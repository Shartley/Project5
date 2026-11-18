"""Builds the gate portal's stone frame (the GDD's anchor asset) and exports it for Godot.

    blender -b --factory-startup -P tools/blender/portal.py -- <out_dir>

A ring of jagged dark-navy rock around a 2 m tall oval opening, with cracks that glow System
Blue, brightest near the opening. The swirling light inside is a Godot shader
(assets/props/portal/portal_swirl.gdshader), so it can animate and change colour per gate.
The frame stands on the floor at the origin and faces Blender -Y (Godot +Z).
"""

import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (V, activate, apply_modifiers, args, bake_maps, clean_mesh, decimate, duplicate,  # noqa: E402
                    export_glb, join, Nodes, remesh, render_views, reset_scene, setup_render, unwrap)

OUT_DIR, _ = args()
random.seed(7)

CENTER_Z = 1.08     # oval centre height
HALF_W = 0.66       # half width of the ring's centre line
HALF_H = 1.12       # half height of the ring's centre line


def ellipse(theta, scale=1.0):
    return V((math.cos(theta) * HALF_W * scale, 0.0, CENTER_Z + math.sin(theta) * HALF_H * scale))


def rock(loc, radius, squash):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=loc)
    r = bpy.context.active_object
    r.scale = squash
    r.rotation_euler = (random.uniform(0, 6.3), random.uniform(0, 6.3), random.uniform(0, 6.3))
    for v in r.data.vertices:                       # chip the surface into flat, broken facets
        v.co *= random.uniform(0.82, 1.12)
    return r


def spike(base, direction, length, radius):
    bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=radius, radius2=0.0, depth=length)
    c = bpy.context.active_object
    c.rotation_mode = "QUATERNION"
    c.rotation_quaternion = V((0, 0, 1)).rotation_difference(direction.normalized())
    c.location = base + direction.normalized() * length * 0.5
    return c


def build_frame_high():
    parts = []
    n = 46
    for i in range(n):
        th = 2 * math.pi * i / n + random.uniform(-0.04, 0.04)
        out = random.uniform(1.05, 1.2)
        size = random.uniform(0.13, 0.2)
        p = ellipse(th, out) + V((0, random.uniform(-0.06, 0.06), 0))
        parts.append(rock(p, size, (random.uniform(0.8, 1.3), random.uniform(0.9, 1.4), random.uniform(0.8, 1.3))))
        inner = ellipse(th, 0.97)
        parts.append(rock(inner, size * 0.62, (1.0, random.uniform(1.0, 1.5), 1.0)))
    for i in range(14):                               # jagged shards sticking outward
        th = 2 * math.pi * (i + random.uniform(0, 0.6)) / 14
        if math.sin(th) < -0.75:                       # none along the floor
            continue
        base = ellipse(th, 1.12)
        outward = V((math.cos(th) / HALF_W, random.uniform(-0.4, 0.4), math.sin(th) / HALF_H))
        parts.append(spike(base, outward + V((0, 0, 0.25)), random.uniform(0.28, 0.5), random.uniform(0.07, 0.11)))
    # a heavy base so the gate sits on the ground
    for x in (-0.55, 0.0, 0.55):
        parts.append(rock(V((x, 0.0, 0.05)), 0.26, (1.3, 1.1, 0.6)))
    frame = join(parts, "PortalHigh")
    # the joined object inherits the first rock's random rotation; bake it into the vertices
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    remesh(frame, 0.014)
    tex = bpy.data.textures.new("rough", "CLOUDS")
    tex.noise_scale = 0.12
    d = frame.modifiers.new("Rough", "DISPLACE")
    d.texture = tex
    d.strength = 0.035
    crack = bpy.data.textures.new("crack", "VORONOI")
    crack.noise_scale = 0.09
    d2 = frame.modifiers.new("Crack", "DISPLACE")
    d2.texture = crack
    d2.strength = -0.005
    apply_modifiers(frame)
    # cut the frame off below the floor
    for v in frame.data.vertices:
        if v.co.z < -0.02:
            v.co.z = -0.02
    activate(frame)
    bpy.ops.object.shade_smooth()
    return frame


def stone_material():
    mat = bpy.data.materials.new("portal_stone_src")
    n = Nodes(mat)
    geo = n.add("ShaderNodeNewGeometry")
    mott = n.ramp(n.noise(3.5, 6.0, 0.6).outputs["Fac"], [(0.3, (0.01, 0.014, 0.024)), (0.75, (0.032, 0.039, 0.056))])
    col = n.ao(mott.outputs["Color"], 0.12, 0.4)
    vor = n.add("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 9.0
    cracks = n.ramp(vor.outputs["Distance"], [(0.0, (1, 1, 1)), (0.014, (0, 0, 0))])
    patchy = n.ramp(n.noise(2.2, 3.0).outputs["Fac"], [(0.48, (0, 0, 0)), (0.62, (1, 1, 1))])
    cracks_mixed = n.mix(1.0, cracks.outputs["Color"], patchy.outputs["Color"], "MULTIPLY")
    # glow strongest near the opening: distance of this point from the oval's centre line
    sep = n.add("ShaderNodeSeparateXYZ")
    n.link(geo.outputs["Position"], sep.inputs["Vector"])
    ex = n.add("ShaderNodeMath")
    ex.operation = "DIVIDE"
    n.link(sep.outputs["X"], ex.inputs[0])
    ex.inputs[1].default_value = HALF_W
    ez = n.add("ShaderNodeMath")
    ez.operation = "SUBTRACT"
    n.link(sep.outputs["Z"], ez.inputs[0])
    ez.inputs[1].default_value = CENTER_Z
    ez2 = n.add("ShaderNodeMath")
    ez2.operation = "DIVIDE"
    n.link(ez.outputs[0], ez2.inputs[0])
    ez2.inputs[1].default_value = HALF_H
    comb = n.add("ShaderNodeCombineXYZ")
    n.link(ex.outputs[0], comb.inputs["X"])
    n.link(ez2.outputs[0], comb.inputs["Y"])
    length = n.add("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    n.link(comb.outputs[0], length.inputs[0])
    near = n.map_range(length.outputs["Value"], 0.95, 1.25, 1.0, 0.0)
    bw = n.add("ShaderNodeRGBToBW")
    n.link(cracks_mixed, bw.inputs["Color"])
    glow = n.add("ShaderNodeMath")
    glow.operation = "MULTIPLY"
    n.link(bw.outputs["Val"], glow.inputs[0])
    n.link(near, glow.inputs[1])
    col = n.mix(glow.outputs[0], col, (0.004, 0.012, 0.025))
    n.link(col, n.bsdf.inputs["Base Color"])
    emis = n.mix(glow.outputs[0], (0, 0, 0), (0.247, 0.722, 1.0))
    n.link(emis, n.bsdf.inputs["Emission Color"])
    n.bsdf.inputs["Emission Strength"].default_value = 1.0
    n.link(n.map_range(n.noise(12.0).outputs["Fac"], 0, 1, 0.55, 0.9), n.bsdf.inputs["Roughness"])
    n.bump(n.noise(40.0, 8.0).outputs["Fac"], 0.5, 0.01)
    return mat


def main():
    scene = reset_scene()
    high = build_frame_high()
    high.data.materials.append(stone_material())
    print("frame high faces:", len(high.data.polygons))
    low = duplicate(high, "PortalFrame")
    decimate(low, 7000)
    clean_mesh(low)
    activate(low)
    bpy.ops.object.shade_smooth()
    unwrap(low)
    print("frame game tris:", sum(len(p.vertices) - 2 for p in low.data.polygons))
    bake_maps([high], low, 2048, OUT_DIR, "portal_frame", maps=("albedo", "normal", "roughness", "emission"))
    high.hide_render = True
    high.hide_set(True)
    export_glb([low], os.path.join(OUT_DIR, "portal_frame.glb"))
    setup_render(scene, res=800, samples=48)
    render_views(scene, OUT_DIR, "portal", target=V((0, 0, 1.05)), dist=5.0, views=(("front", 0), ("angle", 35)), lens=45, height=0.2)


main()
