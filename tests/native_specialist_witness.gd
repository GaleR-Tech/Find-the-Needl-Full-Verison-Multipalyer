extends RefCounted

const FIXTURES := {"assembler.gd":Vector3(15,0,10),"depot.gd":Vector3(22,0,10),
	"power_pole.gd":Vector3(29,0,10),"pipe_pump.gd":Vector3(36,0,10)}

func seed(adapter: RefCounted) -> void:
	var builds: Node = adapter.nodes.builds
	adapter.nodes.tech.call("grant_everything")
	adapter.nodes.state.set("money",20000.0)
	adapter.nodes.state.call("depot_add","paper_roll",5)
	builds.call("add_assembler",FIXTURES["assembler.gd"],0.0)
	builds.call("add_depot",FIXTURES["depot.gd"],0.0,false)
	builds.call("add_power_pole",FIXTURES["power_pole.gd"],0.0,false,false)
	builds.call("add_pipe_pump",FIXTURES["pipe_pump.gd"],Basis.IDENTITY,1,0.0)
	var other: Node3D = builds.call("add_power_pole",Vector3(27,0,8),0.0,false,false)
	builds.call("join_machine",other,_fixture(builds,"pipe_pump.gd"))

func exercise(check: Node, adapter: RefCounted, runtime: Node) -> Dictionary:
	var menus: RefCounted = runtime.guest_menus._specialists
	var player: Node3D = adapter.nodes.player
	var builds: Node = adapter.nodes.builds
	var tree := check.get_tree()
	var result := {}
	for scenario in [["assembler.gd","production_panel.gd","_on_recipe","motor", "recipe","motor"],
		["depot.gd","depot_panel.gd","_on_take","", "paper_roll",4],
		["power_pole.gd","pole_panel.gd","_finish_naming","", "line_name","Coop test"],
		["pipe_pump.gd","water_panel.gd","_on_switch","", "is_switched_off",true]]:
		var target := _fixture(builds,scenario[0])
		if target==null: return _error("FIXTURE_"+scenario[0],result)
		player.global_position = target.global_position+Vector3(0,0,2.5)
		player.call("set_look",0.0,-0.25)
		await tree.physics_frame
		if not menus._open_target(target): return _error("OPEN_"+scenario[0],result)
		var panel: Node = menus._watched
		if scenario[0]=="depot.gd": panel.call("_on_pick","paper_roll")
		var sequence: int = runtime.network._sequence+1
		if scenario[0]=="power_pole.gd":
			panel.call("_on_name_line")
			var field: LineEdit = panel.get("_name_edit")
			field.text = "Coop test"
			field.focus_exited.emit()
		else:
			var button := _button(menus,scenario[1],scenario[2],scenario[3])
			if button==null: return _error("BUTTON_"+scenario[0],result)
			button.pressed.emit()
		var status: Dictionary = await _wait_result(check,sequence)
		if not status.ok: return _error(scenario[0]+"_"+status.code,result)
		var actual: Variant
		for frame in range(45):
			await tree.process_frame
			target = _fixture(builds,scenario[0])
			if target==null: continue
			match scenario[4]:
				"recipe": actual = target.get("recipe")
				"paper_roll": actual = adapter.nodes.state.call("depot_count","paper_roll")
				"line_name": actual = target.get("line_name")
				"is_switched_off": actual = target.call("is_switched_off")
			if actual==scenario[5]: break
		if actual!=scenario[5]: return _error("REPLICA_"+scenario[0]+"_"+str(actual),result)
		result[scenario[0]] = actual
		menus.close()
	var at := Vector3(16,0,19)
	player.global_position = at+Vector3(0,0,3)
	player.call("set_look",0.0,-0.50)
	var blueprint := {"id":"guest-deck","name":"Guest / Deck","mk":1,"rows":[{"type":"platform","position":Vector3(0,0.2,0),"span":Vector2(2,2)}],"tags":[],"orders":[],"paints":[],"pins":[],"unplugged":[],"feeds":[]}
	var local_plan: Object = load("res://scripts/build/blueprint.gd").call("from_dict",blueprint.merged({"format":1,"ids":["deck"],"costs":[17.0]}))
	var library: Script = load("res://scripts/build/blueprint_library.gd")
	if String(library.call("save",local_plan,false)).is_empty(): return _error("BLUEPRINT_SAVE",result)
	var catalog: Node = player.get("catalog")
	catalog.call("set_open",true)
	catalog.call("_set_page",2)
	var page: Node = catalog.get("_pages")[2]
	var select := InputEventMouseButton.new()
	select.pressed = true
	select.button_index = MOUSE_BUTTON_LEFT
	select.double_click = true
	page.call("_on_tile_input",select,blueprint.id)
	var module: RefCounted = load("res://mods/ftn_coop/guest_blueprints.gd").new()
	if not module.in_hand(player): return _error("BLUEPRINT_CATALOG_SELECTION",result)
	var placer: Object = player.get("build").get("blueprint_placer")
	placer.set("locked",true)
	placer.set("_at",at)
	var payload: Dictionary = module.placement_payload(player)
	if not payload.ok: return _error("BLUEPRINT_PREVIEW_"+payload.code,result)
	var seq: int = runtime.network._sequence+1
	runtime._on_primary("dig",{"pressed":true})
	var placement: Dictionary = await _wait_result(check,seq)
	if not placement.ok: return _error("BLUEPRINT_"+placement.code,result)
	var placed := false
	for frame in range(45):
		await tree.process_frame
		for deck in builds.get("platforms"):
			if is_instance_valid(deck) and deck.global_position.is_equal_approx(at+Vector3(0,0.2,0)): placed = true
		if placed: break
	if not placed: return _error("BLUEPRINT_REPLICA",result)
	result.blueprint = true
	player.call("put_away_build")
	await tree.physics_frame
	await tree.physics_frame
	var wheel: Control = menus._wheel
	if not is_instance_valid(wheel): return _error("EMOTE_WHEEL",result)
	player.call("capture_mouse",true)
	if not wheel.call("can_open"): return _error("EMOTE_UNAVAILABLE",result)
	var emote_key := InputEventAction.new()
	emote_key.action = &"emote_wheel"
	emote_key.pressed = true
	if not menus.handle_input(emote_key) or not wheel.call("is_open"): return _error("EMOTE_OPEN",result)
	wheel.set("_pick",0)
	emote_key.pressed = false
	menus.handle_input(emote_key)
	var hands: Node3D = adapter.local_emote_hands()
	for frame in range(24):
		await tree.process_frame
		if runtime.network._local_emote=="wave" and hands.get("_emote_t")>0.04:
			result.wave = true
			return {"ok":true,"code":"OK","checks":result}
	return _error("EMOTE_WAVE_"+str(hands.get("_emote_t")),result)

func _fixture(builds: Node, file: String) -> Node3D:
	for target in builds.call("every_placed"):
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		if target.get_script().resource_path.get_file()==file and target.global_position.distance_to(FIXTURES[file])<0.1: return target
	return null

func _button(menus: RefCounted, file: String, method: String, argument: String) -> BaseButton:
	for record in menus._hooks:
		if not is_instance_valid(record.node) or not record.node is BaseButton or record.signal!="pressed": continue
		var original: Callable = record.original
		if not original.is_valid() or original.get_method()!=method or original.get_object().get_script().resource_path.get_file()!=file: continue
		if not argument.is_empty() and original.get_bound_arguments()!=[argument]: continue
		return record.node
	return null

func _wait_result(check: Node, sequence: int) -> Dictionary:
	for frame in range(150):
		await check.get_tree().process_frame
		if check._results.has(sequence): return check._results[sequence]
	return {"ok":false,"code":"TIMEOUT"}

func _error(code: String, result: Dictionary) -> Dictionary:
	return {"ok":false,"code":code,"checks":result}
