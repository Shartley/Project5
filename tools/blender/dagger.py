"""Builds the player's dagger (used in both hands) and exports it for Godot.

    blender -b --factory-startup -P tools/blender/dagger.py -- <out_dir>

Origin is the centre of the grip; the blade points along Blender +Y, which is Godot's -Z (forward),
so the dagger points where the hand or controller points. Original design: a steel blade with a
fuller, a blackened crossguard, a leather-wrapped grip, and a small System-blue gem in the pommel.
"""

import math
import os
import sys

import bpy
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import V, activate, apply_modifiers, args, assign, export_glb, join, pbr, render_views, reset_scene, setup_render  # noqa: E402

OUT_DIR, _ = args()

GRIP_HALF = 0.048
GUARD_Y = GRIP_HALF + 0.007
BLADE_START = GRIP_HALF + 0.014
BLADE_LEN = 0.2


def smooth_by_angle(obj, degrees):
    activate(obj)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(degrees))
    except Exception:
        bpy.ops.object.shade_flat()


def build_blade():
    bm = bmesh.new()
    sections = 28
    rings = []
    for i in range(sections):
        s = i / sections
        y = BLADE_START + s * BLADE_LEN
        if s < 0.68:
            w = 0.0185 * (1.0 - 0.22 * s)
        else:
            w0 = 0.0185 * (1.0 - 0.22 * 0.68)
            w = w0 * math.sqrt(max(0.0, (1.0 - s) / 0.32))
        t = 0.0043 * (1.0 - 0.55 * s)
        f = 1.0 if s < 0.55 else max(0.0, 1.0 - (s - 0.55) / 0.17)   # fuller fades out
        ridge = t * (1.0 - 0.45 * f)
        side = t * (0.65 + 0.2 * f)
        prof = [(-w, 0.0), (-0.35 * w, side), (0.0, ridge), (0.35 * w, side),
                (w, 0.0), (0.35 * w, -side), (0.0, -ridge), (-0.35 * w, -side)]
        rings.append([bm.verts.new((x, y, z)) for x, z in prof])
    tip = bm.verts.new((0.0, BLADE_START + BLADE_LEN, 0.0))
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    for k in range(n):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % n], tip))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Blade")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("Blade", me)
    bpy.context.collection.objects.link(obj)
    smooth_by_angle(obj, 30)
    assign(obj, pbr("dagger_steel", (0.58, 0.59, 0.6), 1.0, 0.24))
    return obj


def build_guard():
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, GUARD_Y, 0))
    bar = bpy.context.active_object
    bar.scale = (0.078, 0.013, 0.02)
    bpy.ops.object.transform_apply(scale=True)
    bev = bar.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.0025
    bev.segments = 3
    apply_modifiers(bar)
    # bend the quillons slightly toward the blade
    for v in bar.data.vertices:
        v.co.y += 2.0 * v.co.x * v.co.x          # about 3 mm at the tips
    caps = []
    for side in (1, -1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.0085, location=(0.041 * side, GUARD_Y + 2.0 * 0.041 ** 2, 0))
        caps.append(bpy.context.active_object)
    guard = join([bar] + caps, "Guard")
    bpy.ops.object.shade_smooth()
    assign(guard, pbr("dagger_dark_steel", (0.06, 0.065, 0.075), 1.0, 0.42))
    return guard


def build_grip():
    bm = bmesh.new()
    seg, rings_n = 32, 64
    rings = []
    for i in range(rings_n + 1):
        y = -GRIP_HALF + 2 * GRIP_HALF * i / rings_n
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            phase = (y / 0.0105 + a / (2 * math.pi)) % 1.0
            groove = 1.0 - min(1.0, phase / 0.16) if phase < 0.16 else 0.0
            r = 0.0128 - 0.0012 * groove
            ring.append(bm.verts.new((math.cos(a) * r, y, math.sin(a) * r)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((a[k], b[k], b[(k + 1) % seg], a[(k + 1) % seg]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Grip")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("Grip", me)
    bpy.context.collection.objects.link(obj)
    activate(obj)
    bpy.ops.object.shade_smooth()
    assign(obj, pbr("dagger_leather", (0.045, 0.028, 0.018), 0.0, 0.72))
    return obj


def build_pommel():
    y = -GRIP_HALF - 0.011
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.0155, location=(0, y, 0))
    p = bpy.context.active_object
    p.scale = (1.0, 0.72, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.0115, depth=0.008, location=(0, -GRIP_HALF - 0.002, 0), rotation=(math.pi / 2, 0, 0))
    collar = bpy.context.active_object
    pommel = join([p, collar], "Pommel")
    bpy.ops.object.shade_smooth()
    assign(pommel, pbr("dagger_dark_steel_p", (0.06, 0.065, 0.075), 1.0, 0.42))
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.006, location=(0, y - 0.0105, 0))
    gem = bpy.context.active_object
    gem.name = "Gem"
    bpy.ops.object.shade_flat()
    assign(gem, pbr("dagger_gem", (0.08, 0.35, 0.7), 0.0, 0.08, emission=(0.247, 0.722, 1.0), strength=3.0))
    return pommel, gem


def main():
    scene = reset_scene()
    blade = build_blade()
    guard = build_guard()
    grip = build_grip()
    pommel, gem = build_pommel()
    dagger = join([blade, guard, grip, pommel, gem], "Dagger")
    print("dagger tris:", sum(len(p.vertices) - 2 for p in dagger.data.polygons))
    export_glb([dagger], os.path.join(OUT_DIR, "dagger.glb"))
    setup_render(scene, res=800, samples=48, world=(0.18, 0.2, 0.24))
    dagger.rotation_euler = (0, math.radians(-90), math.radians(90))   # lay it across the frame for the preview
    render_views(scene, OUT_DIR, "dagger", target=V((0, 0, 0.0)), dist=0.55, views=(("side", 0), ("angle", 35)), lens=50, height=0.25)


main()
