extends Node3D

const Protocol = preload("res://mods/ftn_coop/protocol.gd")
const AvatarEmotes = preload("res://mods/ftn_coop/avatar_emotes.gd")
const BODY_SCRIPT := "res://scripts/player/bubba.gd"

var _target := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _initialized := false
var _label: Label3D
var _head: Node3D
var _material: StandardMaterial3D
var _body: Node3D
var _emotes: SkeletonModifier3D
var _motion := Vector3.ZERO
var _pose_age := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var material := StandardMaterial3D.new()
	_material = material
	material.albedo_color = Color("e8b654")
	if not _create_native_body(): _create_fallback()
	_label = Label3D.new()
	_label.position.y = 1.95
	_label.font_size = 40
	_label.pixel_size = 0.007
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)

func _create_native_body() -> bool:
	if not ResourceLoader.exists(BODY_SCRIPT): return false
	var script := load(BODY_SCRIPT) as Script
	if script==null or not script.can_instantiate(): return false
	_body = script.new()
	add_child(_body)
	var skeleton: Skeleton3D = _body.get("skeleton")
	if not is_instance_valid(skeleton):
		_body.queue_free()
		_body = null
		return false
	_emotes = AvatarEmotes.new()
	_emotes.configure(skeleton,_body)
	skeleton.add_child(_emotes)
	return true

func _create_fallback() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.15
	body.mesh = capsule
	body.material_override = _material
	body.position.y = 0.8
	add_child(body)
	_head = Node3D.new()
	_head.position.y = 1.5
	add_child(_head)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.23
	sphere.height = 0.46
	head.mesh = sphere
	head.material_override = _material
	_head.add_child(head)
	var visor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.33,0.12,0.09)
	visor.mesh = box
	visor.position = Vector3(0,0.03,-0.21)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("17323c")
	visor.material_override = dark
	_head.add_child(visor)

func set_display_name(value: String) -> void:
	if _label!=null: _label.text = value.left(32)

func set_display_color(value: Color) -> void:
	if _material!=null: _material.albedo_color = value
	if _label!=null: _label.modulate = value

func apply_pose(pose: Dictionary) -> void:
	if not pose.get("position") is Vector3 or not pose.get("rotation") is Vector3: return
	if not pose.position.is_finite() or not pose.rotation.is_finite() or pose.position.length()>2048.0: return
	if not Protocol.valid_pose_animation(pose): return
	_motion = pose.get("motion",Vector3.ZERO)
	_pose_age = 0.0
	_target = pose.position
	_yaw = pose.rotation.y
	_pitch = clampf(pose.rotation.x,-1.5,1.5)
	if not _initialized:
		visible = true
		position = _target
		rotation.y = _yaw
		_initialized = true
	if _emotes!=null and pose.has("emote_sample"): _emotes.apply_sample(pose.emote_sample)

func apply_emote(id: String, serial: int) -> void:
	if _emotes!=null and Protocol.valid_emote(id): _emotes.set_emote(id,serial)

func _process(delta: float) -> void:
	if not _initialized: return
	var weight := 1.0-exp(-18.0*delta)
	position = position.lerp(_target,weight)
	rotation.y = lerp_angle(rotation.y,_yaw,weight)
	if _head!=null: _head.rotation.x = lerp_angle(_head.rotation.x,_pitch,weight)
	if _body==null: return
	_pose_age += delta
	var motion := _motion if _pose_age<0.5 else Vector3.ZERO
	_body.set("speed",motion.x)
	_body.set("crouch",lerpf(_body.get("crouch"),motion.y,weight))
	_body.set("air",lerpf(_body.get("air"),absf(motion.z),weight))
	_body.set("fall",lerpf(_body.get("fall"),maxf(-motion.z,0.0),weight))
	_emotes.look_pitch = lerpf(_emotes.look_pitch,_pitch,weight)
