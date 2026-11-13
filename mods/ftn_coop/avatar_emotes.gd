extends SkeletonModifier3D

const WARDROBE := "res://scripts/player/wardrobe.gd"
const EMOTE_LIBRARY := "res://scripts/player/emotes.gd"
const SOURCE_ARMS := ["clavicle","upperarm","lowerarm","hand"]
const BODY_ARMS := ["Clavicle","UpperArm","Forearm","Hand"]
const SOURCE_FINGERS := ["index","middle","ring","pinky","thumb"]
const BODY_THUMB := ["Proximal","Intermediate","Distal"]

var look_pitch := 0.0
var _head := -1
var _to_skeleton := Quaternion.IDENTITY
var _bones: Array[int] = []
var _rests: Array[Quaternion] = []
var _target := PackedFloat32Array()
var _rotations: Array[Quaternion] = []
var _mix := 0.0
var _age := 0.0
var _emote := ""
var _serial := 0

static func capture(hands: Node3D) -> PackedFloat32Array:
	if not is_instance_valid(hands): return PackedFloat32Array()
	var skeleton: Skeleton3D = hands.get("_sk")
	if not is_instance_valid(skeleton): return PackedFloat32Array()
	var relative := (hands.global_basis.inverse()*skeleton.global_basis).orthonormalized()
	var data := PackedFloat32Array()
	for side in ["l","r"]:
		for part in SOURCE_ARMS:
			if not _capture_bone(data,skeleton,relative,part+"_"+side): return PackedFloat32Array()
		for part in SOURCE_FINGERS:
			for joint in range(1,4):
				if not _capture_bone(data,skeleton,relative,"%s_0%d_%s" % [part,joint,side]): return PackedFloat32Array()
	return data

static func _capture_bone(data: PackedFloat32Array, skeleton: Skeleton3D, relative: Basis, name: String) -> bool:
	var index := skeleton.find_bone(name)
	if index<0: return false
	var rest := skeleton.get_bone_global_rest(index).basis.orthonormalized()
	var pose := skeleton.get_bone_global_pose(index).basis.orthonormalized()
	var rotation := (relative*pose*rest.inverse()*relative.inverse()).get_rotation_quaternion().normalized()
	if not rotation.is_finite(): return false
	data.append_array(PackedFloat32Array([rotation.x,rotation.y,rotation.z,rotation.w]))
	return true

func configure(skeleton: Skeleton3D, body: Node3D) -> void:
	_to_skeleton = (skeleton.global_basis.inverse()*body.global_basis).orthonormalized().get_rotation_quaternion()
	_head = skeleton.find_bone("Handyman Head")
	for side in ["L","R"]:
		for part in BODY_ARMS: _bones.append(skeleton.find_bone("Handyman "+side+" "+part))
		for finger in range(1,5):
			for joint in ["","1","2"]: _bones.append(skeleton.find_bone("Handyman %s Finger%d%s" % [side,finger,joint]))
		var thumb := "Left" if side=="L" else "Right"
		for joint in BODY_THUMB: _bones.append(skeleton.find_bone("Handyman "+thumb+"_Thumb"+joint))
	for index in _bones:
		_rests.append(skeleton.get_bone_global_rest(index).basis.orthonormalized().get_rotation_quaternion() if index>=0 else Quaternion.IDENTITY)

func set_emote(id: String, serial: int) -> void:
	if serial<=_serial: return
	_serial = serial
	_target.clear()
	_emote = id if _allows(id) else ""

func apply_sample(sample: Dictionary) -> void:
	if _emote.is_empty() or sample.serial!=_serial: return
	_target = sample.bones
	_age = 0.0

func _allows(id: String) -> bool:
	if id.is_empty() or not ResourceLoader.exists(EMOTE_LIBRARY): return false
	var emotes := load(EMOTE_LIBRARY)
	if not emotes.is_rude(id): return true
	if not ResourceLoader.exists(WARDROBE): return false
	var settings := ConfigFile.new()
	load(WARDROBE).write(settings)
	return settings.get_value("emotes","rude",false)==true

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton==null: return
	_age += delta
	# The two rigs have different bone axes. Transfer the source's change
	# from its rest pose in character space, then apply it to Bubba's rest.
	if _head>=0:
		var look := _to_skeleton*Quaternion(Vector3.RIGHT,look_pitch)*_to_skeleton.inverse()
		var head := skeleton.get_bone_global_pose(_head)
		head.basis = Basis(look)*head.basis
		skeleton.set_bone_global_pose(_head,head)
	var playing := not _target.is_empty() and _age<0.35
	_mix = move_toward(_mix,1.0 if playing else 0.0,delta*8.0)
	if is_zero_approx(_mix):
		_rotations.clear()
		return
	if playing:
		var weight := 1.0-exp(-24.0*delta)
		for index in _bones.size():
			var offset := 4*index
			var rotation := Quaternion(_target[offset],_target[offset+1],_target[offset+2],_target[offset+3]).normalized()
			if index==_rotations.size(): _rotations.append(rotation)
			else: _rotations[index] = _rotations[index].slerp(rotation,weight)
	var pitch := Quaternion(Vector3.RIGHT,look_pitch)
	for index in _rotations.size():
		var bone := _bones[index]
		if bone<0: continue
		var animated := skeleton.get_bone_global_pose(bone)
		var basis := animated.basis.orthonormalized().get_rotation_quaternion()
		var motion := _to_skeleton*pitch*_rotations[index]*_to_skeleton.inverse()
		animated.basis = Basis(basis.slerp(motion*_rests[index],_mix)).scaled(animated.basis.get_scale())
		skeleton.set_bone_global_pose(bone,animated)
