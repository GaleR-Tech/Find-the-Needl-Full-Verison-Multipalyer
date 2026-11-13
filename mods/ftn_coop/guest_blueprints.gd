extends RefCounted

const BLUEPRINT := "res://scripts/build/blueprint.gd"
const LIBRARY := "res://scripts/build/blueprint_library.gd"
const ROWS := "res://scripts/build/blueprint_rows.gd"
const DESIGNER := "res://scripts/build/blueprint_designer.gd"
const PLACER := "res://scripts/build/blueprint_placer.gd"
const GHOST := "res://scripts/build/blueprint_ghost.gd"
const BUILD_MANAGER := "res://scripts/build/build_manager.gd"
const SLOT := "bp:"
const MAX_ROWS := 512
const MAX_ENCODED := 1024*1024
const MAX_COMPRESSED := 44*1024
const BLUEPRINT_FIELDS := ["id","name","mk","rows","tags","orders","paints","pins","unplugged","feeds"]
const PAIR_FIELDS := ["tags","orders","paints","pins","feeds"]
const ENDPOINT_ROWS := ["railing","wall","roof","conveyor","enclosed_conveyor","underground_belt","water_main","underground_pipe","belt_gate"]
const BOOLEAN_FIELDS := ["off","glass","windowed","floor_ports","floor_back","tee","cross","down","shut","double"]
const INTEGER_FIELDS := ["paint","door","rows","tier","sections","head_turn","forced_side","priority_side","entry","out_lane","segments","storey"]
const ID_FIELDS := ["mat","recipe","order"]
const NUMBER_FIELDS := ["port_reach","port_r","rise","pitch","h","port","cannon_yaw","cannon_throw","out_reach","rate","port_back","out_front","head","throw","aim","power","riser","left_share","stem_wait","angle","strength","turn","tilt","height","bright","setting","run","width","roll","rods","h0","w","t","post"]
const SHAPE_POINT := 1
const SHAPE_POINTS := 2
const SHAPE_DIR := 3
const SHAPE_YAW := 4
const SHAPE_SPAN := 5
const SHAPE_XFORM := 6
const SHAPE_LINE := 7
const SHAPE_LINKS := 8
const SHAPE_PARAMS := 9

func in_hand(player: Node) -> bool:
	if not is_instance_valid(player): return false
	var build: Variant = player.get("build")
	return build is Node and build.has_method("blueprint_in_hand") and build.call("blueprint_in_hand")==true

func placement_payload(player: Node) -> Dictionary:
	if not in_hand(player): return _error("ACTION_INVALID")
	var placer: Object = player.get("build").get("blueprint_placer")
	var at: Vector3 = placer.call("_landing")
	if not at.is_finite() or is_instance_valid(placer.get("onto")): return _error("PLACEMENT_REFUSED")
	var native: Dictionary = placer.get("bp").call("to_dict")
	var blueprint := {}
	for key in BLUEPRINT_FIELDS: blueprint[key] = native[key]
	var payload := {
		"blueprint":blueprint, "at":at, "turns":placer.get("turns"),
		"auto_connect":placer.get("auto_connect"), "locked":placer.get("locked"),
	}
	if not _valid_payload(payload): return _error("ACTION_INVALID")
	var codec: RefCounted = load("res://mods/ftn_coop/value_codec.gd").new()
	var encoded: Dictionary = codec.encode(payload,MAX_ENCODED)
	if not encoded.ok: return encoded
	if encoded.value.size()<48*1024: return _ok(payload)
	var packed: PackedByteArray = encoded.value.compress(FileAccess.COMPRESSION_ZSTD)
	if packed.is_empty() or packed.size()>MAX_COMPRESSED: return _error("PAYLOAD_TOO_LARGE")
	return _ok({"data":packed,"bytes":encoded.value.size()})

func handle_input(player: Node, event: InputEvent) -> bool:
	if not in_hand(player): return false
	var build: Node = player.get("build")
	if build.get("blueprint_placer").call("input",event): return true
	if not InputMap.has_action("build_cancel") or not event.is_action_pressed("build_cancel"): return false
	player.call("put_away_build")
	return true

func confirm_placement(player: Node, blueprint_id: String) -> void:
	if in_hand(player) and player.get("build_id")==SLOT+blueprint_id:
		player.get("build").get("blueprint_placer").call("reset")

func apply_host(actor: Node, payload: Dictionary) -> Dictionary:
	if payload.has("data"):
		var decoded := _unpack(payload)
		if not decoded.ok: return decoded
		payload = decoded.value
	if not _valid_payload(payload): return _error("ACTION_INVALID")
	if not is_instance_valid(actor) or not actor is Node3D or not actor.is_inside_tree(): return _error("ACTOR_NOT_READY")
	var tool: Variant = actor.get("build")
	if not tool is Node3D or not tool.has_method("in_control_room") or not tool.get("builds") is Node: return _error("CAPABILITY_MISSING")
	if tool.call("in_control_room"): return _error("PLACEMENT_REFUSED")
	var source: Dictionary = payload.blueprint
	var designer: Script = load(DESIGNER)
	var side := float(designer.call("side_of",source.mk))
	var half := side*0.5+0.5
	var eye: Vector3 = actor.call("eye_position")
	var max_reach := maxf(float(tool.get("_reach")),side*0.5+7.0)
	if eye.distance_to(payload.at)>max_reach+1.0: return _error("OUT_OF_REACH")
	var native_rows: Script = load(ROWS)
	var shape: Dictionary = native_rows.get_script_constant_map().get("FIXTURE_PARAMS",{})
	for row in source.rows:
		if not _valid_row(row,native_rows,shape,half): return _error("ACTION_INVALID")
	if not _valid_annotations(source,half): return _error("ACTION_INVALID")

	var native: Dictionary = source.duplicate(true)
	native.format = 1
	var blueprint: Object = load(BLUEPRINT).call("from_dict",native)
	if blueprint==null or blueprint.get("rows").size()!=source.rows.size(): return _error("ACTION_INVALID")
	var prices := _identify_rows(blueprint.get("rows"))
	if not prices.ok: return prices
	blueprint.set("ids",prices.value.ids)
	blueprint.set("costs",prices.value.costs)
	if not load(LIBRARY).call("usable",blueprint): return _error("BUILD_LOCKED")
	return _place(tool,blueprint,prices.value.costs,payload)

func _valid_payload(payload: Dictionary) -> bool:
	if payload.size()!=5 or not payload.get("at") is Vector3 or not payload.at.is_finite() or payload.at.length()>2048.0:
		return false
	if typeof(payload.get("turns"))!=TYPE_INT or payload.turns<0 or payload.turns>3:
		return false
	if not payload.get("auto_connect") is bool or not payload.get("locked") is bool:
		return false
	var source: Variant = payload.get("blueprint")
	if not source is Dictionary or source.size()!=BLUEPRINT_FIELDS.size(): return false
	if not _safe_id(source.get("id"),64) or source.id.is_empty() or not source.get("name") is String or source.name.length()>128 or source.name.to_utf8_buffer().has(0): return false
	if typeof(source.get("mk"))!=TYPE_INT or source.mk<1 or source.mk>3: return false
	for key in BLUEPRINT_FIELDS.slice(3):
		if not source.get(key) is Array or source[key].size()>MAX_ROWS: return false
	return not source.rows.is_empty()

func _unpack(payload: Dictionary) -> Dictionary:
	if payload.size()!=2 or not payload.get("data") is PackedByteArray or payload.data.is_empty() or payload.data.size()>MAX_COMPRESSED:
		return _error("ACTION_INVALID")
	if not _integer(payload.get("bytes"),1,MAX_ENCODED): return _error("ACTION_INVALID")
	var raw: PackedByteArray = payload.data.decompress(payload.bytes,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=payload.bytes: return _error("ACTION_INVALID")
	var decoded: Dictionary = load("res://mods/ftn_coop/value_codec.gd").new().decode(raw,MAX_ENCODED)
	return decoded if decoded.ok and decoded.value is Dictionary else _error("ACTION_INVALID")

func _valid_row(row: Variant, rows: Script, fixtures: Dictionary, half: float) -> bool:
	if not row is Dictionary or not _safe_id(row.get("type"),64) or not rows.call("allowed_row",row): return false
	var kind: String = row.type
	if kind=="fixture":
		if not _safe_id(row.get("kind"),64) or not fixtures.has(row.kind) or not row.get("p") is Dictionary: return false
	elif kind in ENDPOINT_ROWS:
		if not _point(row.get("a"),half) or not _point(row.get("b"),half) or row.a.is_equal_approx(row.b): return false
	elif kind=="belt_meter":
		if not row.get("xform") is Transform3D: return false
	elif not _point(row.get("position"),half):
		return false
	for key in row:
		if not key is String: return false
		if key=="p" and kind=="fixture":
			for param in row.p:
				if not param is String or not fixtures[row.kind].has(param) or not _valid_field(row.p[param],int(fixtures[row.kind][param]),param,row.kind,half):
					return false
		else:
			if not _valid_field(row[key],int(rows.call("shape_of",kind,key)),key,kind,half): return false
	return true

func _valid_field(value: Variant, shape: int, key: String, kind: String, half: float) -> bool:
	match shape:
		SHAPE_POINT: return _point(value,half)
		SHAPE_POINTS:
			if not value is Array or value.size()>MAX_ROWS: return false
			for point in value:
				if not _point(point,half): return false
			return true
		SHAPE_DIR:
			return value is Vector3 and value.is_finite() and is_equal_approx(value.length_squared(),1.0)
		SHAPE_YAW: return _number(value,TAU+0.01)
		SHAPE_SPAN:
			return value is Vector2 and value.is_finite() and value.x>0 and value.y>0 and maxf(value.x,value.y)<=half*2
		SHAPE_XFORM:
			return value is Transform3D and _point(value.origin,half) and value.basis.is_finite() and value.basis.is_equal_approx(value.basis.orthonormalized()) and is_equal_approx(value.basis.determinant(),1.0)
		SHAPE_LINE: return _integer(value,0,MAX_ROWS)
		SHAPE_LINKS:
			if not value is Array or value.size()>MAX_ROWS: return false
			for link in value:
				if not link is Dictionary or not _point(link.get("at"),half): return false
				for property in link:
					if not _safe_id(property,32) or (property!="at" and not _scalar(link[property])): return false
			return true
		0:
			if key=="text" and kind=="yard_sign":
				return value is String and value.length()<=1024 and not value.to_utf8_buffer().has(0)
			if key=="kind" and kind not in ["roof","wall"]: return _safe_id(value,64) or _integer(value,0,32)
			if key=="icon" and kind=="yard_sign": return _safe_sign_icon(value)
			if key in ["glow","fed"]: return value is bool or _integer(value,0,8)
			if key=="s" and kind=="marking": return _safe_id(value,64) or _integer(value,0,32)
			if key=="type" or key in ID_FIELDS: return _safe_id(value,128)
			if key in BOOLEAN_FIELDS: return value is bool
			if key in INTEGER_FIELDS: return _integer(value,-1,256)
			if key in NUMBER_FIELDS: return _number(value,128.0)
			if key in ["fg","bg","colour","tint"]:
				return (value is Color and _number(value.r,4) and _number(value.g,4) and _number(value.b,4) and _number(value.a,4)) or _safe_id(value,32) or _integer(value,0,256)
			if key in ["refuses","takes","filters"]:
				if not value is Array and not value is PackedStringArray and not value is PackedInt32Array: return false
				if value.size()>32: return false
				for item in value:
					if not _safe_id(item,64) and not _integer(item,-1,256): return false
				return true
			if key=="taps":
				if not value is Array or value.size()>24: return false
				for tap in value:
					if not tap is Array or tap.size()!=2 or not _point(tap[0],4.0) or not _valid_field(tap[1],SHAPE_DIR,"","",half):
						return false
				return true
			if key in ["manual","closed","resume","wall"]: return value is bool or _integer(value,-1,256) or _number(value,128)
			return _scalar(value)
	return false

func _valid_annotations(source: Dictionary, half: float) -> bool:
	for key in PAIR_FIELDS:
		for pair in source[key]:
			if not pair is Array or pair.size()!=2 or not _point(pair[0],half): return false
			if key in ["pins","feeds"]:
				if not _point(pair[1],half): return false
			elif not _integer(pair[1],-1,256): return false
	for at in source.unplugged:
		if not _point(at,half): return false
	return true

func _identify_rows(rows: Array) -> Dictionary:
	var scratch: Node = load(BUILD_MANAGER).new()
	var ids := PackedStringArray()
	var costs := PackedFloat32Array()
	ids.resize(rows.size())
	costs.resize(rows.size())
	# Gates attach to a conveyor. Restore those after the plan's own belts.
	var order: Array[int] = []
	var gates: Array[int] = []
	for index in rows.size():
		if rows[index].type=="belt_gate": gates.append(index)
		else: order.append(index)
	order.append_array(gates)
	var valid := true
	for index in order:
		var before := scratch.get_child_count()
		scratch.call("_restore_row",rows[index].duplicate(true))
		if scratch.get_child_count()!=before+1:
			valid = false
			break
		var building: Node = scratch.get_child(before)
		var id: String = scratch.call("id_of",building)
		var cost: float = float(building.call("build_cost")) if building.has_method("build_cost") else -1.0
		if id.is_empty() or not is_finite(cost) or cost<0 or cost>10000000:
			valid = false
			break
		ids[index] = id
		costs[index] = cost
	scratch.free()
	return _ok({"ids":ids,"costs":costs}) if valid else _error("ACTION_INVALID")

func _place(tool: Node3D, blueprint: Object, fixed: PackedFloat32Array, payload: Dictionary) -> Dictionary:
	var placer: Object = load(PLACER).new(tool)
	placer.set("bp",blueprint)
	placer.set("turns",payload.turns)
	placer.set("auto_connect",payload.auto_connect)
	placer.set("_fixed",fixed)
	var at: Vector3 = payload.at
	if not payload.locked:
		var landing: Vector3 = placer.call("_landing")
		if not landing.is_finite() or at.distance_to(landing)>0.8: return _error("OUT_OF_REACH")
		at = landing
	if _duplicates_deck(tool.get("builds"),blueprint.get("rows"),at,payload.turns):
		return _error("PLACEMENT_REFUSED")
	var ghost: Node3D = load(GHOST).new(tool)
	tool.add_child(ghost)
	ghost.top_level = true
	ghost.visible = false
	placer.set("ghost",ghost)
	ghost.call("show_blueprint",blueprint)
	placer.call("_find_open_ends")
	ghost.global_transform = Transform3D(Basis(Vector3.UP,float(payload.turns)*PI*0.5),at)
	var previous_eval: Dictionary = tool.get("_eval")
	placer.call("_judge",ghost.global_transform)
	var reason: String = placer.get("_reason")
	if not reason.is_empty():
		ghost.queue_free()
		return _error("PLACEMENT_REFUSED")

	# Record native placement counters and clear props as the normal build click
	# does. The remote controller's equipped item and preview stay untouched.
	var builds: Node = tool.get("builds")
	var caught: Array[Node] = []
	var remember := func(node: Node) -> void: caught.append(node)
	builds.child_entered_tree.connect(remember)
	placer.call("_verdict",reason)
	placer.call("primary")
	builds.child_entered_tree.disconnect(remember)
	tool.set("_eval",previous_eval)
	ghost.queue_free()
	if placer.get("placed")<1: return _error("PLACEMENT_REFUSED")
	tool.set("placed",int(tool.get("placed"))+1)
	tool.call("clear_under",caught)
	return _ok(payload.blueprint.id)

func _duplicates_deck(builds: Node, rows: Array, at: Vector3, turns: int) -> bool:
	var turn := Basis(Vector3.UP,float(turns)*PI*0.5)
	var positions := {}
	for deck in builds.get("platforms"):
		if is_instance_valid(deck) and not deck.is_queued_for_deletion():
			positions[(deck as Node3D).global_position.snapped(Vector3.ONE*0.01)] = true
	for row in rows:
		if row.type!="platform": continue
		var position: Vector3 = (turn*row.position+at).snapped(Vector3.ONE*0.01)
		if positions.has(position): return true
		positions[position] = true
	return false

func _safe_sign_icon(value: Variant) -> bool:
	if not value is String: return false
	var pair: PackedStringArray = value.split(":")
	return _safe_id(value,64) if pair.size()==1 else pair.size()==2 and pair[0] in ["build","item","tool","needle","tech"] and _safe_id(pair[1],64)

func _point(value: Variant, half: float) -> bool:
	return value is Vector3 and value.is_finite() and absf(value.x)<=half and absf(value.y)<=60.0 and absf(value.z)<=half

func _safe_id(value: Variant, limit: int) -> bool:
	if not value is String or value.length()>limit or value.to_utf8_buffer().has(0): return false
	var lower: String = value.to_lower()
	if lower.contains("/") or lower.contains("\\") or lower.begins_with("..") or lower.contains(":"): return false
	for suffix in [".gd",".tscn",".tres",".res",".pck",".blueprint"]:
		if lower.ends_with(suffix): return false
	return true

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value)==TYPE_INT and value>=minimum and value<=maximum

func _number(value: Variant, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and absf(float(value))<=maximum

func _scalar(value: Variant) -> bool:
	return value is bool or _number(value,128) or _safe_id(value,128)

func _ok(value: Variant) -> Dictionary:
	return {"ok":true,"code":"OK","value":value}

func _error(code: String) -> Dictionary:
	return {"ok":false,"code":code,"value":null}
