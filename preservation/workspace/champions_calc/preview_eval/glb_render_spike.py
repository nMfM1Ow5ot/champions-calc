#!/usr/bin/env python3
"""GLB 描画スパイク (Blender ヘッドレス実行専用)。

使い方:
  ./blender/blender -b --python glb_render_spike.py -- <glb> <outdir> [pose]
pose: bind | idle (Battle Idle の中間フレーム)
方位角を 45 度刻みで回し、各方位のレンダリング PNG を出す。
"""
import bpy
import math
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
glb_path, outdir = argv[0], argv[1]
pose = argv[2] if len(argv) > 2 else "idle"
os.makedirs(outdir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# アニメーション: Battle Idle をアーマチュアへ割り当て、中間フレームへ
if pose == "idle":
    target = None
    for act in bpy.data.actions:
        if act.name.lower().startswith("battle idle"):
            target = act
            break
    if target is not None:
        for obj in bpy.data.objects:
            if obj.type == "ARMATURE":
                obj.animation_data_create()
                obj.animation_data.action = target
        f0, f1 = target.frame_range
        bpy.context.scene.frame_set(int((f0 + f1) / 2))
        print(f"POSE: Battle Idle frame {(f0 + f1) / 2:.0f} of [{f0}, {f1}]")
    else:
        print("POSE: Battle Idle が見つからないため bind pose")
else:
    print("POSE: bind")

bpy.context.view_layer.update()

# モデル全体のバウンディングボックス
import mathutils
mins = mathutils.Vector((1e9, 1e9, 1e9))
maxs = mathutils.Vector((-1e9, -1e9, -1e9))
for obj in bpy.data.objects:
    if obj.type == "MESH":
        for corner in obj.bound_box:
            v = obj.matrix_world @ mathutils.Vector(corner)
            mins = mathutils.Vector(map(min, mins, v))
            maxs = mathutils.Vector(map(max, maxs, v))
center = (mins + maxs) / 2
size = (maxs - mins)
radius = max(size.x, size.y, size.z) / 2
print(f"BBOX center={tuple(round(c, 2) for c in center)} size={tuple(round(s, 2) for s in size)}")

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 400
scene.render.resolution_y = 300
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.eevee.taa_render_samples = 16

# ライト: 太陽光 + 弱い環境光
sun_data = bpy.data.lights.new("sun", "SUN")
sun_data.energy = 3.0
sun = bpy.data.objects.new("sun", sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.5, 0.5, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.6

cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam_data.clip_end = 1000

target_pt = center + mathutils.Vector((0, 0, size.z * 0.05))
for az_deg in range(0, 360, 45):
    az = math.radians(az_deg)
    el = math.radians(12)
    dist = radius / math.tan(math.radians(22)) * 1.15
    pos = target_pt + mathutils.Vector((
        dist * math.cos(el) * math.sin(az),
        -dist * math.cos(el) * math.cos(az),
        dist * math.sin(el)))
    cam.location = pos
    direction = target_pt - pos
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(outdir, f"az{az_deg:03d}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)
print("SPIKE DONE")
