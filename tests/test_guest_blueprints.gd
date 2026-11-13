extends RefCounted

const MODULE := "res://mods/ftn_coop/guest_blueprints.gd"

class LocalBlueprint extends RefCounted:
	func to_dict() -> Dictionary:
		return {"id":"local-7","name":"Deck","mk":1,"rows":[{"type":"platform","position":Vector3.ZERO,"span":Vector2(2,2)}],"tags":[],"orders":[],"paints":[],"pins":[],"unplugged":[],"feeds":[],"ids":["deck"],"costs":[5.0]}

class LocalPlacer extends RefCounted:
	var bp := LocalBlueprint.new()
	var turns := 2
	var locked := true
	var auto_connect := false
	var onto: Node
	var _at := Vector3(4,0,1)
	func _landing() -> Vector3: return _at
	func input(event: InputEvent) -> bool:
		if event.is_action_pressed("build_cancel") and locked:
			locked = false
			return true
		return false
	func reset() -> void: locked = false

class LocalTool extends Node:
	var blueprint_placer := LocalPlacer.new()
	func blueprint_in_hand() -> bool: return true

class LocalPlayer extends Node:
	var build := LocalTool.new()
	var build_id := "bp:local-7"
	var stowed := false
	func _init() -> void: add_child(build)
	func put_away_build() -> void: stowed = true

func run(_tree: SceneTree) -> Array:
	var errors := []
	var script: Script = load(MODULE) if ResourceLoader.exists(MODULE) else null
	if script==null: return ["Blueprint placement module is missing."]
	var module: RefCounted = script.new()
	var player := LocalPlayer.new()
	var request: Dictionary = module.placement_payload(player)
	if not request.ok or request.value.at!=Vector3(4,0,1) or request.value.turns!=2 or request.value.auto_connect:
		errors.append("The request lost the native placement target, orientation or options.")
	if request.ok and (request.value.blueprint.has("ids") or request.value.blueprint.has("costs")):
		errors.append("The request sent client-derived build ids or prices.")
	if request.ok:
		for invalid in [
			{"at":Vector3.INF},
			{"turns":4},
			{"blueprint":{"path":"user://my-file.blueprint"}},
		]:
			var altered: Dictionary = request.value.duplicate(true)
			altered.merge(invalid,true)
			if module.apply_host(null,altered).code!="ACTION_INVALID":
				errors.append("Accepted malformed network blueprint fields: "+str(invalid.keys()))
		var invalid: Dictionary = request.value.duplicate(true)
		invalid.blueprint.costs = [0.0]
		if module.apply_host(null,invalid).code!="ACTION_INVALID":
			errors.append("Accepted client-supplied prices.")
	if not InputMap.has_action("build_cancel"): InputMap.add_action("build_cancel")
	var cancel := InputEventAction.new()
	cancel.action = &"build_cancel"
	cancel.pressed = true
	if not module.handle_input(player,cancel) or player.stowed or player.build.blueprint_placer.locked:
		errors.append("Native cancel should release a locked preview before stowing.")
	if not module.handle_input(player,cancel) or not player.stowed:
		errors.append("Native cancel should put the unlocked blueprint away.")
	player.build.blueprint_placer.locked = true
	module.confirm_placement(player,"other-3")
	if not player.build.blueprint_placer.locked:
		errors.append("Confirmation reset a different blueprint.")
	module.confirm_placement(player,"local-7")
	if player.build.blueprint_placer.locked:
		errors.append("Own confirmation should release the matching placement anchor.")
	player.free()
	return errors
