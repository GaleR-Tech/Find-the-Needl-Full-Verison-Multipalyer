# Run as an autoload in an isolated copy of the supported native game build.
extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var root := get_tree().root
	var state := root.get_node_or_null("GameState")
	var tech := root.get_node_or_null("Tech")
	var cfg := root.get_node_or_null("Cfg")
	if state==null or tech==null or cfg==null:
		print("NATIVE BLUEPRINT autoloads missing ",root.get_children())
		get_tree().quit(1)
		return
	tech.call("grant_everything")
	state.set("money",1.0e6)
	cfg.set("build_fx",false)
	var world := Node3D.new()
	world.name = "BlueprintTestWorld"
	root.add_child(world)
	var manager: Node = load("res://scripts/build/build_manager.gd").new()
	manager.name = "Builds"
	manager.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(manager)
	var ground := StaticBody3D.new()
	ground.collision_layer = int(cfg.get_script().get_script_constant_map().L_WORLD)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60,1,60)
	collider.shape = box
	ground.position.y = -0.5
	ground.add_child(collider)
	world.add_child(ground)
	var player: Node3D = load("res://scripts/player/player.gd").new()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(player)
	player.position = Vector3(0,0,5)
	player.call("set_look",0.0,-0.65)
	var build: Node = player.get("build")
	build.set("builds",manager)
	var mod: RefCounted = load("res://mods/ftn_coop/guest_blueprints.gd").new()
	var source := {"id":"isolated-deck","name":"Deck","mk":1,"rows":[{"type":"platform","position":Vector3(0,0.2,0),"span":Vector2(2,2)}],"tags":[],"orders":[],"paints":[],"pins":[],"unplugged":[],"feeds":[]}
	var body := {"blueprint":source,"at":Vector3.ZERO,"turns":0,"auto_connect":false,"locked":true}
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("NATIVE BLUEPRINT eye=",player.call("eye_position")," groups=",manager.get("groups"))
	var before: float = state.get("money")
	var remote := body.duplicate(true)
	remote.at = Vector3(500,0,0)
	var out_of_reach: Dictionary = mod.apply_host(player,remote)
	if out_of_reach.code!="OUT_OF_REACH" or float(state.get("money"))!=before:
		print("NATIVE BLUEPRINT range=",out_of_reach)
		get_tree().quit(1)
		return
	state.set("money",0.0)
	var unaffordable: Dictionary = mod.apply_host(player,body)
	if unaffordable.ok or manager.get("platforms").size()!=0:
		print("NATIVE BLUEPRINT funds=",unaffordable)
		get_tree().quit(1)
		return
	state.set("money",before)
	var first: Dictionary = mod.apply_host(player,body)
	print("NATIVE BLUEPRINT first=",first," rows=",manager.call("to_array")," money=",state.get("money"))
	if not first.ok or float(state.get("money"))>=before or manager.get("platforms").size()!=1:
		get_tree().quit(1)
		return
	var after: float = state.get("money")
	var blocked: Dictionary = mod.apply_host(player,body)
	print("NATIVE BLUEPRINT overlap=",blocked," money=",state.get("money"))
	if blocked.ok or after!=float(state.get("money")) or manager.get("platforms").size()!=1:
		get_tree().quit(1)
		return
	print("NATIVE BLUEPRINT PASS")
	get_tree().quit()
