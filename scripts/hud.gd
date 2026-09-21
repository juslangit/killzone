extends Control

## Crosshair and control list.
##
## The system cursor is hidden and replaced with a drawn reticle, because the
## cursor is the aim in this game and an arrow pointing up and to the left is a
## poor thing to aim with.

const RETICLE := Color(0.55, 1.0, 0.62, 0.92)
const RETICLE_HOT := Color(1.0, 0.72, 0.35, 0.98)

@export var player_path: NodePath

var _player: Player
var _spread := 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as Player
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var firing := Input.is_action_pressed("shoot")
	_spread = move_toward(_spread, 7.0 if firing else 0.0, 60.0 * delta)
	if _player:
		$Stance.text = "CROUCHED" if _player.is_crouching() else "STANDING"
	queue_redraw()


func _draw() -> void:
	var centre := get_viewport().get_mouse_position()
	var firing := Input.is_action_pressed("shoot")
	var colour := RETICLE_HOT if firing else RETICLE
	var gap := 9.0 + _spread
	var arm := 15.0
	var thickness := 3.0

	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(
			centre + direction * gap,
			centre + direction * (gap + arm),
			colour, thickness, true
		)
	draw_circle(centre, 2.2, colour)
