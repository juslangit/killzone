extends Node

## Development harness: runs the game, drives the controls and saves screenshots
## so a change can be checked without a human at the keyboard.
##
## Pass a mode on the command line: "tour" for one shot of each state, "burst"
## for consecutive frames through a run cycle and a jump.

const OUT := "user://shots/"
const SIZE := Vector2i(1280, 720)

var _held: Array[String] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for f in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(OUT + f)
	get_window().size = SIZE
	add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(0.8).timeout
	if "burst" in OS.get_cmdline_user_args():
		await _burst()
	else:
		await _tour()
	get_tree().quit()

func _hold(actions: Array[String]) -> void:
	for a in _held:
		Input.action_release(a)
	_held.assign(actions)
	for a in _held:
		Input.action_press(a)

func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path(OUT) + name + ".png")
	print("SHOT ", name)

func _burst() -> void:
	var centre := Vector2(SIZE) * 0.5
	Input.warp_mouse(centre + Vector2(340, 0))
	_hold(["move_forward"])
	await _wait(0.5)
	for i in 8:
		await _shot("%02d_run" % i)
		await _wait(0.07)
	_hold([])
	await _wait(0.6)
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	for i in 8:
		await _shot("%02d_jump" % (10 + i))
		await _wait(0.09)

func _tour() -> void:
	var centre := Vector2(SIZE) * 0.5
	Input.warp_mouse(centre + Vector2(260, -140))
	await _wait(1.0)
	await _shot("01_idle")

	_hold(["move_forward"])
	await _wait(0.9)
	await _shot("02_run_forward")

	Input.warp_mouse(centre + Vector2(0, -260))
	_hold(["move_back"])
	await _wait(0.9)
	await _shot("03_backpedal")

	_hold(["move_right"])
	await _wait(0.8)
	await _shot("04_strafe")

	_hold(["crouch"])
	await _wait(0.9)
	await _shot("05_crouch")

	_hold(["crouch", "move_forward"])
	await _wait(0.7)
	await _shot("06_crouch_walk")

	_hold([])
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	await _wait(0.3)
	await _shot("07_jump")

	await _wait(0.9)
	Input.warp_mouse(centre + Vector2(320, 60))
	_hold(["shoot"])
	await _wait(0.4)
	await _shot("08_firing")

	_hold(["shoot", "move_left"])
	await _wait(0.4)
	await _shot("09_fire_on_the_move")
	_hold([])
