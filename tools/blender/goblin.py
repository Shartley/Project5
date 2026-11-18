"""Builds the Goblin enemy in Blender from code, then renders previews and exports it for Godot.

Run (Blender 5.x):
    blender -b --factory-startup -P tools/blender/goblin.py -- <out_dir> <stage>

Stages:
    sculpt  - build the high-detail body and render clay previews
    (later) bake, rig, export

The body is sculpted from metaballs (soft blended shapes) so muscles and joints flow into each
other, then voxel-remeshed into one watertight skin. All shapes are original designs.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(ARGS[0]) if ARGS else os.path.abspath("goblin_out")
STAGE = ARGS[1] if len(ARGS) > 1 else "sculpt"
os.makedirs(OUT_DIR, exist_ok=True)

V = Vector

# Used in output file names; tools/blender/kobold.py sets this to "kobold" and reuses this script.
NAME = "goblin"

# A metaball's visible surface sits well inside its radius: with threshold 0.6 and stiffness 2 an
# isolated ball shows at ~0.575 of its radius. Radii below are the sizes we want to SEE, so they
# are scaled up by this factor when the elements are created.
RADIUS_SCALE = 1.0 / 0.575


# --------------------------------------------------------------------------------------------
# Scene helpers
# --------------------------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    return scene


def mirror_x(p):
    return V((-p[0], p[1], p[2]))


class Sculpt:
    """Collects metaball elements; every call with sym=True also adds the mirrored element."""

    def __init__(self, name, resolution=0.006):
        self.data = bpy.data.metaballs.new(name)
        self.data.resolution = resolution
        self.data.render_resolution = resolution
        self.data.threshold = 0.6
        self.obj = bpy.data.objects.new(name, self.data)
        bpy.context.collection.objects.link(self.obj)

    def _new(self, kind, co, radius, stiffness, negative):
        e = self.data.elements.new(type=kind)
        e.co = co
        e.radius = radius * RADIUS_SCALE
        e.stiffness = stiffness
        e.use_negative = negative
        return e

    def ball(self, co, r, stiff=2.0, neg=False, sym=False):
        self._new("BALL", V(co), r, stiff, neg)
        if sym:
            self._new("BALL", mirror_x(co), r, stiff, neg)

    def ellipsoid(self, co, r, size, stiff=2.0, neg=False, sym=False, axis=None):
        for c, flip in ((V(co), 1), (mirror_x(co), -1)) if sym else ((V(co), 1),):
            e = self._new("ELLIPSOID", c, r, stiff, neg)
            e.size_x, e.size_y, e.size_z = size
            if axis is not None:
                a = V((axis[0] * flip, axis[1], axis[2])).normalized()
                e.rotation = V((1, 0, 0)).rotation_difference(a)

    def capsule(self, a, b, r, stiff=2.0, neg=False, sym=False):
        pairs = [(V(a), V(b))]
        if sym:
            pairs.append((mirror_x(a), mirror_x(b)))
        for p, q in pairs:
            d = q - p
            e = self._new("CAPSULE", (p + q) / 2, r, stiff, neg)
            e.size_x = d.length / 2
            e.rotation = V((1, 0, 0)).rotation_difference(d.normalized())

    def chain(self, points, radii, stiff=2.0, sym=False):
        for i in range(len(points) - 1):
            self.capsule(points[i], points[i + 1], (radii[i] + radii[i + 1]) / 2, stiff, sym=sym)


def lerp(a, b, t):
    return V(a).lerp(V(b), t)


# --------------------------------------------------------------------------------------------
# Goblin anatomy (metres, Blender axes: +Z up, character faces -Y). A-pose, hunched, ~1.25 m.
# --------------------------------------------------------------------------------------------

J = {
    # spine
    "pelvis": V((0, 0.005, 0.62)),
    "waist": V((0, -0.01, 0.73)),
    "ribs": V((0, -0.05, 0.86)),
    "upper_chest": V((0, -0.085, 0.95)),
    "neck_base": V((0, -0.12, 1.0)),
    "neck_top": V((0, -0.17, 1.065)),
    "head": V((0, -0.20, 1.10)),
    "head_top": V((0, -0.215, 1.21)),
    "clavicle": V((0.03, -0.1, 0.985)),
    # left arm (right side mirrored)
    "shoulder": V((0.15, -0.08, 0.965)),
    "elbow": V((0.29, -0.055, 0.79)),
    "wrist": V((0.385, -0.10, 0.635)),
    "palm": V((0.41, -0.12, 0.585)),
    # left leg
    "hip": V((0.085, 0.0, 0.6)),
    "knee": V((0.115, -0.075, 0.34)),
    "ankle": V((0.12, -0.01, 0.075)),
    "ball": V((0.125, -0.10, 0.025)),
}


def build_body():
    s = Sculpt("GoblinSculpt")

    # ---- torso: narrow, wiry, with a small pot belly, visible ribs and spine
    s.ellipsoid(J["pelvis"], 0.11, (1.0, 0.8, 0.75))
    s.ellipsoid((0, -0.045, 0.73), 0.095, (0.9, 0.9, 0.95))                        # pot belly
    s.ball((0, 0.0, 0.765), 0.08)                                                  # waist fill
    s.ellipsoid(J["ribs"], 0.118, (1.0, 0.8, 1.0), axis=(0, -0.25, 1))
    s.ellipsoid(J["upper_chest"], 0.105, (1.2, 0.75, 0.62))
    s.ellipsoid((0.055, -0.12, 0.92), 0.042, (1.0, 0.6, 0.8), sym=True)            # pecs
    s.ball((0.065, -0.005, 0.945), 0.04, sym=True)                                 # shoulder blades
    s.capsule((-0.08, -0.07, 1.0), (0.08, -0.07, 1.0), 0.038)                      # trapezius
    s.capsule(J["neck_base"], J["neck_top"], 0.036)
    for i in range(9):                                                              # vertebrae
        t = i / 8
        s.ball((0, 0.072 - 0.05 * t * t, 0.64 + 0.34 * t), 0.011, stiff=1.5)

    # ---- head
    h = J["head"]
    s.ellipsoid(h + V((0, 0.03, 0.035)), 0.095, (1.0, 1.18, 0.98))                 # cranium
    s.capsule((-0.052, -0.268, 1.132), (0.052, -0.268, 1.132), 0.024)              # brow ridge
    s.ball((0.047, -0.262, 1.088), 0.027, sym=True)                                # cheekbones
    s.ellipsoid((0, -0.285, 1.07), 0.045, (1.0, 0.9, 0.8))                         # muzzle
    s.ellipsoid((0, -0.276, 1.034), 0.052, (1.15, 1.05, 0.6))                      # jaw, underbite
    s.ball((0, -0.306, 1.02), 0.022)                                               # chin
    s.chain([(0, -0.29, 1.113), (0, -0.33, 1.098), (0, -0.347, 1.072)], [0.018, 0.016, 0.012])  # hooked nose
    s.ball((0.012, -0.338, 1.08), 0.011, sym=True)                                 # nostril wings
    s.ball((0.033, -0.272, 1.104), 0.021, neg=True, sym=True)                      # eye sockets
    s.capsule((-0.034, -0.316, 1.046), (0.034, -0.316, 1.046), 0.008, neg=True)    # mouth slit

    # ---- arms: thin, long, knobby elbows
    sh, el, wr = J["shoulder"], J["elbow"], J["wrist"]
    s.ball(sh + V((0.01, 0, 0.01)), 0.042, sym=True)                               # deltoid
    s.capsule(sh, el, 0.028, sym=True)
    s.ball(lerp(sh, el, 0.45) + V((0, -0.016, 0)), 0.03, sym=True)                 # biceps
    s.ball(lerp(sh, el, 0.5) + V((0, 0.016, 0)), 0.028, sym=True)                  # triceps
    s.ball(el, 0.03, sym=True)                                                     # elbow
    s.capsule(el, wr, 0.024, sym=True)
    s.ball(lerp(el, wr, 0.25), 0.031, sym=True)                                    # forearm muscle
    s.ball(wr, 0.024, sym=True)

    # ---- hands: three long clawed fingers and a thumb, palm facing the thigh
    fd = (wr - el).normalized()
    up = V((0, -1, 0))
    w = (up - fd * fd.dot(up)).normalized()                                        # across the palm, toward the front
    n = fd.cross(w).normalized()
    if n.x > 0:
        n = -n                                                                     # palm side faces the body
    pa = wr + fd * 0.045
    for o in (0.012, -0.012):
        s.ball(pa + w * o, 0.03, sym=True)
        s.ball(pa + fd * 0.022 + w * o, 0.026, sym=True)

    # ---- legs: lean thighs, knobby knees, long toes
    hp, kn, an, bl = J["hip"], J["knee"], J["ankle"], J["ball"]
    s.ball(hp + V((0, 0.04, 0)), 0.05, sym=True)                                   # glutes
    s.capsule(hp, kn, 0.045, sym=True)
    s.ball(lerp(hp, kn, 0.4) + V((0, -0.02, 0)), 0.044, sym=True)                  # quads
    s.ball(kn, 0.038, sym=True)
    s.ball(kn + V((0, -0.025, 0)), 0.022, sym=True)                                # kneecap
    s.capsule(kn, an, 0.026, sym=True)
    s.ball(lerp(kn, an, 0.3) + V((0, 0.025, 0)), 0.036, sym=True)                  # calf
    s.ball(an, 0.026, sym=True)
    s.capsule(an, bl, 0.028, sym=True)
    s.ball(an + V((0, 0.03, -0.03)), 0.026, sym=True)                              # heel
    return s.obj


def hand_frame():
    """Directions for the left hand: fd along the fingers, w across the palm (front), n into the palm."""
    el, wr = J["elbow"], J["wrist"]
    fd = (wr - el).normalized()
    up = V((0, -1, 0))
    w = (up - fd * fd.dot(up)).normalized()
    n = fd.cross(w).normalized()
    if n.x > 0:
        n = -n
    return wr + fd * 0.045, fd, w, n


def digit_chains():
    """Left-side finger, thumb and toe chains as (points, radii); claws sit on the last point."""
    pa, fd, w, n = hand_frame()
    chains = []
    for o in (0.026, 0.004, -0.018):
        k = pa + fd * 0.03 + w * o
        m = k + fd * 0.05 + n * 0.008 + w * o * 0.15
        t = m + fd * 0.042 + n * 0.018
        chains.append(([k, m, t], [0.0115, 0.0098, 0.0075]))
    tb = pa + w * 0.03 - fd * 0.005
    tm = tb + (w * 0.6 + fd * 0.6 + n * 0.3).normalized() * 0.035
    tt = tm + (w * 0.3 + fd * 0.7 + n * 0.5).normalized() * 0.03
    chains.append(([tb, tm, tt], [0.012, 0.0105, 0.0078]))
    bl = J["ball"]
    for dx in (-0.026, 0.0, 0.026):
        t0 = bl + V((dx, 0.005, -0.004))
        t1 = t0 + V((dx * 0.35, -0.04, -0.004))
        t2 = t1 + V((dx * 0.15, -0.025, -0.008))
        chains.append(([t0, t1, t2], [0.0135, 0.011, 0.008]))
    return chains


def build_digits():
    """Fingers and toes from a skin modifier, so each keeps its exact thickness and stays separate."""
    verts, edges, radii, roots = [], [], [], []
    for pts, rads in digit_chains():
        for mirror in (False, True):
            base = len(verts)
            roots.append(base)
            for i, (p, r) in enumerate(zip(pts, rads)):
                verts.append(tuple(mirror_x(p) if mirror else p))
                radii.append(r)
                if i:
                    edges.append((base + i - 1, base + i))
    me = bpy.data.meshes.new("Digits")
    me.from_pydata(verts, edges, [])
    obj = bpy.data.objects.new("Digits", me)
    bpy.context.collection.objects.link(obj)
    obj.modifiers.new("Skin", "SKIN")
    layer = me.skin_vertices[0].data
    for i, r in enumerate(radii):
        layer[i].radius = (r, r)
        layer[i].use_root = i in roots
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = 2
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return obj


def build_ears():
    """Long pointed ears: a flattened, slightly cupped cone swept back and up."""
    objs = []
    for side in (1, -1):
        bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.04, radius2=0.002, depth=0.17)
        ear = bpy.context.active_object
        ear.scale = (1.0, 0.32, 1.0)
        bpy.ops.object.transform_apply(scale=True)
        # bend the cone so the tip curls back
        for v in ear.data.vertices:
            t = (v.co.z + 0.085) / 0.17
            v.co.y += 0.02 * t * t
        base = V((0.068 * side, -0.19, 1.125))
        tip = V((0.215 * side, -0.14, 1.205))
        d = (tip - base).normalized()
        ear.rotation_mode = "QUATERNION"
        ear.rotation_quaternion = V((0, 0, 1)).rotation_difference(d)
        ear.location = (base + tip) / 2
        objs.append(ear)
    return objs


def to_mesh(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    return bpy.context.active_object


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def remesh(obj, voxel):
    m = obj.modifiers.new("Remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    m.adaptivity = 0.0
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=m.name)


def smooth(obj, factor=0.5, repeat=4):
    m = obj.modifiers.new("Smooth", "LAPLACIANSMOOTH")
    m.lambda_factor = factor
    m.iterations = repeat
    m.use_volume_preserve = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=m.name)


def build_sculpt():
    body = to_mesh(build_body())
    ears = build_ears()
    digits = build_digits()
    skin = join([body, digits] + ears, "GoblinHigh")
    remesh(skin, 0.0035)
    smooth(skin, 0.4, 3)
    bpy.ops.object.shade_smooth()
    return skin


# --------------------------------------------------------------------------------------------
# Preview rendering
# --------------------------------------------------------------------------------------------

def setup_render(scene, res=900, samples=24):
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = "GPU"
    except Exception as exc:  # CPU fallback
        print("GPU setup failed, using CPU:", exc)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("World")
    world.color = (0.05, 0.055, 0.065)
    scene.world = world
    for name, loc, energy, size in (("Key", (1.6, -2.2, 2.4), 260, 1.2), ("Rim", (-1.2, 1.8, 2.0), 220, 1.0), ("Fill", (-2.0, -1.5, 1.0), 70, 2.0)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.size = size
        o = bpy.data.objects.new(name, light)
        o.location = loc
        o.rotation_euler = (V((0, 0, 0.7)) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(o)


def clay(obj):
    mat = bpy.data.materials.new("Clay")
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.42, 0.44, 0.40, 1)
    bsdf.inputs["Roughness"].default_value = 0.6
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def render_views(scene, tag, target=V((0, -0.05, 0.66)), dist=2.6):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 60
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, ang in (("front", 0), ("three_quarter", 40), ("side", 90)):
        a = math.radians(ang)
        cam.location = target + V((math.sin(a) * dist, -math.cos(a) * dist, 0.15))
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(OUT_DIR, f"{tag}_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


def stage_sculpt():
    scene = reset_scene()
    skin = build_sculpt()
    print("high poly faces:", len(skin.data.polygons))
    clay(skin)
    setup_render(scene)
    render_views(scene, "sculpt")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "goblin_sculpt.blend"))


# --------------------------------------------------------------------------------------------
# Materials (procedural, used as bake sources)
# --------------------------------------------------------------------------------------------

class Nodes:
    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.out = self.add("ShaderNodeOutputMaterial", (900, 0))
        self.bsdf = self.add("ShaderNodeBsdfPrincipled", (600, 0))
        self.link(self.bsdf.outputs["BSDF"], self.out.inputs["Surface"])

    def add(self, kind, loc=(0, 0), **props):
        n = self.nt.nodes.new(kind)
        n.location = loc
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def noise(self, scale, detail=4.0, rough=0.55):
        n = self.add("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        return n

    def ramp(self, src, stops):
        r = self.add("ShaderNodeValToRGB")
        els = r.color_ramp.elements
        while len(els) > len(stops):
            els.remove(els[-1])
        while len(els) < len(stops):
            els.new(0.5)
        for e, (pos, col) in zip(els, stops):
            e.position = pos
            e.color = (*col, 1.0)
        self.link(src, r.inputs["Fac"])
        return r

    def mix(self, fac, a, b, blend="MIX"):
        m = self.add("ShaderNodeMix")
        m.data_type = "RGBA"
        m.blend_type = blend
        sock = lambda node, ident, out=False: next(x for x in (node.outputs if out else node.inputs) if x.identifier == ident)
        if isinstance(fac, float):
            m.inputs["Factor"].default_value = fac
        else:
            self.link(fac, m.inputs["Factor"])
        for ident, val in (("A_Color", a), ("B_Color", b)):
            if isinstance(val, tuple):
                sock(m, ident).default_value = (*val, 1.0)
            else:
                self.link(val, sock(m, ident))
        return sock(m, "Result_Color", out=True)

    def bump(self, height, strength, distance):
        b = self.add("ShaderNodeBump")
        b.inputs["Strength"].default_value = strength
        b.inputs["Distance"].default_value = distance
        self.link(height, b.inputs["Height"])
        self.link(b.outputs["Normal"], self.bsdf.inputs["Normal"])
        return b

    def ao(self, color, distance=0.05, floor=0.35):
        a = self.add("ShaderNodeAmbientOcclusion")
        a.inputs["Distance"].default_value = distance
        self.link(color, a.inputs["Color"])
        # darken toward near-black in creases; `floor` is how much of the colour survives full occlusion
        return self.mix(self.inv(a.outputs["AO"], floor), color, (0.02, 0.02, 0.015))

    def inv(self, value, floor):
        # 0 when fully open, (1 - floor) when fully occluded
        m = self.add("ShaderNodeMapRange")
        m.inputs["From Min"].default_value = 0.0
        m.inputs["From Max"].default_value = 1.0
        m.inputs["To Min"].default_value = 1.0 - floor
        m.inputs["To Max"].default_value = 0.0
        self.link(value, m.inputs["Value"])
        return m.outputs["Result"]

    def map_range(self, value, a, b, c, d):
        m = self.add("ShaderNodeMapRange")
        for k, v in (("From Min", a), ("From Max", b), ("To Min", c), ("To Max", d)):
            m.inputs[k].default_value = v
        self.link(value, m.inputs["Value"])
        return m.outputs["Result"]


def mat_skin():
    mat = bpy.data.materials.new("goblin_skin_src")
    n = Nodes(mat)
    geo = n.add("ShaderNodeNewGeometry")
    mottled = n.ramp(n.noise(5.0, 6.0, 0.6).outputs["Fac"], [(0.3, (0.042, 0.05, 0.026)), (0.7, (0.12, 0.13, 0.075))])
    fine = n.ramp(n.noise(28.0, 3.0).outputs["Fac"], [(0.35, (0.0, 0.0, 0.0)), (0.65, (1.0, 1.0, 1.0))])
    col = n.mix(0.25, mottled.outputs["Color"], (0.085, 0.062, 0.038), "MIX")
    col = n.mix(fine.outputs["Color"], col, n.mix(0.25, col, (0.15, 0.155, 0.095)), "MIX")
    vor = n.add("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 34.0
    spots = n.ramp(vor.outputs["Distance"], [(0.08, (1, 1, 1)), (0.22, (0, 0, 0))])
    spot_mask = n.ramp(n.noise(3.0).outputs["Fac"], [(0.45, (0, 0, 0)), (0.6, (1, 1, 1))])
    spot_fac = n.mix(spot_mask.outputs["Color"], (0, 0, 0), spots.outputs["Color"], "MIX")
    bw = n.add("ShaderNodeRGBToBW")
    n.link(spot_fac, bw.inputs["Color"])
    col = n.mix(n.map_range(bw.outputs["Val"], 0, 1, 0, 0.6), col, (0.04, 0.026, 0.016))
    sep = n.add("ShaderNodeSeparateXYZ")
    n.link(geo.outputs["Position"], sep.inputs["Vector"])
    dirt = n.map_range(sep.outputs["Z"], 0.0, 0.22, 0.75, 0.0)
    col = n.mix(dirt, col, (0.022, 0.017, 0.011))
    col = n.ao(col, 0.06, 0.45)
    n.link(col, n.bsdf.inputs["Base Color"])
    rough = n.map_range(n.noise(9.0).outputs["Fac"], 0, 1, 0.42, 0.72)
    n.link(rough, n.bsdf.inputs["Roughness"])
    wr = n.add("ShaderNodeTexVoronoi")
    wr.feature = "DISTANCE_TO_EDGE"
    wr.inputs["Scale"].default_value = 85.0
    pores = n.noise(260.0, 2.0)
    h = n.add("ShaderNodeMath")
    h.operation = "MULTIPLY_ADD"
    n.link(wr.outputs["Distance"], h.inputs[0])
    h.inputs[1].default_value = 1.0
    n.link(pores.outputs["Fac"], h.inputs[2])
    n.bump(h.outputs[0], 0.32, 0.0025)
    return mat


def mat_simple(name, color, rough, bump_scale=0.0, bump_strength=0.0, wood=False, cloth=False):
    mat = bpy.data.materials.new(name)
    n = Nodes(mat)
    if wood:
        wave = n.add("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.bands_direction = "Z"
        wave.inputs["Scale"].default_value = 2.5
        wave.inputs["Distortion"].default_value = 9.0
        wave.inputs["Detail"].default_value = 6.0
        grain = n.ramp(wave.outputs["Fac"], [(0.2, (0.10, 0.062, 0.035)), (0.8, (0.27, 0.17, 0.095))])
        col = n.ao(grain.outputs["Color"], 0.04, 0.5)
        n.link(col, n.bsdf.inputs["Base Color"])
        n.bump(wave.outputs["Fac"], 0.4, 0.002)
    elif cloth:
        dirt = n.ramp(n.noise(7.0, 5.0).outputs["Fac"], [(0.3, (0.09, 0.065, 0.045)), (0.75, color)])
        col = n.ao(dirt.outputs["Color"], 0.05, 0.55)
        n.link(col, n.bsdf.inputs["Base Color"])
        weave = n.noise(420.0, 1.0)
        n.bump(weave.outputs["Fac"], 0.25, 0.0015)
    else:
        n.bsdf.inputs["Base Color"].default_value = (*color, 1)
        if bump_scale:
            n.bump(n.noise(bump_scale).outputs["Fac"], bump_strength, 0.001)
    n.bsdf.inputs["Roughness"].default_value = rough
    return mat


def mat_eyes():
    mat = bpy.data.materials.new("goblin_eyes")
    n = Nodes(mat)
    n.bsdf.inputs["Base Color"].default_value = (0.75, 0.62, 0.18, 1)
    n.bsdf.inputs["Roughness"].default_value = 0.08
    n.bsdf.inputs["Emission Color"].default_value = (0.247, 0.722, 1.0, 1)
    n.bsdf.inputs["Emission Strength"].default_value = 1.5
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


# --------------------------------------------------------------------------------------------
# Props: eyes, teeth, claws, loincloth, club
# --------------------------------------------------------------------------------------------

def cone_between(base, tip, r, name, verts=8):
    d = V(tip) - V(base)
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0.0, depth=d.length)
    o = bpy.context.active_object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = V((0, 0, 1)).rotation_difference(d.normalized())
    o.location = (V(base) + V(tip)) / 2
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def build_eyes():
    eyes = []
    for side in (1, -1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.0145, location=(0.032 * side, -0.271, 1.103))
        eyes.append(bpy.context.active_object)
    e = join(eyes, "GoblinEyes")
    bpy.ops.object.shade_smooth()
    assign(e, mat_eyes())
    return e


def build_teeth():
    parts = []
    for side in (1, -1):
        parts.append(cone_between((0.023 * side, -0.316, 1.036), (0.03 * side, -0.33, 1.07), 0.0068, "Tusk"))
    for x in (-0.014, -0.005, 0.005, 0.014):
        parts.append(cone_between((x, -0.322, 1.058), (x * 1.05, -0.326, 1.047), 0.0032, "Tooth", 6))
    t = join(parts, "GoblinTeeth")
    assign(t, mat_simple("goblin_teeth_src", (0.62, 0.55, 0.38), 0.45))
    return t


def build_claws():
    parts = []
    for pts, rads in digit_chains():
        a, b = V(pts[-2]), V(pts[-1])
        d = (b - a).normalized()
        for mirror in (False, True):
            base = b - d * 0.004
            tip = b + d * 0.022 + V((0, 0, -0.006))
            if mirror:
                base, tip = mirror_x(base), mirror_x(tip)
            parts.append(cone_between(base, tip, rads[-1] * 0.85, "Claw", 6))
    c = join(parts, "GoblinClaws")
    assign(c, mat_simple("goblin_claw_src", (0.05, 0.045, 0.04), 0.35))
    return c


def build_loincloth():
    import random
    random.seed(4)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=1.0, depth=1.0, end_fill_type="NOTHING")
    o = bpy.context.active_object
    o.name = "Loincloth"
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.subdivide(number_cuts=4)
    bpy.ops.object.mode_set(mode="OBJECT")
    for v in o.data.vertices:
        t = v.co.z + 0.5                       # 0 bottom .. 1 top
        ang = math.atan2(v.co.y, v.co.x)
        front = max(0.0, -math.sin(ang))       # 1 at the front (-Y)
        back = max(0.0, math.sin(ang))
        flare = 1.0 + (1.0 - t) * 0.28
        k = J["hip"].x / 0.085                 # 1.0 for the goblin; smaller bodies get a smaller wrap
        rx, ry = 0.142 * k * flare, 0.128 * k * flare
        z_top = J["pelvis"].z + 0.045
        z_bot = J["pelvis"].z - 0.12 - (0.09 * front ** 3 + 0.05 * back ** 4) * k
        hem = (1.0 - t) * random.uniform(-0.018, 0.012) if t < 0.2 else 0.0
        v.co.x = math.cos(ang) * rx
        v.co.y = math.sin(ang) * ry + 0.008
        v.co.z = z_bot + (z_top - z_bot) * t + hem
    sol = o.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.005
    tex = bpy.data.textures.new("folds", "CLOUDS")
    tex.noise_scale = 0.06
    dis = o.modifiers.new("Folds", "DISPLACE")
    dis.texture = tex
    dis.strength = 0.012
    sub = o.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    k = J["hip"].x / 0.085
    bpy.ops.mesh.primitive_torus_add(major_radius=0.146 * k, minor_radius=0.011, major_segments=48, minor_segments=8, location=(0, 0.006, J["pelvis"].z + 0.038))
    belt = bpy.context.active_object
    belt.scale = (1.0, 0.9, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    lc = join([o, belt], "Loincloth")
    bpy.ops.object.shade_smooth()
    assign(lc, mat_simple("goblin_cloth_src", (0.24, 0.17, 0.11), 0.92, cloth=True))
    return lc


def club_frame():
    """Grip centre and direction of the club in the RIGHT hand (mirror of the left-hand frame)."""
    pa, fd, w, n = hand_frame()
    grip = mirror_x(pa + fd * 0.055 + n * 0.012)
    axis = mirror_x((w * 0.85 + V((0, 0, 0.35))).normalized())
    return grip, axis.normalized()


def build_club():
    import random
    random.seed(9)
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=1.0, depth=1.0)
    o = bpy.context.active_object
    o.name = "Club"
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.subdivide(number_cuts=14)
    bpy.ops.object.mode_set(mode="OBJECT")
    length = 0.62
    for v in o.data.vertices:
        t = v.co.z + 0.5
        r = 0.019 + 0.03 * max(0.0, (t - 0.35) / 0.65) ** 1.4
        if t > 0.93:
            r *= max(0.25, 1.0 - (t - 0.93) / 0.07 * 0.75)
        if t < 0.03:
            r *= 0.8
        ang = math.atan2(v.co.y, v.co.x)
        knot = 0.0
        for kt, ka in ((0.55, 1.0), (0.72, 3.4), (0.86, 5.2)):
            knot += 0.012 * math.exp(-((t - kt) / 0.035) ** 2) * max(0.0, math.cos(ang - ka)) ** 2
        rr = r + knot
        v.co.x = math.cos(ang) * rr
        v.co.y = math.sin(ang) * rr
        v.co.z = (t - 0.12) * length            # grip near z=0
    tex = bpy.data.textures.new("bark", "CLOUDS")
    tex.noise_scale = 0.03
    dis = o.modifiers.new("Bark", "DISPLACE")
    dis.texture = tex
    dis.strength = 0.004
    sub = o.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    grip, axis = club_frame()
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = V((0, 0, 1)).rotation_difference(axis)
    o.location = grip
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.shade_smooth()
    assign(o, mat_simple("goblin_wood_src", (0.2, 0.13, 0.07), 0.78, wood=True))
    return o


# --------------------------------------------------------------------------------------------
# Low poly + bake
# --------------------------------------------------------------------------------------------

def duplicate(obj, name):
    c = obj.copy()
    c.data = obj.data.copy()
    c.name = name
    bpy.context.collection.objects.link(c)
    return c


def decimate(obj, target_tris):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris <= target_tris:
        return
    m = obj.modifiers.new("Dec", "DECIMATE")
    m.ratio = target_tris / tris
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=m.name)


def tag_group(obj, name):
    g = obj.vertex_groups.new(name=name)
    g.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")


def unwrap(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_maps(sources, target, size, out_prefix):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    bake = scene.render.bake
    bake.use_selected_to_active = True
    bake.cage_extrusion = 0.012
    bake.max_ray_distance = 0.04
    bake.margin = 6
    mat = bpy.data.materials.new(out_prefix + "_body")
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    images = {}
    for key, colorspace in (("albedo", "sRGB"), ("normal", "Non-Color"), ("roughness", "Non-Color")):
        img = bpy.data.images.new(f"{out_prefix}_{key}", size, size, alpha=False, float_buffer=False)
        img.colorspace_settings.name = colorspace
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.name = key
        images[key] = (img, node)
    target.data.materials.clear()
    target.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    for s in sources:
        s.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    for key, btype, kwargs in (("normal", "NORMAL", {"normal_space": "TANGENT"}),
                               ("albedo", "DIFFUSE", {"pass_filter": {"COLOR"}}),
                               ("roughness", "ROUGHNESS", {})):
        img, node = images[key]
        nt.nodes.active = node
        print("baking", key)
        bpy.ops.object.bake(type=btype, **kwargs)
        img.filepath_raw = os.path.join(OUT_DIR, f"{out_prefix}_{key}.png")
        img.file_format = "PNG"
        img.save()
    # wire the baked maps into the material used for export
    nt.links.new(images["albedo"][1].outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(images["roughness"][1].outputs["Color"], bsdf.inputs["Roughness"])
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(images["normal"][1].outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


# --------------------------------------------------------------------------------------------
# Rig
# --------------------------------------------------------------------------------------------

def bone_layout():
    pa, fd, w, n = hand_frame()
    toe_tip = J["ball"] + V((0.005, -0.07, -0.012))
    left = {
        "clavicle": (J["clavicle"], J["shoulder"], "chest"),
        "upper_arm": (J["shoulder"], J["elbow"], "clavicle"),
        "forearm": (J["elbow"], J["wrist"], "upper_arm"),
        "hand": (J["wrist"], pa + fd * 0.03, "forearm"),
        "fingers": (pa + fd * 0.03, pa + fd * 0.12 + n * 0.02, "hand"),
        "thigh": (J["hip"], J["knee"], "hips"),
        "shin": (J["knee"], J["ankle"], "thigh"),
        "foot": (J["ankle"], J["ball"], "shin"),
        "toes": (J["ball"], toe_tip, "foot"),
    }
    bones = {
        "root": ((0, 0, 0), (0, 0.12, 0), None),
        "hips": (J["pelvis"] + V((0, 0, -0.02)), J["waist"], "root"),
        "spine": (J["waist"], J["ribs"], "hips"),
        "chest": (J["ribs"], J["neck_base"], "spine"),
        "neck": (J["neck_base"], J["neck_top"], "chest"),
        "head": (J["neck_top"], J["head_top"], "neck"),
    }
    for name, (h, t, parent) in left.items():
        lp = parent if parent in ("chest", "hips") else parent + ".L"
        rp = parent if parent in ("chest", "hips") else parent + ".R"
        bones[name + ".L"] = (h, t, lp)
        bones[name + ".R"] = (mirror_x(h), mirror_x(t), rp)
    return bones


def build_armature():
    arm_data = bpy.data.armatures.new("GoblinRig")
    rig = bpy.data.objects.new("GoblinRig", arm_data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    layout = bone_layout()
    for name, (h, t, parent) in layout.items():
        b = arm_data.edit_bones.new(name)
        b.head = V(h)
        b.tail = V(t)
    for name, (h, t, parent) in layout.items():
        b = arm_data.edit_bones[name]
        if parent:
            b.parent = arm_data.edit_bones[parent]
            b.use_connect = False
        b.use_deform = name != "root"
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def skin_to(rig, obj, only_bone=None):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    if only_bone:
        bpy.ops.object.parent_set(type="ARMATURE_NAME")
        g = obj.vertex_groups.get(only_bone)
        g.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    else:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def force_group(obj, tag, bone):
    """Vertices in vertex group `tag` follow only `bone` (rigid props such as the club and teeth)."""
    tg = obj.vertex_groups.get(tag)
    if tg is None:
        return
    idx = [v.index for v in obj.data.vertices if any(g.group == tg.index and g.weight > 0.5 for g in v.groups)]
    for g in obj.vertex_groups:
        if g.name != tag and g.name != bone:
            g.remove(idx)
    target = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    target.add(idx, 1.0, "REPLACE")


def copy_nearest_weights(obj, tag, source_tag, bone_names):
    """Vertices tagged `tag` take the bone weights of the nearest vertex tagged `source_tag`."""
    from mathutils.kdtree import KDTree
    me = obj.data
    tg, sg = obj.vertex_groups.get(tag), obj.vertex_groups.get(source_tag)
    if tg is None or sg is None:
        return
    def tagged(group):
        return [v for v in me.vertices if any(g.group == group.index and g.weight > 0.5 for g in v.groups)]
    targets, sources = tagged(tg), tagged(sg)
    kd = KDTree(len(sources))
    for i, v in enumerate(sources):
        kd.insert(v.co, i)
    kd.balance()
    bone_idx = {obj.vertex_groups[b].index for b in bone_names if b in obj.vertex_groups}
    for v in targets:
        _, si, _ = kd.find(v.co)
        weights = [(g.group, g.weight) for g in sources[si].groups if g.group in bone_idx]
        for gi in bone_idx:
            obj.vertex_groups[gi].remove([v.index])
        for gi, w in weights:
            obj.vertex_groups[gi].add([v.index], w, "REPLACE")


# --------------------------------------------------------------------------------------------
# Animation (rotations given in rest-pose armature space, so bone roll does not matter)
# --------------------------------------------------------------------------------------------

AX = {"x": V((1, 0, 0)), "y": V((0, 1, 0)), "z": V((0, 0, 1))}


def world_rot(spec, side):
    """spec: list of (axis, degrees). Right-side bones flip Y/Z rotations so poses mirror."""
    from mathutils import Quaternion
    q = Quaternion()
    for axis, deg in spec:
        d = deg
        if side == "R" and axis in ("y", "z"):
            d = -deg
        q = Quaternion(AX[axis], math.radians(d)) @ q
    return q


def pose_key(rig, frame, pose, loc=None):
    """pose: {bone_name_without_side_or_full: [(axis, deg), ...]}; '.L/.R' added for limb bones."""
    from mathutils import Quaternion
    pb = rig.pose.bones
    for b in pb:
        b.rotation_mode = "QUATERNION"
        b.rotation_quaternion = Quaternion()
        b.location = V((0, 0, 0))
    for key, spec in pose.items():
        names = [key] if key in pb else [key + ".L", key + ".R"]
        for name in names:
            if name not in pb:
                continue
            side = name[-1] if name[-2:] in (".L", ".R") else "C"
            if key.endswith(".L") or key.endswith(".R"):
                side = key[-1]
            q = world_rot(spec, side)
            m = rig.data.bones[name].matrix_local.to_quaternion()
            pb[name].rotation_quaternion = m.inverted() @ q @ m
    if loc is not None:
        pb["hips"].location = rig.data.bones["hips"].matrix_local.to_quaternion().inverted() @ V(loc)
    for b in pb:
        b.keyframe_insert("rotation_quaternion", frame=frame)
        b.keyframe_insert("location", frame=frame)


def stance():
    return {
        "hips": [("x", 8)],
        "spine": [("x", 6)],
        "chest": [("x", 4)],
        "neck": [("x", -12)],
        "head": [("x", -6)],
        "upper_arm": [("y", 26), ("x", -8)],
        "forearm": [("x", -22)],
        "hand": [("x", -6)],
        "fingers": [("x", -25)],
        "fingers.R": [("x", -25), ("y", -55)],
        "thigh": [("x", -18)],
        "shin": [("x", 30)],
        "foot": [("x", -12)],
    }


def combine(*poses):
    out = {}
    for p in poses:
        for k, v in p.items():
            out[k] = out.get(k, []) + list(v)
    return out


def side_pose(bone, spec_l, spec_r):
    return {bone + ".L": spec_l, bone + ".R": spec_r}


def make_action(rig, name, frames, fn, loop):
    from mathutils import Quaternion
    rig.animation_data_create()
    act = bpy.data.actions.new(name)
    rig.animation_data.action = act
    for f in frames:
        pose, loc = fn(f)
        pose_key(rig, f, pose, loc)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(frames[0]), act)
    strip.name = name
    rig.animation_data.action = None
    return act


def build_animations(rig):
    st = stance()

    def idle(f):
        t = f / 60.0 * 2 * math.pi
        breath = math.sin(t)
        return combine(st, {
            "spine": [("x", 1.5 * breath)],
            "chest": [("x", -2.0 * breath)],
            "head": [("z", 6 * math.sin(t * 0.5)), ("x", 2 * breath)],
            "upper_arm": [("x", 2.5 * breath)],
        }), (0, 0, -0.006 * (1 + breath))

    def walk(f):
        t = f / 24.0 * 2 * math.pi
        s = math.sin(t)
        c = math.cos(t)
        lift_l = max(0.0, math.sin(t + math.pi / 2))
        lift_r = max(0.0, math.sin(t - math.pi / 2))
        return combine(st, {
            "hips": [("x", 6), ("z", 7 * s)],
            "spine": [("x", 4), ("z", -4 * s)],
            "chest": [("z", -5 * s)],
            "head": [("z", 4 * s)],
        },
            side_pose("thigh", [("x", -30 * s)], [("x", 30 * s)]),
            side_pose("shin", [("x", 55 * lift_l)], [("x", 55 * lift_r)]),
            side_pose("foot", [("x", -20 * lift_l + 12 * s)], [("x", -20 * lift_r - 12 * s)]),
            side_pose("upper_arm", [("x", 28 * s)], [("x", -28 * s)]),
            side_pose("forearm", [("x", -12 - 12 * max(0, -s))], [("x", -12 - 12 * max(0, s))]),
        ), (0, 0, -0.02 + 0.018 * abs(c))

    def windup(f):
        k = min(1.0, f / 24.0)
        e = 1 - (1 - k) ** 3
        return combine(st, {
            "spine": [("x", -10 * e), ("z", -22 * e)],
            "chest": [("x", -6 * e), ("z", -12 * e)],
            "head": [("z", 18 * e), ("x", 8 * e)],
            "upper_arm.R": [("x", -150 * e), ("y", -38 * e)],
            "forearm.R": [("x", -75 * e)],
            "hand.R": [("x", -20 * e)],
            "upper_arm.L": [("x", -35 * e), ("y", -10 * e)],
            "forearm.L": [("x", -25 * e)],
            "thigh.R": [("x", 10 * e)],
            "thigh.L": [("x", -14 * e)],
        }), (0, 0.02 * e, -0.015 * e)

    def attack(f):
        k = min(1.0, f / 12.0)
        e = k * k * (3 - 2 * k)
        return combine(st, {
            "spine": [("x", -10 + 34 * e), ("z", -22 + 40 * e)],
            "chest": [("x", -6 + 16 * e), ("z", -12 + 22 * e)],
            "head": [("z", 18 - 26 * e), ("x", 8 - 14 * e)],
            "upper_arm.R": [("x", -150 + 115 * e), ("y", -38 + 30 * e)],
            "forearm.R": [("x", -75 + 70 * e)],
            "hand.R": [("x", -20 + 30 * e)],
            "upper_arm.L": [("x", -35 + 50 * e), ("y", -10)],
            "forearm.L": [("x", -25)],
            "thigh.R": [("x", 10 - 30 * e)],
            "thigh.L": [("x", -14 + 20 * e)],
            "shin.R": [("x", 20 * e)],
        }), (0, 0.02 - 0.08 * e, -0.015 - 0.03 * e)

    def hit(f):
        k = math.sin(min(1.0, f / 9.0) * math.pi)
        return combine(st, {
            "spine": [("x", -14 * k)],
            "chest": [("x", -10 * k), ("z", 8 * k)],
            "head": [("x", -18 * k), ("z", -10 * k)],
            "upper_arm": [("y", 18 * k), ("x", 10 * k)],
        }), (0, 0.05 * k, 0)

    def death(f):
        k = min(1.0, f / 30.0)
        e = k * k
        return combine(st, {
            "hips": [("x", 70 * e)],
            "spine": [("x", 20 * e)],
            "chest": [("x", 15 * e)],
            "head": [("x", 25 * e)],
            "thigh": [("x", -60 * e)],
            "shin": [("x", 90 * e)],
            "upper_arm": [("y", -30 * e), ("x", -40 * e)],
        }), (0, -0.25 * e, -0.45 * e)

    scene = bpy.context.scene
    scene.render.fps = 30
    make_action(rig, "idle", range(0, 61, 3), idle, True)
    make_action(rig, "walk", range(0, 25, 2), walk, True)
    make_action(rig, "windup", range(0, 25, 3), windup, False)
    make_action(rig, "attack", range(0, 13, 2), attack, False)
    make_action(rig, "hit", range(0, 10, 3), hit, False)
    make_action(rig, "death", range(0, 31, 5), death, False)


# --------------------------------------------------------------------------------------------
# Full pipeline
# --------------------------------------------------------------------------------------------

def stage_full():
    scene = reset_scene()
    skin_hi = build_sculpt()
    assign(skin_hi, mat_skin())
    cloth_hi = build_loincloth()
    club_hi = build_club()
    teeth = build_teeth()
    claws = build_claws()
    eyes = build_eyes()

    parts_lo = []
    for src, name, tris, tag in ((skin_hi, "body_lo", 9000, "body"), (cloth_hi, "cloth_lo", 900, "cloth"), (club_hi, "club_lo", 500, "club")):
        lo = duplicate(src, name)
        lo.modifiers.clear()
        decimate(lo, tris)
        tag_group(lo, tag)
        parts_lo.append(lo)
    for src, tag in ((teeth, "teeth"), (claws, "claws")):
        lo = duplicate(src, src.name + "_lo")
        tag_group(lo, tag)
        parts_lo.append(lo)
    body = join(parts_lo, NAME.capitalize())
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.dissolve_degenerate(threshold=0.0001)
    bpy.ops.mesh.delete_loose()
    bpy.ops.object.mode_set(mode="OBJECT")
    body.data.validate(clean_customdata=False)
    bpy.ops.object.shade_smooth()
    unwrap(body)
    print("game mesh tris:", sum(len(p.vertices) - 2 for p in body.data.polygons))

    bake_maps([skin_hi, cloth_hi, club_hi, teeth, claws], body, 2048, NAME)

    rig = build_armature()
    skin_to(rig, body)
    force_group(body, "club", "hand.R")
    bone_names = [b.name for b in rig.data.bones]
    copy_nearest_weights(body, "claws", "body", bone_names)
    copy_nearest_weights(body, "teeth", "body", bone_names)
    copy_nearest_weights(body, "cloth", "body", bone_names)  # the wrap follows the hips and thighs under it
    skin_to(rig, eyes, only_bone="head")
    for tag in ("body", "cloth", "club", "teeth", "claws"):
        g = body.vertex_groups.get(tag)
        if g:
            body.vertex_groups.remove(g)
    build_animations(rig)

    for o in (skin_hi, cloth_hi, club_hi, teeth, claws):
        o.hide_render = True
        o.hide_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, NAME + "_full.blend"))
    export_glb(rig, body, eyes)
    render_beauty(scene, rig, body, eyes)


def export_glb(rig, body, eyes):
    bpy.ops.object.select_all(action="DESELECT")
    for o in (rig, body, eyes):
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    path = os.path.join(OUT_DIR, NAME + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_skins=True, export_yup=True)
    print("exported", path)


def render_beauty(scene, rig, body, eyes):
    setup_render(scene, res=900, samples=48)
    ad = rig.animation_data
    for t in ad.nla_tracks:
        t.mute = t.name != "windup"
    scene.frame_set(24)
    render_views(scene, NAME, target=V((0, -0.05, J["pelvis"].z + 0.08)), dist=2.4 * J["pelvis"].z / 0.62)
    for t in ad.nla_tracks:
        t.mute = t.name != "walk"
    scene.frame_set(6)
    scene.render.filepath = os.path.join(OUT_DIR, NAME + "_walk.png")
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    if STAGE == "sculpt":
        stage_sculpt()
    elif STAGE == "full":
        stage_full()
    else:
        raise SystemExit("unknown stage " + STAGE)
