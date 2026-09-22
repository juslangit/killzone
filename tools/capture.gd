extends Node

## Development harness: runs the game, drives the controls and saves screenshots
## so a change can be checked without a human at the keyboard.
##
## Pass a mode on the command line: "tour" for one shot of each state, "burst"
## for consecutive frames through a run cycle and a jump.

const OUT := "user://shots/"
const SIZE := Vector2i(1280, 720)
const CARD_SIZE := Vector2i(1600, 886)

var _held: Array[String] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for f in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(OUT + f)
	get_window().size = CARD_SIZE if "card" in OS.get_cmdline_user_args() else SIZE
	add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(0.8).timeout
	if "burst" in OS.get_cmdline_user_args():
		await _burst()
	elif "card" in OS.get_cmdline_user_args():
		await _card()
	elif "facing" in OS.get_cmdline_user_args():
		await _facing()
	elif "strafe" in OS.get_cmdline_user_args():
		await _strafe()
	elif "clips" in OS.get_cmdline_user_args():
		await _clips()
	elif "fire" in OS.get_cmdline_user_args():
		await _fire_frames()
	elif "recoil" in OS.get_cmdline_user_args():
		await _recoil()
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


## One wide hero frame for the portfolio card: firing on the move.
func _card() -> void:
	var centre := Vector2(CARD_SIZE) * 0.5
	Input.warp_mouse(centre + Vector2(430, 130))
	_hold(["move_left", "move_forward"])
	await _wait(0.9)
	_hold(["move_left", "move_forward", "shoot"])
	await _wait(0.35)
	await _shot("card_hero")


## Close on the character, aimed in each of the four screen directions. The
## camera sits behind and above, so aiming below him turns him to face it: that
## frame must show his face, and the one aiming above must show his back.
func _facing() -> void:
	var centre := Vector2(SIZE) * 0.5
	var rig := get_node("/root/Capture/Main/CameraRig")
	rig.height = 4.6
	rig.distance = 5.2
	rig.aim_lead = 0.0
	rig._camera.position = Vector3(0.0, rig.height, rig.distance)
	rig._camera.rotation_degrees = Vector3(-38.0, 0.0, 0.0)
	rig._camera.fov = 45.0
	for aim in [["toward_camera_should_show_FACE", Vector2(0, 300)],
				["away_should_show_BACK", Vector2(0, -300)],
				["screen_right", Vector2(340, 0)],
				["screen_left", Vector2(-340, 0)]]:
		Input.warp_mouse(centre + aim[1])
		await _wait(1.0)
		await _shot(String(aim[0]))


## Aiming at screen right, his own right hand side points down the screen. So
## moving down the screen must look like a sidestep to HIS right, and moving up
## the screen like a sidestep to his left. If the two look identical, or swapped,
## the strafe clips are mirrored.
func _strafe() -> void:
	var centre := Vector2(SIZE) * 0.5
	var rig := get_node("/root/Capture/Main/CameraRig")
	rig.height = 5.0
	rig.distance = 5.6
	rig.aim_lead = 0.0
	rig._camera.position = Vector3(0.0, rig.height, rig.distance)
	rig._camera.rotation_degrees = Vector3(-40.0, 0.0, 0.0)
	Input.warp_mouse(centre + Vector2(400, 0))
	for run in [["to_his_RIGHT_down_screen", "move_back"],
				["to_his_LEFT_up_screen", "move_forward"]]:
		_hold([])
		await _wait(0.5)
		_hold([String(run[1])])
		await _wait(0.45)
		for i in 3:
			await _shot("%s_%d" % [run[0], i])
			await _wait(0.1)
	_hold([])


## Freeze the player facing the camera and drive the locomotion blend space by
## hand. Seen head on, a sidestep to HIS right travels to the viewer's left, so
## these two frames must be mirror images of each other and not identical.
func _clips() -> void:
	var player := get_node("/root/Capture/Main/Player") as Player
	var rig := get_node("/root/Capture/Main/CameraRig")
	rig.set_physics_process(false)
	rig.global_position = player.global_position
	rig._camera.position = Vector3(0.0, 2.4, 5.0)
	rig._camera.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	await _wait(0.3)
	player.set_physics_process(false)
	player.rotation.y = PI   # face +Z, straight at the camera
	var tree := player.get_node("AnimationTree") as AnimationTree
	for probe in [["strafe_right_should_go_viewer_LEFT", Vector2(1, 0)],
				  ["strafe_left_should_go_viewer_RIGHT", Vector2(-1, 0)],
				  ["run_forward_toward_camera", Vector2(0, 1)],
				  ["run_backward_away", Vector2(0, -1)]]:
		tree.set("parameters/ground/blend_position", probe[1])
		await _wait(0.9)
		await _shot(String(probe[0]))


## A fixed close framing for the animation-review modes.
##
## Rather than computing a distance from a field of view and trusting it - which
## was wrong twice, because how fov maps to the frame depends on keep_aspect -
## this places the camera, measures where the character's head and feet actually
## land on screen, and corrects. Two passes are enough, and it prints the result
## so the framing is a checked number rather than something eyeballed.
func _study_camera(fill := 0.78) -> void:
	var player := get_node("/root/Capture/Main/Player") as Player
	var rig := get_node("/root/Capture/Main/CameraRig")
	var cam: Camera3D = rig._camera
	rig.set_physics_process(false)
	# Measure in the viewport's own coordinates, not the window's. The project
	# stretches canvas items, so the visible rect is 1600x900 while the window -
	# and the saved screenshot - is 1280x720. Mixing the two makes this loop
	# converge on a framing that is right for neither. They share an aspect
	# ratio, so a framing correct in viewport space is correct in the PNG too.
	var view: Vector2 = get_viewport().get_visible_rect().size
	# Measure how tall he actually is from the skeleton rather than assuming the
	# height the build script aims for. Assuming 1.8 m put his head 215 px above
	# the top of the frame, because the model imports at 2.74 m.
	var sk: Skeleton3D = player.find_child("Skeleton3D", true, false)
	var tall := 1.8
	for i in sk.get_bone_count():
		tall = maxf(tall, (sk.global_transform * sk.get_bone_global_pose(i)).origin.y
			- player.global_position.y)
	cam.fov = 40.0
	cam.position = Vector3(0.0, 0.95, 3.4)
	cam.rotation_degrees = Vector3.ZERO

	var head := Vector2.ZERO
	var feet := Vector2.ZERO
	for pass_index in 3:
		# Re-centre on the character every pass: he is what has to be framed.
		rig.global_position = player.global_position
		await get_tree().process_frame
		head = cam.unproject_position(player.global_position + Vector3.UP * tall)
		feet = cam.unproject_position(player.global_position)
		var span: float = feet.y - head.y
		if span < 1.0:
			break
		# Scale the distance by how far off the height is, and slide the camera
		# up or down so the middle of him sits in the middle of the frame.
		cam.position.z *= span / (fill * view.y)
		# Raising the camera pushes the subject DOWN the frame, and sliding it
		# right pushes him LEFT, so both corrections move with the error.
		cam.position.y -= ((head.y + feet.y) * 0.5 - view.y * 0.5) / span * tall
		cam.position.x += (head.x - view.x * 0.5) / span * tall
	print("FRAME z=%.2f y=%.2f  head=%s feet=%s  fill=%.0f%%  model is %.2f m tall" % [
		cam.position.z, cam.position.y, head.round(), feet.round(),
		100.0 * (feet.y - head.y) / view.y, tall])


## Consecutive frames while the trigger is held, close in and from three quarters
## on, which is the angle the recoil has to read from. He aims normally at a
## fixed point on screen and stands still, so nothing about firing is faked.
func _fire_frames() -> void:
	var player := get_node("/root/Capture/Main/Player") as Player
	var rig := get_node("/root/Capture/Main/CameraRig")
	var centre := Vector2(SIZE) * 0.5
	Input.warp_mouse(centre + Vector2(430, 210))
	await _wait(0.8)
	await _study_camera()
	await _wait(0.5)
	await _shot("00_before")
	Input.action_press("shoot")
	for i in 11:
		await _shot("%02d_firing" % (i + 1))
		await _wait(0.035)
	Input.action_release("shoot")
	for i in 4:
		await _wait(0.06)
		await _shot("%02d_after" % (20 + i))


## Isolate the recoil: freeze the player so nothing else writes to the tree, then
## force the shoot blend fully on and step the clip through frame by frame. No
## shot is fired, so no muzzle flash or tracer sits on top of the pose.
func _recoil() -> void:
	var player := get_node("/root/Capture/Main/Player") as Player
	Input.warp_mouse(Vector2(SIZE) * 0.5 + Vector2(430, 120))
	await _wait(0.9)
	await _study_camera()
	await _wait(0.4)
	player.set_physics_process(false)
	var tree := player.get_node("AnimationTree") as AnimationTree
	tree.set("parameters/fire/blend_amount", 0.0)
	await _wait(0.4)
	await _shot("00_no_recoil")
	tree.set("parameters/fire/blend_amount", 1.0)
	tree.set("parameters/shoot_seek/seek_request", 0.0)
	for i in 10:
		await _shot("%02d_t%03d" % [i + 1, i * 33])
		await _wait(0.0333)
