"""Builds the Kobold enemy by reusing the Goblin pipeline with its own anatomy and gear.

    blender -b --factory-startup -P tools/blender/kobold.py -- <out_dir> full

An original small reptile-dog creature, about 1 m tall: long snout, swept-back horns, a tail,
backward-bending (digitigrade) legs, rust-brown scaly skin, a ragged wrap and a short spear.
Same rig layout and animations as the Goblin, so the game drives both the same way.
"""

import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import goblin as g  # noqa: E402

V = g.V
g.NAME = "kobold"

# Joints (metres, +Z up, facing -Y), A-pose, slightly hunched.
g.J.update({
    "pelvis": V((0, 0.01, 0.5)),
    "waist": V((0, 0.0, 0.59)),
    "ribs": V((0, -0.03, 0.7)),
    "upper_chest": V((0, -0.06, 0.78)),
    "neck_base": V((0, -0.09, 0.82)),
    "neck_top": V((0, -0.15, 0.88)),
    "head": V((0, -0.19, 0.92)),
    "head_top": V((0, -0.2, 1.0)),
    "clavicle": V((0.025, -0.075, 0.8)),
    "shoulder": V((0.12, -0.06, 0.79)),
    "elbow": V((0.23, -0.05, 0.65)),
    "wrist": V((0.31, -0.09, 0.52)),
    "palm": V((0.33, -0.1, 0.48)),
    "hip": V((0.07, 0.0, 0.49)),
    "knee": V((0.095, -0.1, 0.33)),
    "ankle": V((0.095, 0.04, 0.12)),
    "ball": V((0.1, -0.04, 0.025)),
})
J = g.J


def kobold_body():
    s = g.Sculpt("KoboldSculpt")
    s.ellipsoid(J["pelvis"], 0.085, (1.0, 0.85, 0.8))
    s.ball((0, -0.02, 0.6), 0.068)
    s.ellipsoid(J["ribs"], 0.093, (1.0, 0.85, 1.05), axis=(0, -0.2, 1))
    s.ellipsoid(J["upper_chest"], 0.083, (1.15, 0.8, 0.65))
    s.ball((0.05, -0.005, 0.77), 0.034, sym=True)                                  # shoulder blades
    s.capsule(J["neck_base"], J["neck_top"], 0.033)
    for i in range(7):                                                              # ridge of spines down the back
        t = i / 6
        s.ball((0, 0.068 - 0.08 * t, 0.56 + 0.24 * t), 0.012, stiff=1.6)        # follows the curve of the back
    tail = [(0, 0.08, 0.52), (0, 0.17, 0.42), (0, 0.27, 0.27), (0, 0.36, 0.13), (0, 0.46, 0.05), (0.03, 0.56, 0.03)]
    s.chain(tail, [0.05, 0.042, 0.033, 0.024, 0.016, 0.009])
    h = J["head"]
    s.ellipsoid(h + V((0, 0.02, 0.02)), 0.068, (0.95, 1.1, 0.9))                  # cranium
    s.chain([h + V((0, -0.03, 0.0)), h + V((0, -0.1, -0.02)), h + V((0, -0.16, -0.032))], [0.045, 0.033, 0.023])  # snout
    s.chain([h + V((0, -0.02, -0.04)), h + V((0, -0.09, -0.055)), h + V((0, -0.14, -0.06))], [0.034, 0.025, 0.017])  # jaw
    s.capsule(h + V((-0.036, -0.035, 0.03)), h + V((0.036, -0.035, 0.03)), 0.016)  # brow
    s.ball(h + V((0.034, -0.045, 0.012)), 0.015, neg=True, sym=True)               # eye sockets
    s.ball(h + V((0.012, -0.168, -0.018)), 0.006, neg=True, sym=True)              # nostrils
    s.capsule(h + V((-0.03, -0.12, -0.046)), h + V((0.03, -0.12, -0.046)), 0.004, neg=True)  # mouth line
    sh, el, wr = J["shoulder"], J["elbow"], J["wrist"]
    s.ball(sh + V((0.008, 0, 0.008)), 0.032, sym=True)
    s.capsule(sh, el, 0.022, sym=True)
    s.ball(g.lerp(sh, el, 0.45) + V((0, -0.012, 0)), 0.023, sym=True)
    s.ball(el, 0.022, sym=True)
    s.capsule(el, wr, 0.019, sym=True)
    s.ball(g.lerp(el, wr, 0.25), 0.024, sym=True)
    s.ball(wr, 0.019, sym=True)
    pa, fd, w, n = g.hand_frame()
    for o in (0.009, -0.009):
        s.ball(pa + w * o, 0.023, sym=True)
        s.ball(pa + fd * 0.016 + w * o, 0.02, sym=True)
    hp, kn, an, bl = J["hip"], J["knee"], J["ankle"], J["ball"]
    s.ball(hp + V((0, 0.03, 0)), 0.042, sym=True)
    s.capsule(hp, kn, 0.036, sym=True)
    s.ball(g.lerp(hp, kn, 0.4) + V((0, -0.012, 0)), 0.038, sym=True)
    s.ball(kn, 0.028, sym=True)
    s.capsule(kn, an, 0.022, sym=True)
    s.ball(g.lerp(kn, an, 0.35) + V((0, 0.015, 0)), 0.026, sym=True)
    s.ball(an, 0.021, sym=True)
    s.capsule(an, bl, 0.018, sym=True)
    return s.obj


def kobold_horns():
    """Two horns swept back from the top of the skull, curling slightly outward."""
    horns = []
    h = J["head"]
    for side in (1, -1):
        base = h + V((0.03 * side, 0.025, 0.055))
        tip = h + V((0.055 * side, 0.135, 0.105))
        bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.016, radius2=0.002, depth=(tip - base).length)
        horn = bpy.context.active_object
        for v in horn.data.vertices:  # curl back toward the tip
            t = (v.co.z + (tip - base).length / 2) / (tip - base).length
            v.co.y -= 0.012 * t * t
        horn.rotation_mode = "QUATERNION"
        horn.rotation_quaternion = V((0, 0, 1)).rotation_difference((tip - base).normalized())
        horn.location = (base + tip) / 2
        horns.append(horn)
    return horns


def kobold_eyes():
    eyes = []
    h = J["head"]
    for side in (1, -1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.0115, location=h + V((0.033 * side, -0.043, 0.012)))
        eyes.append(bpy.context.active_object)
    e = g.join(eyes, "KoboldEyes")
    bpy.ops.object.shade_smooth()
    g.assign(e, g.mat_eyes())
    return e


def kobold_teeth():
    parts = []
    h = J["head"]
    for side in (1, -1):
        for i in range(5):
            y = -0.07 - i * 0.017
            parts.append(g.cone_between(h + V((0.021 * side, y, -0.036)), h + V((0.021 * side, y - 0.002, -0.05)), 0.0032, "Tooth", 6))
        parts.append(g.cone_between(h + V((0.016 * side, -0.13, -0.05)), h + V((0.018 * side, -0.132, -0.032)), 0.0035, "Fang", 6))
    t = g.join(parts, "KoboldTeeth")
    g.assign(t, g.mat_simple("kobold_teeth_src", (0.62, 0.56, 0.42), 0.45))
    return t


def kobold_skin():
    mat = bpy.data.materials.new("kobold_skin_src")
    n = g.Nodes(mat)
    geo = n.add("ShaderNodeNewGeometry")
    base = n.ramp(n.noise(4.0, 6.0, 0.6).outputs["Fac"], [(0.3, (0.055, 0.03, 0.017)), (0.75, (0.15, 0.08, 0.04))])
    scales = n.add("ShaderNodeTexVoronoi")
    scales.feature = "DISTANCE_TO_EDGE"
    scales.inputs["Scale"].default_value = 140.0
    edges = n.ramp(scales.outputs["Distance"], [(0.0, (1, 1, 1)), (0.08, (0, 0, 0))])
    bw = n.add("ShaderNodeRGBToBW")
    n.link(edges.outputs["Color"], bw.inputs["Color"])
    col = n.mix(n.map_range(bw.outputs["Val"], 0, 1, 0, 0.55), base.outputs["Color"], (0.025, 0.014, 0.008))
    sep = n.add("ShaderNodeSeparateXYZ")
    n.link(geo.outputs["Position"], sep.inputs["Vector"])
    belly = n.map_range(sep.outputs["Y"], -0.16, -0.05, 0.45, 0.0)               # paler throat and belly
    col = n.mix(belly, col, (0.2, 0.15, 0.09))
    dirt = n.map_range(sep.outputs["Z"], 0.0, 0.2, 0.7, 0.0)
    col = n.mix(dirt, col, (0.02, 0.015, 0.01))
    col = n.ao(col, 0.05, 0.45)
    n.link(col, n.bsdf.inputs["Base Color"])
    n.link(n.map_range(n.noise(12.0).outputs["Fac"], 0, 1, 0.35, 0.6), n.bsdf.inputs["Roughness"])
    n.bump(scales.outputs["Distance"], 0.45, 0.0015)
    return mat


def spear_frame():
    """Grip point and shaft direction in the RIGHT hand: mostly upright, tip leaning forward."""
    pa, fd, w, n = g.hand_frame()
    grip = g.mirror_x(pa + fd * 0.045 + n * 0.01)
    return grip, V((0, -0.32, 1.0)).normalized()


def kobold_spear():
    random.seed(3)
    length = 1.2
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.011, depth=length)
    shaft = bpy.context.active_object
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.subdivide(number_cuts=10)
    bpy.ops.object.mode_set(mode="OBJECT")
    for v in shaft.data.vertices:                     # slightly crooked branch
        t = v.co.z / length + 0.5
        v.co.x += 0.006 * math.sin(t * 5.0)
        v.co.z += length * 0.15                       # grip about a third of the way up
    g.assign(shaft, g.mat_simple("kobold_wood_src", (0.2, 0.13, 0.07), 0.8, wood=True))
    tip_z = length * 0.65
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.028, radius2=0.0, depth=0.16, location=(0, 0, tip_z + 0.08))
    head = bpy.context.active_object
    head.scale = (1.0, 0.25, 1.0)                     # flat leaf blade
    bpy.ops.object.transform_apply(scale=True)
    g.assign(head, g.mat_simple("kobold_iron_src", (0.16, 0.15, 0.14), 0.55, bump_scale=60.0, bump_strength=0.3))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.014, minor_radius=0.004, location=(0, 0, tip_z - 0.01))
    binding = bpy.context.active_object
    g.assign(binding, g.mat_simple("kobold_binding_src", (0.18, 0.12, 0.07), 0.9, cloth=True))
    spear = g.join([shaft, head, binding], "Club")    # named Club: it uses the Goblin's hand-held weapon path
    grip, axis = spear_frame()
    spear.rotation_mode = "QUATERNION"
    spear.rotation_quaternion = V((0, 0, 1)).rotation_difference(axis)
    spear.location = grip
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.shade_smooth()
    return spear


g.build_body = kobold_body
g.build_ears = kobold_horns
g.build_eyes = kobold_eyes
g.build_teeth = kobold_teeth
g.mat_skin = kobold_skin
g.build_club = kobold_spear

if __name__ == "__main__":
    g.stage_full()
