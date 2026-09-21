# Killzone

A top-down shooter prototype in Godot 4.7. One man, one rifle, an empty field of
grass, and the controls to move him around it.

The view is Diablo's: a fixed bird's-eye camera that follows the player without
ever turning with him. Movement and aim are separate - WASD drives him around
the world while the mouse decides which way he faces - so he can backpedal or
sidestep while keeping the rifle on the cursor.

## Controls

| Input | Action |
|---|---|
| `W` `A` `S` `D` | Move, relative to the screen |
| Mouse | Aim - he always faces the cursor |
| Left mouse button | Fire |
| `Space` | Jump |
| `C` or `Ctrl` | Crouch |

## What is in it

- Four-way locomotion that picks the right animation for the direction of travel
  relative to where he is looking: run, backpedal, and a strafe each way.
- Jump with a real crouch-and-drive, and a crouch that lowers his collider as
  well as his pose.
- Hitscan firing at roughly nine rounds a second, with a muzzle flash on the
  rifle bone, a tracer, and an impact puff. The recoil animation plays on the
  upper body only, so he keeps running while he fires.

There are no enemies and nothing to shoot at yet. The map is a bare 60 x 60 m
square of grass with a low wall around it.

## Running it

Open the folder in Godot 4.7 and press play, or:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . scenes/main.tscn
```

To take screenshots of every mechanic without touching the keyboard:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture.tscn
# frame-by-frame through a run cycle and a jump:
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture.tscn -- burst
```

## Rebuilding the character

`assets/models/player.glb` is generated, not hand-made. The Sketchfab soldier it
comes from ships seven animations and none of them cover jumping, strafing,
backpedalling or firing, so those are authored from the poses of the clips that
do exist:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    --python tools/build_character.py
```

The recipes are in that script, each one commented with what it is made of.

## Credits

The character model is **[Futuristic soldier (lowpoly)](https://sketchfab.com/3d-models/futuristic-soldier-lowpoly-5ebade1ccbff4adb91ddd3a4d1fcd541)**
by **SlagPerch 3D**, from Sketchfab, under
[CC Attribution](https://creativecommons.org/licenses/by/4.0/). Commercial use is
allowed and the credit is required, so it must stay on any screen this game ever
ships with. The animations shipped in that file were recombined and extended for
this project; the original rig and mesh are unchanged.

Full licence text is in `assets/sketchfab/futuristic_soldier_lowpoly/ATTRIBUTION.md`.
