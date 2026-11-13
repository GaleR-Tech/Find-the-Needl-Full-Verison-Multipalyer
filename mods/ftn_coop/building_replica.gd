extends RefCounted

# Only these known mutable fields can be restored on existing native nodes.
# Geometry, tiers and unfamiliar fields use the full native restore path.
const LIVE := {
	"hay_generator":["fuel"],
	"hay_compressor":["stored","needles"],
	"hay_silo":["queued","stored","needles"],
	"haystack_scanner":["banked","stored","loads","blocks"],
	"hay_drone":["trips"],
	"assembler":["cycle_duration","cycle_makes","cycle_needles","needles","off","out_id","out_left","out_strands","out_worth","port_last","recipe","run","slots"],
	"depot":["empty","empty_kinds","limits","off","refused"],
	"pipe_pump":["off"],
	"conveyor_splitter":["next_side"],"conveyor_u_splitter":["next_side"],
	"conveyor_t_splitter":["next_side"],"conveyor_joiner":["next_side"],
	"conveyor_u_joiner":["next_side"]
}
const COLLECTION := {
	"hay_generator":"generators","hay_compressor":"compressors",
	"hay_silo":"silos","haystack_scanner":"scanners","hay_drone":"hay_drones",
	"assembler":"every_placed","depot":"every_placed","pipe_pump":"pipe_pumps",
	"conveyor_splitter":"splitters","conveyor_u_splitter":"splitters",
	"conveyor_t_splitter":"splitters","conveyor_joiner":"joiners",
	"conveyor_u_joiner":"joiners"
}

func difference(before: Array, records: Array) -> Dictionary:
	var rows := []
	for index in range(records.size()):
		if before[index]!=records[index]: rows.append({"index":index,"record":records[index]})
	return {"count":records.size(),"rows":rows}

func expand(before: Array, delta: Variant) -> Dictionary:
	if not delta is Dictionary or delta.size()!=2 or typeof(delta.get("count"))!=TYPE_INT or delta.count!=before.size() or delta.count>32768 or not delta.get("rows") is Array or delta.rows.is_empty() or delta.rows.size()>before.size(): return {"ok":false}
	var result: Array = before.duplicate()
	var previous := -1
	for row in delta.rows:
		if not row is Dictionary or row.size()!=2 or typeof(row.get("index"))!=TYPE_INT or row.index<=previous or row.index>=before.size() or not row.get("record") is Dictionary: return {"ok":false}
		previous = row.index
		result[row.index] = row.record
	return {"ok":true,"value":result}

func layout(records: Array) -> Array:
	var result := []
	for record in records:
		var row: Dictionary = record.duplicate()
		for key in LIVE.get(row.get("type",""),[]): row.erase(key)
		result.append(row)
	return result

func update(manager: Node, before: Array, records: Array) -> bool:
	var properties := {}
	for property in manager.get_property_list(): properties[str(property.name)] = true
	for index in range(records.size()):
		var row: Dictionary = records[index]
		if row==before[index]: continue
		var collection: String = COLLECTION.get(row.get("type",""),"")
		var candidates: Variant
		if collection=="every_placed" and manager.has_method(collection): candidates = manager.call(collection)
		elif properties.has(collection): candidates = manager.get(collection)
		else: return false
		if not candidates is Array: return false
		var target: Node3D
		for candidate in candidates:
			if is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and candidate is Node3D and candidate.global_position.is_equal_approx(row.position):
				if collection=="every_placed":
					var script: Script = candidate.get_script()
					if script==null or script.resource_path.get_file()!=row.type+".gd": continue
				if target!=null: return false
				target = candidate
		if target==null: return false
		if row.type=="hay_silo" and target.has_method("from_dict"):
			target.call("from_dict",row)
			continue
		if row.type in ["assembler","depot","pipe_pump"]:
			if not _restore_specialist(target,row,before[index]): return false
			continue
		var fields := {}
		for property in target.get_property_list(): fields[str(property.name)] = true
		for key in LIVE[row.type]:
			if not row.has(key) or row.get(key)==before[index].get(key): continue
			if key=="loads" and target.has_method("restore_loads"):
				target.call("restore_loads",row[key]); continue
			var name: String = "pending_needles" if key=="needles" else key
			if not fields.has(name) or typeof(target.get(name))!=typeof(row[key]): return false
			var value: Variant = row[key]
			target.set(name,value.duplicate(true) if value is Dictionary or value is Array else value)
	return true

func _restore_specialist(target: Node3D, row: Dictionary, before: Dictionary) -> bool:
	if row.type=="assembler":
		if not target.has_method("from_dict"): return false
		target.call("from_dict",row.duplicate(true))
		return true
	if not target.has_method("set_switched_off"): return false
	target.call("set_switched_off",row.get("off",false))
	if row.type=="pipe_pump": return true
	target.call("set_emptying",row.get("empty",false))
	for operation in [["empty_kinds","set_emptying_kind"],["refused","set_refused"]]:
		var selected: Array = row.get(operation[0],[])
		for id in before.get(operation[0],[]):
			if id not in selected: target.call(operation[1],id,false)
		for id in selected: target.call(operation[1],id,true)
	var limits: Dictionary = row.get("limits",{})
	for id in before.get("limits",{}):
		if not limits.has(id): target.call("set_limit",id,-1)
	for id in limits: target.call("set_limit",id,limits[id])
	return true
