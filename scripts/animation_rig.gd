class_name AnimationRig
extends RefCounted

## Builds the player's AnimationTree in code.
##
## Doing this here rather than clicking it together in the editor keeps the whole
## blend setup in one readable place, and lets the upper-body filter be derived
## from the skeleton's actual track names instead of being typed out by hand and
## silently breaking whenever the character is rebuilt.
##
## The tree is a stack of blends, each one layered over the last:
##
##     ground   4-way locomotion  ─┐
##                                 ├─ stance ─┐
##     crouch   4-way, crouched   ─┘          ├─ air ─┐
##     jump                         ──────────┘       ├─ fire ── output
##     shoot (upper body only)      ──────────────────┘

## Bones the shoot animation is allowed to touch. Everything below the waist
## keeps running, walking or crouching while he fires.
const UPPER_BODY := [
	"Spine", "Spine1", "Spine2", "Spine2.001",
	"Neck", "Head", "HeadTop_End",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftHandIndex1", "LeftHandIndex2", "LeftHandIndex3", "LeftHandIndex4",
	"RightHandIndex1", "RightHandIndex2", "RightHandIndex3", "RightHandIndex4",
]

const LOOPING := [
	"idle", "run_forward", "run_backward", "strafe_left", "strafe_right",
	"crouch_idle", "crouch_walk",
]


static func _clip(library: String, name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = library + name
	return node


## A diamond of four directional clips around a centre. Feeding it a direction in
## the character's own space - +Y forward, +X right - picks the right mix, which
## is what lets him backpedal or sidestep while still aiming at the cursor.
static func _blend_space(
	library: String, centre: String, forward: String, back: String,
	left: String, right: String
) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 1.0)
	space.snap = Vector2(0.05, 0.05)
	for point in [
		[centre, Vector2.ZERO, "centre"],
		[forward, Vector2(0.0, 1.0), "forward"],
		[back, Vector2(0.0, -1.0), "back"],
		[left, Vector2(-1.0, 0.0), "left"],
		[right, Vector2(1.0, 0.0), "right"],
	]:
		space.add_blend_point(_clip(library, point[0]), point[1], -1, point[2])
	return space


## Reduce an exported bone name to the plain Mixamo bone it came from.
##
## Blender writes these as "mixamorig:Spine2_21" - a namespace prefix and an
## index suffix around the real name - and Godot's importer then turns the colon
## into an underscore, so what actually arrives is "mixamorig_Spine2_21". Both
## spellings are handled, because which one you get depends on the importer.
static func bone_stem(bone: String) -> String:
	var leaf := bone
	for prefix in ["mixamorig_", "mixamorig:"]:
		if leaf.begins_with(prefix):
			leaf = leaf.substr(prefix.length())
			break
	var cut := leaf.rfind("_")
	return leaf.substr(0, cut) if cut > 0 else leaf


## Every track in the character's animations whose bone belongs to the upper
## body. Track paths look like "Model/.../Skeleton3D:mixamorig_Spine2_21".
static func _upper_body_tracks(player: AnimationPlayer) -> Array[NodePath]:
	var paths: Array[NodePath] = []
	var seen := {}
	for anim_name in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		for track in anim.get_track_count():
			var path := anim.track_get_path(track)
			var bone := String(path.get_concatenated_subnames())
			if bone.is_empty() or seen.has(path):
				continue
			if UPPER_BODY.has(bone_stem(bone)):
				seen[path] = true
				paths.append(path)
	return paths


## Locomotion has to loop or the character freezes mid-stride; jump and shoot
## must not, or he would keep re-jumping on the spot. The glTF importer has no
## idea which is which, so it is set here from the clip name.
static func apply_loop_modes(player: AnimationPlayer) -> void:
	for anim_name in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		var stem := anim_name.get_slice("/", anim_name.get_slice_count("/") - 1)
		anim.loop_mode = (
			Animation.LOOP_LINEAR if LOOPING.has(stem) else Animation.LOOP_NONE
		)


static func build(player: AnimationPlayer) -> AnimationNodeBlendTree:
	# Godot can file imported clips under a named library, in which case every
	# clip name needs that prefix. Usually "" for a plain glTF, but do not
	# assume it. Match on the last path segment only - testing for a name ending
	# in "idle" would happily pick "crouch_idle" and invent a "crouch_" library.
	var library := ""
	for name in player.get_animation_list():
		if name.get_slice("/", name.get_slice_count("/") - 1) == "idle":
			library = name.substr(0, name.length() - 4)
			break

	var tree := AnimationNodeBlendTree.new()

	tree.add_node("ground", _blend_space(
		library, "idle", "run_forward", "run_backward",
		"strafe_left", "strafe_right",
	), Vector2(0, 0))

	# Only one crouched walk cycle exists, so every direction reuses it. He
	# shuffles slowly when crouched, and the difference does not read.
	tree.add_node("crouch", _blend_space(
		library, "crouch_idle", "crouch_walk", "crouch_walk",
		"crouch_walk", "crouch_walk",
	), Vector2(0, 220))

	var stance := AnimationNodeBlend2.new()
	tree.add_node("stance", stance, Vector2(300, 100))
	tree.connect_node("stance", 0, "ground")
	tree.connect_node("stance", 1, "crouch")

	# Jump and shoot both need to restart from frame zero every time they are
	# triggered, which a plain animation node cannot do - hence the seek nodes.
	tree.add_node("jump_clip", _clip(library, "jump"), Vector2(300, 320))
	tree.add_node("jump_seek", AnimationNodeTimeSeek.new(), Vector2(460, 320))
	tree.connect_node("jump_seek", 0, "jump_clip")

	var air := AnimationNodeBlend2.new()
	tree.add_node("air", air, Vector2(620, 160))
	tree.connect_node("air", 0, "stance")
	tree.connect_node("air", 1, "jump_seek")

	tree.add_node("shoot_clip", _clip(library, "shoot"), Vector2(620, 400))
	tree.add_node("shoot_seek", AnimationNodeTimeSeek.new(), Vector2(780, 400))
	tree.connect_node("shoot_seek", 0, "shoot_clip")

	var fire := AnimationNodeBlend2.new()
	fire.filter_enabled = true
	for path in _upper_body_tracks(player):
		fire.set_filter_path(path, true)
	tree.add_node("fire", fire, Vector2(940, 220))
	tree.connect_node("fire", 0, "air")
	tree.connect_node("fire", 1, "shoot_seek")

	tree.connect_node("output", 0, "fire")
	return tree
