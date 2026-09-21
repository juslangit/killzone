"""
Build the Killzone player character.

Takes the Sketchfab soldier (Futuristic soldier (lowpoly) by SlagPerch 3D, CC-BY)
and turns it into a single game-ready GLB that carries every animation the game
needs. The source model ships seven clips - Idle, Walk, Run, Crouch, Rifle_stand,
Rifle_run, Rifle_crouch - and none of them cover jumping, strafing, walking
backwards or firing. Those are authored here by resampling and recombining the
poses of the clips that do exist, so the new animations sit on the same rig and
keep the same feel.

Run it with:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        --python tools/build_character.py

Output: assets/models/player.glb
"""

import bpy
import math
import os
import sys
from mathutils import Quaternion, Vector

# --------------------------------------------------------------------------
# paths
# --------------------------------------------------------------------------

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(
    HERE, "assets", "sketchfab", "futuristic_soldier_lowpoly",
    "futuristic_soldier_lowpoly.glb",
)
OUT_DIR = os.path.join(HERE, "assets", "models")
OUT = os.path.join(OUT_DIR, "player.glb")

# The character should stand 1.8 m tall in Godot, and face -Z (Godot forward).
# The source model is roughly 3.1 units tall and faces -Y in Blender, which the
# glTF exporter would turn into +Z, so it gets spun 180 degrees on the way out.
TARGET_HEIGHT = 1.8
FPS = 30

# The source model carries its rifle slung low across the body. In a top-down
# shooter the player is aiming at the cursor the whole time, so every clip gets
# the chest tipped back far enough to bring the muzzle level, with the neck tipped
# the other way so he keeps looking where he is going. Measured by rendering the
# stand pose across a sweep of angles: positive pitch on the chest raises the gun.
AIM_CHEST = 22.0
AIM_NECK = -12.0

# --------------------------------------------------------------------------
# bone groups
# --------------------------------------------------------------------------

HIPS = "mixamorig:Hips_34"

LEG_BONES = [
    "mixamorig:LeftUpLeg_28", "mixamorig:LeftLeg_27", "mixamorig:LeftFoot_26",
    "mixamorig:LeftToeBase_25", "mixamorig:LeftToe_End_24",
    "mixamorig:RightUpLeg_33", "mixamorig:RightLeg_32", "mixamorig:RightFoot_31",
    "mixamorig:RightToeBase_30", "mixamorig:RightToe_End_29",
]

SPINE_BONES = [
    "mixamorig:Spine_23", "mixamorig:Spine1_22", "mixamorig:Spine2_21",
]

# Spine2.001 is the bone the rifle mesh hangs off, so it is the one to kick for
# recoil. Everything from the neck up and both arms ride along with the chest.
GUN_BONE = "mixamorig:Spine2.001_20"

ARM_BONES = [
    "mixamorig:LeftShoulder_10", "mixamorig:LeftArm_9", "mixamorig:LeftForeArm_8",
    "mixamorig:LeftHand_7",
    "mixamorig:RightShoulder_18", "mixamorig:RightArm_17",
    "mixamorig:RightForeArm_16", "mixamorig:RightHand_15",
]

HEAD_BONES = [
    "mixamorig:Neck_2", "mixamorig:Head_1", "mixamorig:HeadTop_End_0",
]

FINGER_BONES = [
    "mixamorig:LeftHandIndex1_6", "mixamorig:LeftHandIndex2_5",
    "mixamorig:LeftHandIndex3_4", "mixamorig:LeftHandIndex4_3",
    "mixamorig:RightHandIndex1_14", "mixamorig:RightHandIndex2_13",
    "mixamorig:RightHandIndex3_12", "mixamorig:RightHandIndex4_11",
]

LOWER = [HIPS] + LEG_BONES
UPPER = SPINE_BONES + [GUN_BONE] + ARM_BONES + HEAD_BONES + FINGER_BONES
ALL_BONES = LOWER + UPPER


# --------------------------------------------------------------------------
# pose sampling
#
# Poses are read straight off the source f-curves rather than out of the
# depsgraph. Evaluating a curve at a frame is exact, needs no scene update, and
# lets a pose be sampled from one clip while a different clip is assigned.
# --------------------------------------------------------------------------

def action_curves(action):
    """Map (data_path, array_index) -> f-curve for a slotted Blender 4.4+ action."""
    curves = {}
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    curves[(fc.data_path, fc.array_index)] = fc
    return curves


def sample_pose(action, frame, bones=None):
    """Read one frame of an action as {bone: {"loc":, "rot":, "scale":}}."""
    curves = action_curves(action)
    bones = bones or ALL_BONES
    pose = {}
    for bone in bones:
        path = 'pose.bones["%s"]' % bone

        def chan(prop, index, default):
            fc = curves.get(("%s.%s" % (path, prop), index))
            return fc.evaluate(frame) if fc else default

        rot = Quaternion((
            chan("rotation_quaternion", 0, 1.0),
            chan("rotation_quaternion", 1, 0.0),
            chan("rotation_quaternion", 2, 0.0),
            chan("rotation_quaternion", 3, 0.0),
        ))
        if rot.magnitude < 1e-6:
            rot = Quaternion((1, 0, 0, 0))
        pose[bone] = {
            "loc": Vector((chan("location", i, 0.0) for i in range(3))),
            "rot": rot.normalized(),
            "scale": Vector((chan("scale", i, 1.0) for i in range(3))),
        }
    return pose


def qmix(a, b, t):
    """Blend two quaternions. Unlike slerp this also extrapolates past 0..1,
    which is how the jump gets legs straighter than standing and knees bent
    further than crouching without hand-authoring either pose."""
    diff = a.rotation_difference(b)
    axis, angle = diff.to_axis_angle()
    if angle > math.pi:
        angle -= 2 * math.pi
    return (a @ Quaternion(axis, angle * t)).normalized()


def blend(pose_a, pose_b, t, bones=None):
    """Blend two poses. t=0 is pose_a, t=1 is pose_b, outside that extrapolates."""
    out = {}
    for bone in (bones or pose_a.keys()):
        a, b = pose_a[bone], pose_b[bone]
        out[bone] = {
            "loc": a["loc"] + (b["loc"] - a["loc"]) * t,
            "rot": qmix(a["rot"], b["rot"], t),
            "scale": a["scale"] + (b["scale"] - a["scale"]) * t,
        }
    return out


def merge(lower_from, upper_from):
    """Take the hips and legs from one pose and everything above them from another."""
    out = {}
    for bone in LOWER:
        out[bone] = dict(lower_from[bone])
    for bone in UPPER:
        out[bone] = dict(upper_from[bone])
    return out


def copy_pose(pose):
    return {b: dict(v) for b, v in pose.items()}


def yaw(pose, bones, degrees):
    """Spin bones about the armature's vertical axis.

    Every spine and hip bone on a Mixamo rig rests pointing straight up, so the
    bone's own local Y axis is world up and a pre-multiplied rotation about it is
    a clean yaw. This is what turns the run cycle into a strafe: the hips twist
    to the side so the legs step sideways, and the spine twists back so the
    chest and rifle keep facing the cursor.
    """
    out = copy_pose(pose)
    spin = Quaternion((0, 1, 0), math.radians(degrees))
    for bone in bones:
        out[bone]["rot"] = (spin @ out[bone]["rot"]).normalized()
    return out


def pitch(pose, bones, degrees):
    """Tip bones backwards or forwards about their local X axis - used for recoil."""
    out = copy_pose(pose)
    tip = Quaternion((1, 0, 0), math.radians(degrees))
    for bone in bones:
        out[bone]["rot"] = (tip @ out[bone]["rot"]).normalized()
    return out


def lift(pose, amount):
    """Raise or drop the hips. The hips bone points up, so its local Y is height."""
    out = copy_pose(pose)
    out[HIPS]["loc"] = out[HIPS]["loc"] + Vector((0.0, amount, 0.0))
    return out


def aim(pose):
    """Bring the rifle up to a level, ready-to-fire carry."""
    out = pitch(pose, ["mixamorig:Spine2_21"], AIM_CHEST)
    return pitch(out, ["mixamorig:Neck_2"], AIM_NECK)


# --------------------------------------------------------------------------
# writing actions
# --------------------------------------------------------------------------

def write_action(armature, name, keys):
    """Create an action from [(frame, pose), ...] and leave it on the armature."""
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    armature.animation_data.action = action
    if action.slots:
        armature.animation_data.action_slot = action.slots[0]

    for frame, pose in keys:
        for bone, vals in pose.items():
            pb = armature.pose.bones[bone]
            pb.rotation_mode = "QUATERNION"
            pb.location = vals["loc"]
            pb.rotation_quaternion = vals["rot"]
            pb.scale = vals["scale"]
            pb.keyframe_insert("location", frame=frame)
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("scale", frame=frame)
        # The slot only exists once the first key is inserted.
        if action.slots and armature.animation_data.action_slot is None:
            armature.animation_data.action_slot = action.slots[0]

    for fc in action_curves(action).values():
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
    return action


def resample(action, frames):
    """Turn an existing clip into a list of (frame, pose) keys, one per frame."""
    start = int(action.frame_range[0])
    return [(i, sample_pose(action, start + i)) for i in range(frames)]


# --------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    bpy.context.scene.render.fps = FPS

    # The Sketchfab scene ships a backdrop sphere with the model. Drop it.
    for obj in list(bpy.data.objects):
        if obj.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj, do_unlink=True)

    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    if not armature.animation_data:
        armature.animation_data_create()

    src = {a.name: a for a in list(bpy.data.actions)}
    print("SOURCE CLIPS:", sorted(src))

    # ---- reference poses -------------------------------------------------
    # One frame each, used as the raw material for everything authored below.
    #
    # Two different clips are needed for crouching. Rifle_crouch has the rifle
    # held properly in both hands but is really only a forward hunch, while
    # Crouch is a genuine deep squat with the rifle slung on his back. So the
    # legs come from Crouch and everything above the hips from Rifle_crouch.
    stand = sample_pose(src["Rifle_stand"], 1)
    squat = sample_pose(src["Crouch"], 1)
    hunch = sample_pose(src["Rifle_crouch"], 1)

    built = []

    # ---- idle ------------------------------------------------------------
    # The stock 186-frame standing loop, kept as-is. It already breathes and
    # shifts weight, which is more life than anything worth authoring by hand.
    built.append(("idle", resample(src["Rifle_stand"], 186), True))

    # ---- run forward -----------------------------------------------------
    run_len = 18
    run_keys = resample(src["Rifle_run"], run_len)
    built.append(("run_forward", run_keys, True))

    # ---- run backward ----------------------------------------------------
    # Legs play the run cycle in reverse so the feet push the other way, while
    # the chest and rifle keep running forward - he backpedals while aiming.
    back = []
    for i in range(run_len):
        legs = sample_pose(src["Rifle_run"], 1 + (run_len - 1 - i))
        torso = sample_pose(src["Rifle_run"], 1 + i)
        back.append((i, merge(legs, torso)))
    built.append(("run_backward", back, True))

    # ---- strafe left / right ---------------------------------------------
    # The run cycle with the hips twisted sideways and the spine twisted back,
    # so the legs cross over while the rifle stays pointed at the cursor.
    for name, angle in (("strafe_left", 68.0), ("strafe_right", -68.0)):
        keys = []
        for i in range(run_len):
            pose = sample_pose(src["Rifle_run"], 1 + i)
            pose = yaw(pose, [HIPS], angle)
            # Undo the twist gradually up the spine rather than all at once, so
            # no single joint has to do an impossible amount of work.
            pose = yaw(pose, SPINE_BONES, -angle / 3.0)
            keys.append((i, pose))
        built.append((name, keys, True))

    # ---- crouch idle -----------------------------------------------------
    # Squatting legs from Crouch, but only three quarters of the way there and
    # with the standing torso on top. Taken at full strength the squat folds him
    # double, because its hips lean well forward and Rifle_crouch's spine then
    # hunches further over that. What is wanted is a tactical crouch: knees
    # down, chest up, rifle still level with the cursor.
    crouch_len = 26
    crouch_idle = []
    for i in range(crouch_len):
        legs = sample_pose(src["Crouch"], 1 + i)
        breathe = sample_pose(src["Rifle_crouch"], 1 + (i * 48) // crouch_len)
        low = blend(stand, legs, 0.75, bones=LOWER)
        crouch_idle.append((i, merge(low, blend(stand, breathe, 0.35))))
    built.append(("crouch_idle", crouch_idle, True))

    # ---- crouch walk -----------------------------------------------------
    # The run cycle pulled down into the same crouch, so he still steps but
    # stays low, with the rifle-ready torso kept upright on top.
    crouch_walk = []
    for i in range(crouch_len):
        moving = sample_pose(src["Rifle_run"], 1 + (i * run_len) // crouch_len)
        legs = blend(moving, squat, 0.55, bones=LOWER)
        crouch_walk.append((i, merge(legs, blend(stand, hunch, 0.3))))
    built.append(("crouch_walk", crouch_walk, True))

    # ---- jump ------------------------------------------------------------
    # Five leg poses, all derived by pushing the stand-to-squat blend past its
    # own ends rather than by hand-dialling joint angles: dip into the squat,
    # drive straighter than standing, tuck deeper than the squat, reach, absorb.
    # The hips barely move here - Godot's physics does the actual travel, so the
    # animation only has to sell the push and the tuck.
    def leg_pose(t, hips=0.0):
        return lift(merge(blend(stand, squat, t, bones=LOWER), stand), hips)

    built.append((
        "jump",
        [(0, stand),
         (4, leg_pose(0.55, -0.04)),
         (9, leg_pose(-0.28, 0.10)),
         (16, leg_pose(0.95, 0.16)),
         (23, leg_pose(0.10, 0.05)),
         (28, leg_pose(0.70, -0.08)),
         (34, stand)],
        False,
    ))

    # ---- shoot -----------------------------------------------------------
    # A short kick on the chest and the rifle bone, on top of whatever aim
    # offset gets applied below. Godot plays this on the upper body only, so he
    # can fire in the middle of any locomotion clip. Positive pitch drives the
    # muzzle up and the shoulders back, which is the direction recoil goes.
    kick = pitch(stand, ["mixamorig:Spine2_21"], 17.0)
    kick = pitch(kick, ["mixamorig:Spine1_22"], 5.0)
    kick = pitch(kick, [GUN_BONE], 9.0)
    settle = pitch(stand, ["mixamorig:Spine2_21"], 6.0)
    settle = pitch(settle, [GUN_BONE], 3.0)
    built.append((
        "shoot",
        [(0, stand), (1, kick), (4, settle), (9, stand)],
        False,
    ))

    # ---- write them out --------------------------------------------------
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    for name, keys, _loop in built:
        keys = [(f, aim(p)) for f, p in keys]
        action = write_action(armature, name, keys)
        print("BUILT %-14s frames=%.0f..%.0f" % (
            name, action.frame_range[0], action.frame_range[1]))

    # ---- orient and scale for Godot --------------------------------------
    root = next(o for o in bpy.data.objects if o.name == "Sketchfab_model")
    deps = bpy.context.evaluated_depsgraph_get()
    bpy.context.scene.frame_set(1)
    top = max(
        (o.evaluated_get(deps).matrix_world @ Vector(corner)).z
        for o in bpy.data.objects if o.type == "MESH"
        for corner in o.bound_box
    )
    scale = TARGET_HEIGHT / top
    root.scale = (scale, scale, scale)
    root.rotation_euler = (0.0, 0.0, math.pi)
    print("SCALE height=%.3f -> %.3f (factor %.4f)" % (top, TARGET_HEIGHT, scale))

    # ---- export ----------------------------------------------------------
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_bake_animation=True,
        export_nla_strips=False,
        export_apply=False,
        export_yup=True,
        export_skins=True,
        export_morph=False,
        export_force_sampling=True,
        export_frame_range=False,
        export_optimize_animation_size=False,
    )
    print("WROTE", OUT, os.path.getsize(OUT), "bytes")


main()
