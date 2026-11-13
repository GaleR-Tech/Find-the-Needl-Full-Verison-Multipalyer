extends RefCounted

const REACH := 8.0
const TARGET_TOLERANCE_SQUARED := 0.000001
const WATER_SETTINGS := 8
const TAG_COUNT := 8
const DEPOT_OPERATIONS := {
	"depot_empty_kind": ["set_emptying_kind", TYPE_BOOL],
	"depot_refuse": ["set_refused", TYPE_BOOL],
	"depot_limit": ["set_limit", TYPE_INT],
	"depot_limit_step": ["step_limit", TYPE_INT],
	"depot_take": ["take_one", TYPE_NIL],
	"depot_take_all": ["take_all", TYPE_NIL],
}

static func apply(actor: Node, world: Node, builds: Node, payload: Dictionary) -> Dictionary:
	if not actor is Node3D or not actor.is_inside_tree() or not actor.global_position.is_finite():
		return _result(false, "ACTOR_NOT_READY")
	if not is_instance_valid(world) or not world.is_ancestor_of(actor) or not is_instance_valid(builds) or not builds.has_method("every_placed"):
		return _result(false, "WORLD_NOT_READY")
	var operation: Variant = payload.get("operation")
	var at: Variant = payload.get("target")
	if not operation is String or not at is Vector3 or not at.is_finite() or not _type_valid(payload, "target_type"):
		return _result(false, "ACTION_INVALID")
	var pair: bool = operation in ["power_join", "power_cut", "power_plug"]
	var id_required: bool = operation in DEPOT_OPERATIONS or operation in ["power_tag_switch","power_tag_name"]
	var value_required: bool = operation not in ["depot_take", "depot_take_all", "power_join", "power_cut", "power_plug", "power_unplug"]
	var expected_size := 2 + int(payload.has("target_type")) + int(pair) + int(pair and payload.has("other_type")) + int(id_required) + int(value_required)
	if payload.size() != expected_size or (id_required and not payload.has("id")) or (value_required and not payload.has("value")):
		return _result(false, "ACTION_INVALID")
	var other_at: Variant = payload.get("other")
	if pair and (not other_at is Vector3 or not other_at.is_finite() or not _type_valid(payload, "other_type")):
		return _result(false, "ACTION_INVALID")
	var buildings: Array = builds.call("every_placed")
	var target := _target_at(buildings, at, payload.get("target_type", ""))
	if target == null:
		return _result(false, "OUT_OF_REACH")
	var other: Node3D
	if pair:
		other = _target_at(buildings, other_at, payload.get("other_type", ""))
		if other == null or other == target:
			return _result(false, "OUT_OF_REACH")
	if not _can_reach(actor, builds, target, other, operation):
		return _result(false, "OUT_OF_REACH")
	var value: Variant = payload.get("value")
	match operation:
		"switch":
			if not value is bool: return _result(false, "ACTION_INVALID")
			if not target.has_method("set_switched_off") or not target.has_method("is_switched_off"): return _result(false, "ACTION_UNSUPPORTED")
			target.call("set_switched_off", value)
			return _result(target.call("is_switched_off") == value)
		"recipe":
			return _recipe(world, target, value)
		"depot_empty":
			if not value is bool: return _result(false, "ACTION_INVALID")
			if not target.has_method("set_emptying"): return _result(false, "ACTION_UNSUPPORTED")
			target.call("set_emptying", value)
			return _result(target.get("emptying") == value)
		"water_valve":
			return _water_valve(actor, target, value)
		"power_line", "power_pole", "power_name", "power_join", "power_cut", "power_plug", "power_unplug", "power_master", "power_tag_switch", "power_tag_name", "power_order", "power_group":
			return _power(builds, target, other, operation, value, payload.get("id"))
	if operation in DEPOT_OPERATIONS:
		return _depot(actor, world, target, operation, payload.get("id"), value)
	return _result(false, "ACTION_INVALID")

static func _type_valid(payload: Dictionary, key: String) -> bool:
	var hint: Variant = payload.get(key, "")
	return hint is String and hint.length() <= 160

static func _target_at(buildings: Array, at: Vector3, type: String) -> Node3D:
	var found: Node3D
	for candidate in buildings:
		if not is_instance_valid(candidate) or not candidate is Node3D or not candidate.is_inside_tree() or candidate.is_queued_for_deletion():
			continue
		if candidate.global_position.distance_squared_to(at) > TARGET_TOLERANCE_SQUARED or candidate.get("placement_preview") == true:
			continue
		if not type.is_empty():
			var script: Script = candidate.get_script()
			if script == null or type not in [script.resource_path, script.resource_path.get_file()]: continue
		if found != null and found != candidate: return null
		found = candidate
	return found

static func _can_reach(actor: Node3D, builds: Node, target: Node3D, other: Node3D, operation: String) -> bool:
	var from := actor.global_position
	if from.distance_squared_to(target.global_position) <= REACH * REACH:
		return true
	if operation == "power_cut" and other != null:
		return _near_segment(from, target.global_position, other.global_position)
	if operation == "power_unplug":
		var grid: Variant = builds.get("grid")
		if grid != null and grid.has_method("pole_for"):
			var pole: Variant = grid.call("pole_for", target)
			if is_instance_valid(pole) and pole is Node3D and _is_pole(builds, pole):
				return _near_segment(from, target.global_position, pole.global_position)
	return false

static func _near_segment(from: Vector3, a: Vector3, b: Vector3) -> bool:
	return from.distance_squared_to(Geometry3D.get_closest_point_to_segment(from, a, b)) <= REACH * REACH

static func _recipe(world: Node, target: Node3D, id: Variant) -> Dictionary:
	if not id is String or id.is_empty() or id.length() > 64: return _result(false, "ACTION_INVALID")
	if not target.has_method("set_recipe"): return _result(false, "ACTION_UNSUPPORTED")
	var spec: Dictionary = {}
	if target.has_method("recipe_spec"):
		var native_spec: Variant = target.call("recipe_spec", id)
		# Several native recipe lookups return the default for an unknown ID.
		if native_spec is Dictionary and native_spec.get("id") == id: spec = native_spec
	elif target.has_method("recipes"):
		for entry in target.call("recipes"):
			if entry is Dictionary and entry.get("id") == id:
				spec = entry
				break
	if spec.is_empty(): return _result(false, "ACTION_INVALID")
	var panel: Variant = world.get("machine_panel")
	if not is_instance_valid(panel) or not panel.has_method("_recipe_open"): return _result(false, "CAPABILITY_MISSING")
	if panel.call("_recipe_open", spec) != true: return _result(false, "RECIPE_LOCKED")
	if target.get("recipe") != id: target.call("set_recipe", id)
	return _result(target.get("recipe") == id)

static func _depot(actor: Node, world: Node, target: Node3D, operation: String, id: Variant, value: Variant) -> Dictionary:
	var rule: Array = DEPOT_OPERATIONS[operation]
	if not id is String or id.is_empty() or id.length() > 64 or typeof(value) != rule[1]:
		return _result(false, "ACTION_INVALID")
	# Depot stock is shared. The target depot owns its local output settings.
	if not target.has_method("set_emptying") or not target.has_method("limit"):
		return _result(false, "ACTION_UNSUPPORTED")
	var state := world.get_tree().root.get_node_or_null("GameState")
	if state == null or not state.has_method("depot_cap"): return _result(false, "CAPABILITY_MISSING")
	var cap: int = state.call("depot_cap", id)
	if cap <= 0: return _result(false, "ACTION_INVALID")
	var panel: Variant = world.get("depot_panel")
	if operation in ["depot_take", "depot_take_all"]:
		if not is_instance_valid(panel) or not panel.has_method(rule[0]): return _result(false, "CAPABILITY_MISSING")
		var withdrawn: Variant = _call_depot_panel(panel, actor, target, rule[0], [id])
		return _result(withdrawn == true if operation == "depot_take" else int(withdrawn) > 0)
	if operation in ["depot_limit", "depot_limit_step"]:
		if not is_instance_valid(panel) or not panel.has_method("limits_open"): return _result(false, "CAPABILITY_MISSING")
		if panel.call("limits_open") != true: return _result(false, "ACTION_REFUSED")
		if operation == "depot_limit_step":
			if value not in [-1, 1]: return _result(false, "ACTION_INVALID")
			if not panel.has_method(rule[0]): return _result(false, "CAPABILITY_MISSING")
			_call_depot_panel(panel, actor, target, rule[0], [id, value])
			return _result(true)
		if value < -1 or value > cap: return _result(false, "ACTION_INVALID")
		if value == cap: value = -1
	if not target.has_method(rule[0]): return _result(false, "ACTION_UNSUPPORTED")
	target.call(rule[0], id, value)
	return _result(true)

static func _call_depot_panel(panel: Node, actor: Node, target: Node3D, method: String, args: Array) -> Variant:
	var previous_player: Variant = panel.get("player")
	var previous_depot: Variant = panel.get("_depot")
	panel.set("player", actor)
	panel.set("_depot", target)
	var result: Variant = panel.callv(method, args)
	panel.set("_depot", previous_depot)
	panel.set("player", previous_player)
	return result

static func _water_valve(actor: Node, target: Node3D, value: Variant) -> Dictionary:
	if not value is int or value < 0 or value >= WATER_SETTINGS: return _result(false, "ACTION_INVALID")
	if not target.has_method("flow_cap_lps") or not target.has_method("water_through") or not target.has_method("interact"):
		return _result(false, "ACTION_UNSUPPORTED")
	var setting: Variant = target.get("setting")
	if not setting is int or setting < 0 or setting >= WATER_SETTINGS:
		return _result(false, "ACTION_UNSUPPORTED")
	for step in posmod(value - setting, WATER_SETTINGS):
		target.call("interact", actor)
	return _result(target.get("setting") == value)

static func _is_pole(builds: Node, target: Node3D) -> bool:
	var poles: Variant = builds.get("power_poles")
	return _has_building(poles, target) or (target.has_method("wire_point") and target.has_method("link_reach"))

static func _has_building(buildings: Variant, target: Node3D) -> bool:
	# Native arrays have concrete script element types and reject find() on other buildings.
	if buildings is Array:
		for building in buildings:
			if building == target: return true
	return false

static func _power(builds: Node, target: Node3D, other: Node3D, operation: String, value: Variant, id: Variant) -> Dictionary:
	var grid: Variant = builds.get("grid")
	if grid == null: return _result(false, "CAPABILITY_MISSING")
	if operation in ["power_master", "power_tag_switch", "power_tag_name", "power_order", "power_group"]:
		return _power_tags(builds, target, operation, value, id)
	if operation in ["power_plug", "power_unplug"]:
		return _power_machine(builds, target, other, operation)
	if not _is_pole(builds, target):
		return _result(false, "ACTION_UNSUPPORTED")
	match operation:
		"power_line", "power_pole":
			if not value is bool: return _result(false, "ACTION_INVALID")
			var read := "line_running" if operation == "power_line" else "pole_running"
			var set_off := "switch_line" if operation == "power_line" else "switch_pole"
			if not grid.has_method(read) or not grid.has_method(set_off): return _result(false, "CAPABILITY_MISSING")
			grid.call(set_off,target,value)
			return _result(true)
		"power_name":
			if not value is String or value.length() > 120 or "\n" in value or "\r" in value: return _result(false, "ACTION_INVALID")
			if not grid.has_method("set_line_name"): return _result(false, "CAPABILITY_MISSING")
			return _result(grid.call("set_line_name", target, value) == true)
		"power_join", "power_cut":
			if other == null or not _is_pole(builds, other): return _result(false, "ACTION_UNSUPPORTED")
			var connect := operation == "power_join"
			var method := "join_poles" if connect else "cut_poles"
			if not builds.has_method(method) or not grid.has_method("linked"): return _result(false, "CAPABILITY_MISSING")
			if grid.call("linked", target, other) != connect: builds.call(method, other, target)
			return _result(grid.call("linked", target, other) == connect)
	return _result(false, "ACTION_INVALID")

static func _power_machine(builds: Node, target: Node3D, other: Node3D, operation: String) -> Dictionary:
	if not target.has_method("power_ports") or _is_pole(builds, target):
		return _result(false, "ACTION_UNSUPPORTED")
	var plugs: Variant = builds.get("plugs")
	if plugs == null: return _result(false, "CAPABILITY_MISSING")
	if operation == "power_unplug":
		if not plugs.has_method("unplugged") or not builds.has_method("cut_machine"): return _result(false, "CAPABILITY_MISSING")
		if plugs.call("unplugged", target) != true: builds.call("cut_machine", target)
		return _result(plugs.call("unplugged", target) == true)
	if other == null or not _is_pole(builds, other): return _result(false, "ACTION_UNSUPPORTED")
	if not plugs.has_method("pin_of") or not builds.has_method("join_machine"): return _result(false, "CAPABILITY_MISSING")
	if plugs.call("pin_of", target) != other: builds.call("join_machine", other, target)
	return _result(plugs.call("pin_of", target) == other)

static func _power_tags(builds: Node, target: Node3D, operation: String, value: Variant, id: Variant) -> Dictionary:
	var tags: Variant = builds.get("tags")
	if tags == null or not tags.has_method("enabled"): return _result(false, "CAPABILITY_MISSING")
	if tags.call("enabled") != true: return _result(false, "ACTION_UNSUPPORTED")
	if operation == "power_order":
		if not value is int or value < 0 or value > 2: return _result(false, "ACTION_INVALID")
		if not tags.has_method("orderable") or not tags.has_method("set_order") or not tags.has_method("order_of"):
			return _result(false, "CAPABILITY_MISSING")
		if tags.call("orderable", target) != true: return _result(false, "ACTION_UNSUPPORTED")
		tags.call("set_order", target, value)
		return _result(tags.call("order_of", target) == value)
	if operation == "power_group":
		if not value is int or value < -1 or value >= TAG_COUNT: return _result(false, "ACTION_INVALID")
		if not tags.has_method("taggable") or not tags.has_method("set_tag") or not tags.has_method("tag_of"):
			return _result(false, "CAPABILITY_MISSING")
		if tags.call("taggable", target) != true: return _result(false, "ACTION_UNSUPPORTED")
		tags.call("set_tag", target, value)
		return _result(tags.call("tag_of", target) == value)
	if operation=="power_tag_name":
		if not id is int or id<0 or id>=TAG_COUNT or not value is String or value.length()>16 or value.to_utf8_buffer().has(0) or "\r" in value or "\n" in value:
			return _result(false,"ACTION_INVALID")
		if not _has_building(builds.get("switch_boxes"),target): return _result(false,"ACTION_UNSUPPORTED")
		tags.call("rename",id,value)
		return _result(true)
	if not value is bool or (operation == "power_tag_switch" and (not id is int or id < 0 or id >= TAG_COUNT)):
		return _result(false, "ACTION_INVALID")
	if not _has_building(builds.get("switch_boxes"), target): return _result(false, "ACTION_UNSUPPORTED")
	if operation == "power_master":
		if not tags.has_method("switch_all"): return _result(false, "CAPABILITY_MISSING")
		tags.call("switch_all", value)
	else:
		if not tags.has_method("switch"): return _result(false, "CAPABILITY_MISSING")
		tags.call("switch", id, value)
	return _result(true)

static func _result(ok: bool, failure := "ACTION_REFUSED") -> Dictionary:
	return {"ok": ok, "code": "OK" if ok else failure, "value": null}
