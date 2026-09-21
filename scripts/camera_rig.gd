extends Node3D

## The bird's-eye camera.
##
## Fixed angle, fixed distance, no player control - the view Diablo uses. The rig
## follows the player's position but never his rotation, which is what keeps
## "forward" meaning "up the screen" however he happens to be turned.

@export var target_path: NodePath
@export var follow_speed := 7.0
@export var height := 8.0
@export var distance := 5.8
@export var pitch_degrees := -54.1

## How far the view drifts toward the cursor. A little lead makes it feel like
## he is looking where you are aiming without taking the camera off him.
@export var aim_lead := 0.18
@export var max_lead := 4.0

var _target: Player
var _camera: Camera3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Player
	_camera = $Camera3D
	_camera.position = Vector3(0.0, height, distance)
	_camera.rotation_degrees = Vector3(pitch_degrees, 0.0, 0.0)
	if _target:
		global_position = _target.global_position


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var focus := _target.global_position
	var lead := (_target.aim_point() - focus) * aim_lead
	lead.y = 0.0
	focus += lead.limit_length(max_lead)
	global_position = global_position.lerp(focus, clampf(follow_speed * delta, 0.0, 1.0))
