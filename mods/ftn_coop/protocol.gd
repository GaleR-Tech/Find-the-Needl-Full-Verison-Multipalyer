extends RefCounted

const MAX_PACKET := 65536
const TYPES := ["HELLO","WELCOME","REJECT","ROSTER","WORLD_REQUEST","SNAPSHOT_BEGIN","SNAPSHOT_CHUNK","WORLD_READY","ACTION","ACTION_RESULT","EVENT","POSE","EMOTE","RESYNC","MARKER_REQUEST","MARKERS","STATUS_PROBE","STATUS_REPLY","PLAYER_STATUS","LOAD_STATUS"]
const EMOTES := ["wave","victory","thumbs_up","point","finger_guns","rock_on","ok","beckon","salute","fist_pump","count","call_me","thumbs_down","middle_finger","up_yours","jerk_off","spit_flip","pee","yap"]
const EMOTE_BONES := 38

func encode(message: Dictionary) -> Dictionary:
	if not _envelope_valid(message): return _error("INVALID_PAYLOAD")
	return _codec().encode(message, MAX_PACKET)

func decode(bytes: PackedByteArray) -> Dictionary:
	var result: Dictionary = _codec().decode(bytes, MAX_PACKET)
	if not result.ok: return result
	if not result.value is Dictionary or not _envelope_valid(result.value): return _error("INVALID_PAYLOAD")
	return result

func _envelope_valid(message: Dictionary) -> bool:
	if message.size() != 4 or typeof(message.get("protocol")) != TYPE_INT or message.protocol != 1: return false
	if not message.get("type") is String or message.type not in TYPES or not message.get("session") is String or not message.get("body") is Dictionary: return false
	if message.session == "": return message.type in ["HELLO", "REJECT"]
	if not valid_id(message.session): return false
	var body: Dictionary = message.body
	if message.type=="EMOTE":
		for field in body:
			if field not in ["id","serial","peer","_connection"]: return false
		return valid_emote(body.get("id")) and _valid_serial(body.get("serial")) and (not body.has("peer") or _valid_serial(body.peer))
	if message.type in ["POSE","ACTION"] and body.has("pose"):
		return body.pose is Dictionary and valid_pose_animation(body.pose,message.type=="POSE")
	return true

static func valid_emote(value: Variant) -> bool:
	return value is String and (value.is_empty() or value in EMOTES)

static func valid_pose_animation(pose: Dictionary, allow_sample: bool=true) -> bool:
	if pose.has("motion"):
		var motion: Variant = pose.motion
		if not motion is Vector3 or not motion.is_finite() or motion.x<0.0 or motion.x>24.0 or motion.y<0.0 or motion.y>1.0 or motion.z< -1.0 or motion.z>1.0: return false
	if pose.has("emote_sample"):
		var sample: Variant = pose.emote_sample
		if not allow_sample or not sample is Dictionary or sample.size()!=2 or not _valid_serial(sample.get("serial")): return false
		var bones: Variant = sample.get("bones")
		if not bones is PackedFloat32Array or bones.size()!=4*EMOTE_BONES: return false
		for index in range(0,bones.size(),4):
			var bone := Quaternion(bones[index],bones[index+1],bones[index+2],bones[index+3])
			if not bone.is_finite() or absf(bone.length_squared()-1.0)>0.01: return false
	return true

static func _valid_serial(value: Variant) -> bool:
	return typeof(value)==TYPE_INT and value>0 and value<=9007199254740991

func valid_id(value: Variant) -> bool:
	if not value is String or value.length() != 32: return false
	for character in value:
		if not "0123456789abcdef".contains(character): return false
	return true

func _codec() -> RefCounted:
	return load(get_script().resource_path.get_base_dir() + "/value_codec.gd").new()

func _error(code: String) -> Dictionary:
	return {"ok":false,"code":code,"value":null}
