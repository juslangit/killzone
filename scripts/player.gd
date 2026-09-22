class_name Player
extends CharacterBody3D

## The man with the rifle.
##
## Movement and aim are deliberately independent, the way Diablo and every
## twin-stick shooter since has done it: WASD drives him around the world while
## the mouse decides which way he is facing. That is why the animation set needs
## a separate backward and sideways cycle - he spends most of his time moving in
## a direction he is not looking in.

signal fired(from: Vector3, to: Vector3, hit: bool)

const GRAVITY := 22.0
const RUN_SPEED := 5.5
const CROUCH_SPEED := 2.2
const AIR_CONTROL := 0.55
const JUMP_VELOCITY := 6.4
const ACCELERATION := 14.0
const TURN_SPEED := 14.0

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.15
const CROUCH_BLEND_SPEED := 9.0

const FIRE_INTERVAL := 0.11
const SHOOT_RANGE := 60.0
## How fast the upper body takes the recoil on, and lets go of it afterwards.
const SHOOT_BLEND_SPEED := 40.0
const SHOOT_DECAY := 6.0
## The recoil clip is 0.30 s; stop holding the blend on once it has recovered.
const SHOOT_HOLD := 0.26

## The rifle mesh, as the glTF importer names it. Godot already hangs it off a
## BoneAttachment3D for the rifle bone, so parenting the muzzle marker to it is
## enough to make shots leave the barrel - and to make the flash follow recoil.
const GUN_MESH := "Object_33"
## Fallback if the rifle cannot be found: roughly where his hands are.
const CHEST_MUZZLE := Vector3(0.0, 1.25, -0.45)

@onready var _collider: CollisionShape3D = $Collider
@onready var _model: Node3D = $Model
@onready var _tree: AnimationTree = $AnimationTree

var _capsule: CapsuleShape3D
var _anim_player: AnimationPlayer
var _muzzle: Marker3D

var _crouching := false
var _crouch_blend := 0.0
var _air_blend := 0.0
var _shoot_blend := 0.0
var _recoiling := false
var _fire_cooldown := 0.0
var _aim_point := Vector3.ZERO


func _ready() -> void:
	_capsule = _collider.shape as CapsuleShape3D
	_anim_player = _model.find_child("AnimationPlayer", true, false)
	assert(_anim_player != null, "player.glb did not import an AnimationPlayer")

	AnimationRig.apply_loop_modes(_anim_player)
	_tree.anim_player = _tree.get_path_to(_anim_player)
	_tree.tree_root = AnimationRig.build(_anim_player)
	_tree.active = true

	_attach_muzzle()
	_aim_point = global_position - global_transform.basis.z


## Put a marker at the end of the barrel, so the muzzle stays put through every
## animation including the recoil kick.
##
## The exact offset is measured from the rifle mesh rather than typed in: take
## its bounding box, walk to the end of its longest axis, and keep whichever end
## sits further from his hips. That is the barrel, and it stays correct if the
## character is ever rebuilt with a different weapon.
func _attach_muzzle() -> void:
	_muzzle = Marker3D.new()
	var gun: MeshInstance3D = _model.find_child(GUN_MESH, true, false)
	if gun == null:
		push_warning("Rifle mesh not found; firing from the chest instead.")
		_muzzle.position = CHEST_MUZZLE
		add_child(_muzzle)
		return

	var box := gun.get_aabb()
	var axis := 0
	for i in 3:
		if box.size[i] > box.size[axis]:
			axis = i
	var reach := Vector3.ZERO
	reach[axis] = box.size[axis] * 0.5
	var centre := box.get_center()

	gun.add_child(_muzzle)
	var near := gun.to_global(centre - reach)
	var far := gun.to_global(centre + reach)
	var hips := global_position + Vector3.UP
	_muzzle.position = centre + (reach if far.distance_to(hips) > near.distance_to(hips) else -reach)


func _physics_process(delta: float) -> void:
	_update_aim()
	_update_stance(delta)
	_update_movement(delta)
	_update_shooting(delta)
	_update_animation(delta)


## Where the mouse is pointing, as a spot on the ground at roughly chest height.
## Intersecting a flat plane rather than raycasting the world keeps the aim
## steady - a world raycast would snap the crosshair around whenever the ray
## clipped the character's own shoulder.
func _update_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, global_position.y + 1.0)
	var hit = plane.intersects_ray(
		camera.project_ray_origin(mouse), camera.project_ray_normal(mouse)
	)
	if hit != null:
		_aim_point = hit


func _update_stance(delta: float) -> void:
	var wants_crouch := Input.is_action_pressed("crouch") and is_on_floor()
	# Do not let him stand up into a ceiling. There is none on this map yet, but
	# the check belongs with the crouch rather than being bolted on later.
	if _crouching and not wants_crouch and _blocked_above():
		wants_crouch = true
	_crouching = wants_crouch

	var target := 1.0 if _crouching else 0.0
	_crouch_blend = move_toward(_crouch_blend, target, CROUCH_BLEND_SPEED * delta)

	var height: float = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_blend)
	_capsule.height = height
	_collider.position.y = height * 0.5


func _blocked_above() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * CROUCH_HEIGHT,
		global_position + Vector3.UP * (STAND_HEIGHT + 0.1)
	)
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


func _update_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and not _crouching:
		velocity.y = JUMP_VELOCITY

	var input := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	# Screen-relative, not character-relative: pressing W always sends him up
	# the screen no matter which way he happens to be facing.
	var wish := Vector3(input.x, 0.0, input.y)
	if wish.length() > 1.0:
		wish = wish.normalized()

	var speed: float = lerpf(RUN_SPEED, CROUCH_SPEED, _crouch_blend)
	var grip := ACCELERATION * (1.0 if is_on_floor() else AIR_CONTROL)
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, grip * delta)
	velocity.z = move_toward(velocity.z, target.z, grip * delta)

	move_and_slide()
	_face_aim(delta)


func _face_aim(delta: float) -> void:
	var to_aim := _aim_point - global_position
	to_aim.y = 0.0
	if to_aim.length_squared() < 0.0025:
		return
	var wanted := atan2(-to_aim.x, -to_aim.z)
	rotation.y = rotate_toward(rotation.y, wanted, TURN_SPEED * delta)


func _update_shooting(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	if Input.is_action_pressed("shoot") and _fire_cooldown <= 0.0:
		_fire_cooldown = FIRE_INTERVAL
		_fire()
		_recoiling = true
		# Seek the recoil back to its first frame, which is the kick itself.
		_tree.set("parameters/shoot_seek/seek_request", 0.0)

	# Ramp the upper body onto the recoil rather than snapping it there. The
	# attack is fast enough to still land on the kick - two physics ticks - but
	# not so fast that the first shot of a burst pops.
	if _recoiling:
		_shoot_blend = move_toward(_shoot_blend, 1.0, SHOOT_BLEND_SPEED * delta)
		# Let go once the clip has played out, so the blend fades instead of
		# being held on a recoil that has already finished recovering.
		if _tree.get("parameters/shoot_seek/current_position") >= SHOOT_HOLD:
			_recoiling = false
	else:
		_shoot_blend = move_toward(_shoot_blend, 0.0, SHOOT_DECAY * delta)


func _fire() -> void:
	var from := _muzzle.global_position
	# Aim from the barrel at the cursor, not straight down the barrel - the rifle
	# is carried across the body, so its own forward axis is not where he looks.
	var target := _aim_point
	var direction := (target - from).normalized()
	var to := from + direction * SHOOT_RANGE

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		to = hit.position
	fired.emit(from, to, not hit.is_empty())


func _update_animation(delta: float) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var top: float = lerpf(RUN_SPEED, CROUCH_SPEED, _crouch_blend)

	# The blend spaces want the direction of travel in the character's own frame,
	# so that running while facing sideways picks the strafe cycle.
	var local := global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var move := Vector2.ZERO
	if ground_speed > 0.05:
		move = Vector2(local.x, -local.z).normalized() * clampf(ground_speed / top, 0.0, 1.0)

	_tree.set("parameters/ground/blend_position", move)
	_tree.set("parameters/crouch/blend_position", move)
	_tree.set("parameters/stance/blend_amount", _crouch_blend)
	_tree.set("parameters/fire/blend_amount", _shoot_blend)

	var airborne := 1.0 if not is_on_floor() else 0.0
	if airborne > _air_blend and _air_blend < 0.01:
		_tree.set("parameters/jump_seek/seek_request", 0.0)
	_air_blend = move_toward(_air_blend, airborne, 8.0 * delta)
	_tree.set("parameters/air/blend_amount", _air_blend)


func aim_point() -> Vector3:
	return _aim_point


func is_crouching() -> bool:
	return _crouching
