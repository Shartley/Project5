"""Shared helpers for the Blender asset scripts (Blender 5.x, run in background mode)."""

import math
import os
import sys

import bpy
from mathutils import Vector

V = Vector


def args():
    """(out_dir, stage) from `blender -b -P script.py -- <out_dir> [stage]`."""
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(a[0]) if a else os.path.abspath("asset_out")
    os.makedirs(out_dir, exist_ok=True)
    return out_dir, (a[1] if len(a) > 1 else "full")


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifiers(obj):
    activate(obj)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


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
    apply_modifiers(obj)


def duplicate(obj, name):
    c = obj.copy()
    c.data = obj.data.copy()
    c.name = name
    bpy.context.collection.objects.link(c)
    return c


def decimate(obj, target_tris):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > target_tris:
        m = obj.modifiers.new("Dec", "DECIMATE")
        m.ratio = target_tris / tris
        apply_modifiers(obj)


def clean_mesh(obj):
    activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.dissolve_degenerate(threshold=0.0001)
    bpy.ops.mesh.delete_loose()
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.data.validate(clean_customdata=False)


def unwrap(obj, margin=0.004):
    activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=margin, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


class Nodes:
    """Small builder for Principled-BSDF node graphs."""

    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.out = self.add("ShaderNodeOutputMaterial")
        self.bsdf = self.add("ShaderNodeBsdfPrincipled")
        self.link(self.bsdf.outputs["BSDF"], self.out.inputs["Surface"])

    def add(self, kind):
        return self.nt.nodes.new(kind)

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

        def sock(ident, out=False):
            return next(x for x in (m.outputs if out else m.inputs) if x.identifier == ident)

        if isinstance(fac, float):
            m.inputs["Factor"].default_value = fac
        else:
            self.link(fac, m.inputs["Factor"])
        for ident, val in (("A_Color", a), ("B_Color", b)):
            if isinstance(val, tuple):
                sock(ident).default_value = (*val, 1.0)
            else:
                self.link(val, sock(ident))
        return sock("Result_Color", out=True)

    def map_range(self, value, a, b, c, d):
        m = self.add("ShaderNodeMapRange")
        for k, v in (("From Min", a), ("From Max", b), ("To Min", c), ("To Max", d)):
            m.inputs[k].default_value = v
        self.link(value, m.inputs["Value"])
        return m.outputs["Result"]

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
        fac = self.map_range(a.outputs["AO"], 0.0, 1.0, 1.0 - floor, 0.0)
        return self.mix(fac, color, (0.01, 0.01, 0.012))


def pbr(name, color, metallic, rough, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    n = Nodes(mat)
    n.bsdf.inputs["Base Color"].default_value = (*color, 1)
    n.bsdf.inputs["Metallic"].default_value = metallic
    n.bsdf.inputs["Roughness"].default_value = rough
    if emission:
        n.bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        n.bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def bake_maps(sources, target, size, out_dir, prefix, maps=("albedo", "normal", "roughness")):
    """Bakes the listed maps from `sources` onto `target` and gives it a material that uses them.

    maps may include: albedo, normal, roughness, emission.
    """
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    bake = scene.render.bake
    bake.use_selected_to_active = True
    bake.cage_extrusion = 0.015
    bake.max_ray_distance = 0.05
    bake.margin = 6
    mat = bpy.data.materials.new(prefix)
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    images = {}
    for key in maps:
        img = bpy.data.images.new(f"{prefix}_{key}", size, size, alpha=False)
        img.colorspace_settings.name = "sRGB" if key in ("albedo", "emission") else "Non-Color"
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        images[key] = (img, node)
    assign(target, mat)
    bpy.ops.object.select_all(action="DESELECT")
    for s in sources:
        s.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    plan = {"normal": ("NORMAL", {"normal_space": "TANGENT"}),
            "albedo": ("DIFFUSE", {"pass_filter": {"COLOR"}}),
            "roughness": ("ROUGHNESS", {}),
            "emission": ("EMIT", {})}
    for key in maps:
        img, node = images[key]
        nt.nodes.active = node
        btype, kwargs = plan[key]
        print("baking", prefix, key)
        bpy.ops.object.bake(type=btype, **kwargs)
        img.filepath_raw = os.path.join(out_dir, f"{prefix}_{key}.png")
        img.file_format = "PNG"
        img.save()
    if "albedo" in images:
        nt.links.new(images["albedo"][1].outputs["Color"], bsdf.inputs["Base Color"])
    if "roughness" in images:
        nt.links.new(images["roughness"][1].outputs["Color"], bsdf.inputs["Roughness"])
    if "normal" in images:
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(images["normal"][1].outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if "emission" in images:
        nt.links.new(images["emission"][1].outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def setup_render(scene, res=900, samples=32, world=(0.05, 0.055, 0.065)):
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = "GPU"
    except Exception as exc:
        print("GPU setup failed, using CPU:", exc)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    w = bpy.data.worlds.new("World")
    w.color = world
    scene.world = w
    for name, loc, energy, size in (("Key", (1.6, -2.2, 2.4), 260, 1.2), ("Rim", (-1.2, 1.8, 2.0), 220, 1.0), ("Fill", (-2.0, -1.5, 1.0), 70, 2.0)):
        light = bpy.data.lights.new(name, "AREA")
        light.energy = energy
        light.size = size
        o = bpy.data.objects.new(name, light)
        o.location = loc
        o.rotation_euler = (V((0, 0, 0.7)) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(o)


def render_views(scene, out_dir, tag, target, dist, views=(("front", 0), ("three_quarter", 40)), lens=60, height=0.15):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = lens
    cam_data.clip_start = 0.01
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, ang in views:
        a = math.radians(ang)
        cam.location = V(target) + V((math.sin(a) * dist, -math.cos(a) * dist, height))
        cam.rotation_euler = (V(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{tag}_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


def export_glb(objs, path, animations=False):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_animations=animations, export_yup=True)
    print("exported", path)
