extends RefCounted

class Yard extends Node3D:
	var buildings: Array = []
	var power_poles: Array = []
	var extras: Array = []
	var grid := PowerGrid.new()
	var plugs := Plugs.new()
	var tags := PowerTags.new()

	func every_placed() -> Array: return buildings
	func join_poles(first: Node3D, second: Node3D) -> int:
		grid.linked_nodes = [first, second]
		return 1
	func cut_poles(first: Node3D, second: Node3D) -> int:
		if not grid.linked(first, second): return 0
		grid.linked_nodes.clear()
		return 1
	func join_machine(pole: Node3D, machine: Node3D) -> bool:
		plugs.pins[machine] = pole
		return true
	func cut_machine(machine: Node3D) -> bool:
		plugs.pins.erase(machine)
		plugs.disconnected[machine] = true
		return true

class PowerGrid extends RefCounted:
	var linked_nodes: Array = []
	var label := ""
	var off := false

	func linked(first: Node3D, second: Node3D) -> bool: return first in linked_nodes and second in linked_nodes
	func line_running(_pole: Node3D) -> bool: return not off
	func switch_line(_pole: Node3D, value: bool) -> int:
		off = value
		return 1
	func set_line_name(_pole: Node3D, value: String) -> bool:
		label = value
		return true

class Plugs extends RefCounted:
	var pins: Dictionary = {}
	var disconnected: Dictionary = {}

	func pin_of(machine: Node3D) -> Node3D: return pins.get(machine)
	func unplugged(machine: Node3D) -> bool: return disconnected.get(machine, false)

class PowerTags extends RefCounted:
	var orders: Dictionary = {}
	var groups: Dictionary = {}

	func enabled() -> bool: return true
	func orderable(_machine: Node3D) -> bool: return true
	func taggable(_machine: Node3D) -> bool: return true
	func set_order(machine: Node3D, value: int) -> void: orders[machine] = value
	func set_tag(machine: Node3D, value: int) -> void: groups[machine] = value
	func order_of(machine: Node3D) -> int: return orders.get(machine,1)
	func tag_of(machine: Node3D) -> int: return groups.get(machine,0)

class Building extends Node3D:
	var switched_off := false
	var placement_preview := false
	var recipe := "first"
	func set_switched_off(off: bool) -> void: switched_off = off
	func is_switched_off() -> bool: return switched_off
	func power_ports() -> Array: return []
	func recipes() -> Array: return [{"id":"first"},{"id":"second"},{"id":"locked","locked":true}]
	func set_recipe(id: String) -> void: recipe = id

class Depot extends Building:
	var emptying := false
	var limits := {}
	var emptying_kinds := {}
	var refused := {}
	func set_emptying(on: bool) -> void: emptying = on
	func set_emptying_kind(id: String, on: bool) -> void: emptying_kinds[id] = on
	func is_emptying_kind(id: String) -> bool: return emptying_kinds.get(id,false)
	func set_refused(id: String, on: bool) -> void: refused[id] = on
	func refuses(id: String) -> bool: return refused.get(id,false)
	func set_limit(id: String, n: int) -> void: limits[id] = n
	func limit(id: String) -> int: return limits.get(id,0)

class Valve extends Node3D:
	var setting := 0
	func flow_cap_lps() -> float: return 0.0
	func water_through() -> Array: return []
	func interact(_actor: Node) -> String:
		setting = (setting + 1) % 8
		return ""

class MachinePanel extends Node:
	func _recipe_open(recipe: Dictionary) -> bool: return not recipe.get("locked",false)

class DepotPanel extends Node:
	var player: Node
	var _depot: Node3D
	func limits_open() -> bool: return true
	func step_limit(id: String, way: int) -> void:
		_depot.call("set_limit", id, 25 + 5 * way)
	func take_one(_id: String) -> bool:
		player.set_meta("received", _depot.position)
		return true

class State extends Node:
	func depot_cap(id: String) -> int: return 25 if id == "paper" else 0

class World extends Node3D:
	var machine_panel := MachinePanel.new()
	var depot_panel := DepotPanel.new()
	func _init() -> void:
		add_child(machine_panel)
		add_child(depot_panel)

func run(tree: SceneTree) -> Array[String]:
	var errors: Array[String] = []
	var path := "res://mods/ftn_coop/specialist_actions.gd"
	if not FileAccess.file_exists(path): return ["Host machine actions are missing."]
	var actions: GDScript = load(path)
	var world := World.new()
	var yard := Yard.new()
	var actor := Node3D.new()
	var host := Node3D.new()
	var machine := Building.new()
	var first := Node3D.new()
	var second := Node3D.new()
	var depot := Depot.new()
	var detached := Building.new()
	var valve := Valve.new()
	var state := State.new()
	tree.root.add_child(world)
	world.add_child(yard)
	world.add_child(actor)
	world.add_child(host)
	tree.root.add_child(state)
	state.name = "GameState"
	for building in [machine,first,second,depot,detached,valve]: yard.add_child(building)
	machine.position = Vector3(2,0,0)
	first.position = Vector3(3,0,0)
	second.position = Vector3(4,0,0)
	depot.position = Vector3(5,0,0)
	detached.position = Vector3(6,0,0)
	valve.position = Vector3(3,0,2)
	yard.buildings = [machine,first,second,depot,valve]
	yard.extras = [valve]
	yard.power_poles = [first,second]
	var send := func(target: Node3D, operation: String, fields: Dictionary = {}) -> Dictionary:
		var payload := {"target":target.global_position,"operation":operation}
		payload.merge(fields)
		return actions.apply(actor,world,yard,payload)
	if not send.call(machine,"switch",{"value":true}).ok or not machine.switched_off:
		errors.append("A nearby host machine must accept its native switch setter.")
	if send.call(machine,"switch",{"value":0}).ok or send.call(machine,"switch",{"value":false,"other":Vector3.ZERO}).ok or not machine.switched_off:
		errors.append("Malformed requests must leave the machine unchanged.")
	if send.call(detached,"switch",{"value":true}).ok or detached.switched_off:
		errors.append("A node absent from the build manager is not a placed machine.")
	actor.position = Vector3(100,0,0)
	if send.call(machine,"switch",{"value":false}).ok or not machine.switched_off:
		errors.append("Host position must limit machine interactions.")
	actor.position = Vector3.ZERO
	if send.call(machine,"recipe",{"value":"locked"}).ok or send.call(machine,"recipe",{"value":"unknown"}).ok or machine.recipe != "first":
		errors.append("The host must enforce native recipe membership and lock rules.")
	if not send.call(machine,"recipe",{"value":"second"}).ok or machine.recipe != "second":
		errors.append("An available recipe must use the native setter.")
	if send.call(depot,"depot_limit",{"id":"paper","value":26}).ok or send.call(depot,"depot_refuse",{"id":"arbitrary","value":true}).ok:
		errors.append("Depot settings must validate item identity and native stock cap.")
	if not send.call(depot,"depot_limit",{"id":"paper","value":20}).ok or depot.limit("paper") != 20:
		errors.append("Valid per-item depot limits must reach the selected depot.")
	if not send.call(depot,"depot_limit",{"id":"paper","value":25}).ok or depot.limit("paper") != -1:
		errors.append("A limit at the depot cap must clear the per-depot limit.")
	if not send.call(depot,"depot_limit_step",{"id":"paper","value":-1}).ok or depot.limit("paper") != 20:
		errors.append("Stepping a limit must use the native depot panel logic.")
	world.depot_panel.player = host
	world.depot_panel._depot = null
	if not send.call(depot,"depot_take",{"id":"paper"}).ok or actor.get_meta("received", null) != depot.position or host.has_meta("received"):
		errors.append("A depot withdrawal belongs to the authoritative guest actor.")
	if world.depot_panel.player != host or world.depot_panel._depot != null:
		errors.append("The host depot panel must recover its original context after the guest withdrawal.")
	if send.call(first,"power_join",{"other":machine.position}).ok:
		errors.append("A building with no pole membership cannot be used as a wiring pole.")
	if not send.call(first,"power_join",{"other":second.position}).ok or not yard.grid.linked(first,second):
		errors.append("The host must apply native wiring to a valid pole pair.")
	if not send.call(first,"power_cut",{"other":second.position}).ok or yard.grid.linked(first,second):
		errors.append("Cutting a valid pole pair must remove its host connection.")
	if not send.call(machine,"power_plug",{"other":first.position}).ok or yard.plugs.pin_of(machine) != first:
		errors.append("Machine wiring must change the host's native plug state.")
	if not send.call(machine,"power_unplug").ok or not yard.plugs.unplugged(machine):
		errors.append("Machine unplugging must use native power manager state.")
	if not send.call(machine,"power_order",{"value":2}).ok or yard.tags.order_of(machine) != 2:
		errors.append("The host must apply a machine's valid load-shedding priority.")
	if not send.call(machine,"power_group",{"value":3}).ok or yard.tags.tag_of(machine) != 3:
		errors.append("The host must apply a valid machine power group.")
	if send.call(machine,"power_order",{"value":9}).ok or send.call(machine,"power_group",{"value":10}).ok:
		errors.append("Power settings must reject nonexistent priorities and groups.")
	if send.call(valve,"water_valve",{"value":8}).ok or valve.setting != 0:
		errors.append("The host must reject an unknown valve setting.")
	if not send.call(valve,"water_valve",{"value":7}).ok or valve.setting != 7:
		errors.append("The requested valve setting must be applied via native interaction.")
	if not send.call(valve,"water_valve",{"value":0}).ok or valve.setting != 0:
		errors.append("A valve must cycle from fully closed to fully open.")
	world.free()
	state.free()
	return errors