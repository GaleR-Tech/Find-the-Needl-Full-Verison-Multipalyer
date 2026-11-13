extends RefCounted

const CONSOLES := {
	"machine_panel":"machine", "depot_panel":"depot", "pole_panel":"pole",
	"water_panel":"shown", "switch_box_panel":"box", "designer_panel":"target"
}
const CALLBACKS := {
	"_on_recipe":"recipe", "_on_empty":"depot_empty", "_on_empty_kind":"depot_empty_kind",
	"_on_take":"depot_take", "_on_take_all":"depot_take_all", "_on_limit":"depot_limit_step",
	"_on_limit_slid":"depot_limit", "_on_refuse":"depot_refuse",
	"_on_pole_switch":"power_pole", "_finish_naming":"power_name",
	"_on_order":"power_order", "_on_group":"power_group", "_on_master":"power_master",
	"_save_now":"designer_save", "_clear_now":"designer_host_only"
}

var _player: Node
var _builds: Node
var _wheel: Node
var _wire: Node
var _panels := {}
var _modes: Array[Dictionary] = []
var _hooks: Array[Dictionary] = []
var _send: Callable
var _watched: Node
var _target: Node3D
var _target_key := {}
var _selection := ""
var _refresh_at := 0
var _designer_buttons: Array[Dictionary] = []

func bind_world(world: Node, send: Callable) -> void:
	detach()
	_player = world.get("player")
	if not is_instance_valid(_player): return
	_send = send
	_builds = world.get("builds")
	for role in CONSOLES:
		var panel: Node = _player.get(role)
		if not is_instance_valid(panel) or not panel.has_method("is_open") or not panel.has_method(CONSOLES[role]): continue
		_panels[role] = panel
		_enable_panel(panel)
		if role=="designer_panel":
			for field in ["_clear","_load"]:
				var button: Button = panel.get(field)
				if is_instance_valid(button):
					_designer_buttons.append({"node":button,"disabled":button.disabled})
					button.disabled = true
	_wire = _player.get("wire_mode")
	_wheel = world.get_node_or_null("EmoteWheelLayer/EmoteWheel")
	if is_instance_valid(_wire): _enable_panel(_wire)
	if is_instance_valid(_wheel): _enable_panel(_wheel)
	const EMOTES := "res://scripts/player/emotes.gd"
	if ResourceLoader.exists(EMOTES):
		var hands: Node = load(EMOTES).hands_of(_player)
		if is_instance_valid(hands): _enable_panel(hands)

func _enable_panel(panel: Node) -> void:
	_modes.append({"node":panel,"mode":panel.process_mode,"input":panel.is_processing_input(),
		"unhandled":panel.is_processing_unhandled_input(),"keys":panel.is_processing_unhandled_key_input()})
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_suppress_input(panel)

func _suppress_input(panel: Node) -> void:
	panel.set_process_input(false)
	panel.set_process_unhandled_input(false)
	panel.set_process_unhandled_key_input(false)

func _open() -> Node:
	for panel in _panels.values():
		if _is_open(panel): return panel
	return null

func _is_open(panel: Variant) -> bool:
	return is_instance_valid(panel) and panel.call("is_open")==true

func blocks_gameplay() -> bool:
	return _open()!=null or _is_open(_wheel)

func close() -> void:
	_watched = null
	_target = null
	_target_key.clear()
	for panel in _panels.values():
		if _is_open(panel): panel.call("close")
	if _is_open(_wheel): _wheel.call("close",false)
	if _is_open(_wire): _wire.call("end")

func open_interaction() -> bool:
	if not is_instance_valid(_player) or not _player.has_method("_open_console"): return false
	var target: Node3D = _player.call("_console_under")
	if target==null and is_instance_valid(_builds):
		var eye: Vector3 = _player.call("eye_position")
		var look: Vector3 = _player.call("look_direction")
		for query in ["switch_box_under","pole_under","water_under"]:
			target = _builds.call(query,eye,look)
			if target!=null: break
		if target==null and _player.has_method("designer_under"): target = _player.call("designer_under")
	if target==null and is_instance_valid(_builds):
		var build: Node = _player.get("build")
		var aimed: Variant = build.call("dismantle_target") if is_instance_valid(build) else null
		if aimed is Node3D and _script_name(aimed)=="pipe_valve.gd": target = aimed
	if target==null: return false
	if _script_name(target)=="pipe_valve.gd":
		_request("water_valve",target,posmod(int(target.get("setting"))+1,8))
		return true
	return _open_target(target)

func _open_target(target: Node3D) -> bool:
	if _script_name(target)=="blueprint_designer.gd" and _panels.has("designer_panel"):
		var designer: Node = _panels.designer_panel
		_designer_call(designer,"open",[target])
	elif not _can_open(target) or not _player.call("_open_console",target): return false
	var panel := _open()
	if panel==null:
		if _player.has_method("close_consoles"): _player.call("close_consoles")
		return false
	if _script_name(target) in ["power_pole.gd","switch_box.gd","pipe_pump.gd","water_main.gd"]:
		# The native rebuild refreshes readouts and gauge state without ticking
		# production or cargo in the guest world.
		if is_instance_valid(_builds) and _builds.has_method("_rewire_now"): _builds.call("_rewire_now")
	_watch(panel,target)
	return _watched!=null

func _can_open(target: Node3D) -> bool:
	if not is_instance_valid(_builds): return true
	var type := _script_name(target)
	if type in ["power_pole.gd","water_main.gd","pipe_pump.gd","switch_box.gd","depot.gd"]: return true
	# These have dedicated native consoles outside the production dashboard.
	if type in ["piston_rake.gd","excavator.gd","crane.gd","pelletizer.gd","tube_launcher.gd","jump_pad.gd",
		"yard_fan.gd","hay_silo.gd","rob_arm.gd","robotic_arm.gd","hay_drone.gd","needle_cabinet.gd",
		"needle_radar.gd","blueprint_designer.gd","yard_sign.gd","paint_board.gd"]: return false
	return target.has_method("set_switched_off") or target.has_method("recipe_spec")

func handle_input(event: InputEvent) -> bool:
	if _is_open(_wheel):
		if event.is_action_pressed("ui_cancel"):
			_wheel.call("close",false)
		elif event.is_action_released("emote_wheel"):
			_wheel.call("close",true)
		else: _wheel.call("_input",event)
		return true
	if _open()!=null:
		if not event.is_echo() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
			var focus: Control = _player.get_viewport().gui_get_focus_owner()
			if focus is LineEdit and not event.is_action_pressed("ui_cancel"): return false
			close()
			return true
		return false
	if not event.is_echo() and is_instance_valid(_wheel) and event.is_action_pressed("emote_wheel") and _wheel.call("can_open"):
		_wheel.call("open")
		_suppress_input(_wheel)
		return true
	if Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or event.is_echo(): return false
	return _handle_wire(event)

func _handle_wire(event: InputEvent) -> bool:
	if not is_instance_valid(_wire) or not event.is_pressed(): return false
	if _is_open(_wire):
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("secondary") or event.is_action_pressed("interact"):
			_wire.call("end")
			return true
		if not event.is_action_pressed("primary"): return false
		var from: Node3D = _wire.call("from_pole")
		if not is_instance_valid(from) or from.is_queued_for_deletion():
			_wire.call("end")
			return true
		var pole: Node3D = _wire.call("hovered")
		var machine: Node3D = _wire.call("hovered_machine")
		if is_instance_valid(pole) and pole!=from:
			var grid: Variant = _builds.get("grid")
			var linked: bool = grid.call("linked",from,pole)
			_request("power_cut" if linked else "power_join",pole,null,"",from)
		elif is_instance_valid(machine):
			var plugs: Variant = _builds.get("plugs")
			if plugs.call("pin_of",machine)==from: _request("power_unplug",machine)
			else: _request("power_plug",machine,null,"",from)
		else: _cut_aimed_wire()
		return true
	if event.is_action_pressed("secondary") and _player.has_method("wire_target"):
		var pole: Node3D = _player.call("wire_target")
		if pole!=null:
			_wire.call("begin",pole)
			return true
	return false

func _cut_aimed_wire() -> void:
	var drop: Node3D = _wire.call("aimed_drop")
	if is_instance_valid(drop):
		_request("power_unplug",drop)
		return
	var span: Array = _wire.call("aimed_span")
	if span.size()>=2 and span[0] is Node3D and span[1] is Node3D:
		_request("power_cut",span[0],null,"",span[1])

func _watch(panel: Node, target: Node3D) -> void:
	_watched = panel
	_target = target
	_selection = ""
	if panel==null: return
	_target_key = {"at":target.global_position,"type":_script_name(target)}
	_hook_tree(panel)

func refresh() -> void:
	if not is_instance_valid(_player): return
	for record in _modes:
		if is_instance_valid(record.node): _suppress_input(record.node)
	for record in _designer_buttons:
		if is_instance_valid(record.node): record.node.disabled = true
	if not is_instance_valid(_watched): return
	if not is_instance_valid(_target) or _target.is_queued_for_deletion():
		_reopen()
		return
	if not _is_open(_watched):
		_watched = null
		return
	if Time.get_ticks_msec()<_refresh_at: return
	_refresh_at = Time.get_ticks_msec()+100
	if _watched==_panels.get("depot_panel"): _selection = str(_watched.get("_picked"))
	_hook_tree(_watched)

func _reopen() -> void:
	var panel := _watched
	var key := _target_key.duplicate()
	var selected := _selection
	_watched = null
	if _is_open(panel): panel.call("close")
	if not is_instance_valid(_builds) or not _builds.has_method("every_placed"): return
	for target in _builds.call("every_placed"):
		if not is_instance_valid(target) or not target is Node3D: continue
		if not target.global_position.is_equal_approx(key.at) or _script_name(target)!=key.type: continue
		if _open_target(target) and _watched==_panels.get("depot_panel") and not selected.is_empty(): _watched.call("_on_pick",selected)
		return

func _hook_tree(panel: Node) -> void:
	_hooks = _hooks.filter(func(record): return is_instance_valid(record.node))
	var pending: Array[Node] = [panel]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if _script_name(node)=="tag_lines.gd": _hook_tag_lines(panel,node)
		for source in [["pressed",0],["item_selected",1],["value_changed",1],["toggled",1],["focus_exited",0]]:
			if not node.has_signal(source[0]): continue
			for connection in node.get_signal_connection_list(source[0]):
				var original: Callable = connection.callable
				var owner: Object = original.get_object()
				if owner!=panel and _script_name(owner) not in ["production_panel.gd","priority_tabs.gd"]: continue
				var method := str(original.get_method())
				var operation: String = CALLBACKS.get(method,"")
				if method=="_on_switch": operation = _switch_operation(panel)
				if panel==_panels.get("designer_panel") and node==panel.get("_load"): operation = "designer_host_only"
				if operation.is_empty(): continue
				var args := original.get_bound_arguments()
				var callback := _pressed.bind(panel,owner,operation,args) if source[1]==0 else _changed.bind(panel,node,owner,operation,args)
				_replace(node,source[0],connection,callback)
				if operation=="depot_limit" and node is Slider and not node.drag_ended.is_connected(_depot_drag_finished.bind(node,panel)):
					node.drag_ended.connect(_depot_drag_finished.bind(node,panel))

func _hook_tag_lines(panel: Node, lines: Node) -> void:
	var rows: Array = lines.get("_rows")
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary: continue
		var name: LineEdit = row.get("name")
		var button: Button = row.get("switch")
		if is_instance_valid(name):
			for connection in name.text_submitted.get_connections():
				if connection.callable.get_object()==lines:
					_replace(name,"text_submitted",connection,_tag_name.bind(panel,index))
		if is_instance_valid(button):
			for connection in button.pressed.get_connections():
				if connection.callable.get_object()==lines:
					_replace(button,"pressed",connection,_tag_switch.bind(panel,index))

func _replace(node: Node, signal_name: String, connection: Dictionary, callback: Callable) -> void:
	node.disconnect(signal_name,connection.callable)
	node.connect(signal_name,callback)
	_hooks.append({"node":node,"signal":signal_name,"original":connection.callable,"flags":connection.flags,"callback":callback})

func _tag_switch(panel: Node, id: int) -> void:
	if _watched==panel and is_instance_valid(_target):
		_request("power_tag_switch",_target,_builds.get("tags").call("running",id),id)

func _tag_name(value: String, panel: Node, id: int) -> void:
	if _watched==panel and is_instance_valid(_target): _request("power_tag_name",_target,value,id)

func _switch_operation(panel: Node) -> String:
	return "power_line" if panel==_panels.get("pole_panel") else "switch"

func _pressed(panel: Node, owner: Object, operation: String, args: Array) -> void:
	_route(panel,owner,operation,args)

func _changed(value: Variant, panel: Node, control: Node, owner: Object, operation: String, args: Array) -> void:
	if operation=="depot_limit" and control is Slider:
		if not control.has_focus() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return
	if operation=="power_group" and control is OptionButton:
		value = int(value)-1
	_route(panel,owner,operation,[value]+args)

func _depot_drag_finished(changed: bool, slider: Slider, panel: Node) -> void:
	if changed: _route(panel,panel,"depot_limit",[slider.value])

func _route(panel: Node, owner: Object, operation: String, args: Array) -> void:
	if not is_instance_valid(_target) or _watched!=panel or not _is_open(panel): return
	if operation=="designer_host_only": return
	if operation=="designer_save":
		_designer_call(panel,"_save_now",[])
		return
	var value: Variant = args[0] if not args.is_empty() else null
	var id := ""
	if panel==_panels.get("depot_panel") and operation.begins_with("depot_"):
		id = str(panel.get("_picked")) if operation!="depot_empty" else ""
	match operation:
		"switch": value = not bool(_target.call("is_switched_off")) if _target.has_method("is_switched_off") else not bool(_target.get("switched_off"))
		"depot_empty": value = not bool(_target.get("emptying"))
		"depot_empty_kind": value = not bool(_target.call("is_emptying_kind",id))
		"depot_refuse":
			id = String(value)
			value = not bool(_target.call("refuses",id))
		"depot_limit_step": value = int(value)
		"depot_limit": value = int(value)
		"power_pole": value = _builds.get("grid").call("pole_running",_target)
		"power_line": value = _builds.get("grid").call("line_running",_target)
		"power_name": value = panel.get("_name_edit").text
		"power_master": value = _builds.get("tags").call("any_running")
	if operation in ["power_order","power_group"]:
		var machine: Node3D = owner.get("_machine")
		if is_instance_valid(machine): _request(operation,machine,value)
		return
	_request(operation,_target,value,id)

func _designer_call(panel: Node, method: String, arguments: Array) -> void:
	# Blueprint capture exports arm save rows. Use the same read-only arm
	# copies as live world capture while the native panel reads the pad.
	var capture: RefCounted = load("res://mods/ftn_coop/live_build_capture.gd").new()
	if is_instance_valid(_builds) and _builds.has_method("to_array"):
		var arms: Array = _builds.get("robotic_arms")
		if not arms.is_empty() and not capture.capture(_builds).ok: return
		if not arms.is_empty():
			_builds.set("robotic_arms",capture.arm_copies())
			panel.callv(method,arguments)
			_builds.set("robotic_arms",arms)
			capture.close()
			return
	panel.callv(method,arguments)

func _request(operation: String, target: Node3D, value: Variant=null, id: Variant="", other: Node3D=null) -> void:
	if not _send.is_valid() or not is_instance_valid(target): return
	var payload := {"operation":operation,"target":target.global_position,"target_type":_script_name(target)}
	if value!=null: payload.value = value
	if id is int or (id is String and not id.is_empty()): payload.id = id
	if is_instance_valid(other):
		payload.other = other.global_position
		payload.other_type = _script_name(other)
	_send.call("machine_config",payload)

func _script_name(object: Object) -> String:
	if not is_instance_valid(object): return ""
	var script: Script = object.get_script()
	return script.resource_path.get_file() if script!=null else ""

func detach() -> void:
	close()
	for record in _hooks:
		if not is_instance_valid(record.node): continue
		if record.signal=="value_changed" and record.node is Slider and _panels.has("depot_panel"):
			var finished := _depot_drag_finished.bind(record.node,_panels.depot_panel)
			if record.node.drag_ended.is_connected(finished): record.node.drag_ended.disconnect(finished)
		if record.node.is_connected(record.signal,record.callback): record.node.disconnect(record.signal,record.callback)
		if record.original.is_valid() and not record.node.is_connected(record.signal,record.original):
			record.node.connect(record.signal,record.original,record.flags)
	for record in _modes:
		if not is_instance_valid(record.node): continue
		record.node.process_mode = record.mode
		record.node.set_process_input(record.input)
		record.node.set_process_unhandled_input(record.unhandled)
		record.node.set_process_unhandled_key_input(record.keys)
	_hooks.clear()
	_modes.clear()
	for record in _designer_buttons:
		if is_instance_valid(record.node): record.node.disabled = record.disabled
	_designer_buttons.clear()
	_panels.clear()
	_player = null
	_builds = null
	_wheel = null
	_wire = null
	_send = Callable()
