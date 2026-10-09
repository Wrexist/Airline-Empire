"""Turn a generated model (Meshy GLB/FBX/OBJ) into a Hub View USDZ.

Runs inside Blender. Three ways to call it:

    blender --background --python scripts/hub-models/clean_model.py -- \
        --input raw/narrowbody.glb --slot aircraft_narrowbody
    python3.11 scripts/hub-models/clean_model.py --input ... --slot ...   # `pip install bpy`
    # from the Blender MCP: exec this file with sys.argv set the same way

What it does, in order (docs/HUB_MODEL_PIPELINE.md, stage 4):
 1. imports the file into an empty scene and joins every mesh into one;
 2. turns it to face +X (`--yaw`, degrees about the up axis, if the
    generator faced it elsewhere) and applies all transforms;
 3. paints every face with the nearest **allowed palette slot** for this
    model (manifest.json), sampling the generator's texture at the face,
    then smooths the result over neighbouring faces so noise does not
    speckle the slots;
 4. decimates to the triangle budget;
 5. scales uniformly to the real size in manifest.json and puts the pivot
    at the centre of the footprint, on the ground;
 6. drops every texture and splits the mesh into one object per slot,
    named `ae_<slot>`, with a flat matte preview material;
 7. smooth-shades by angle and exports `Hub_<slot>.usdz`, Y-up, metres.

Then run check_usdz.py on the result.
"""
import argparse
import json
import math
import os
import sys
from collections import Counter

import bpy  # must come first: bmesh only exists once bpy is loaded
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--input", required=True,
                   help="GLB, GLTF, FBX or OBJ from the generator, or a hand-fixed .blend to re-export")
    p.add_argument("--slot", required=True, help="manifest key, e.g. aircraft_narrowbody")
    p.add_argument("--out", help="output .usdz (default AirlineEmpireApp/Resources/HubModels/Hub_<slot>.usdz)")
    p.add_argument("--yaw", type=float, default=0.0, help="degrees to turn about up so the front faces +X")
    p.add_argument("--target-tris", type=int, help="override the budget midpoint")
    p.add_argument("--smooth-passes", type=int, default=2, help="neighbour smoothing of slot assignment")
    p.add_argument("--manifest", default=os.path.join(HERE, "manifest.json"))
    p.add_argument("--save-blend", help="also save the cleaned .blend here, for hand fixes")
    return p.parse_args(argv)


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def import_model(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        sys.exit(f"unsupported input {ext}")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        sys.exit("no mesh in the input")
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    # Bake parents (glTF imports put meshes under empties) before joining.
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    for o in list(bpy.context.scene.objects):
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    return obj


class TextureSampler:
    """Base colour of a material at a UV: image texture, else the flat value."""

    def __init__(self, mat):
        self.flat = (0.8, 0.8, 0.8)
        self.pixels = None
        if mat is None:
            return
        if not mat.use_nodes:
            self.flat = tuple(mat.diffuse_color[:3])
            return
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            return
        socket = bsdf.inputs["Base Color"]
        self.flat = tuple(linear_to_srgb(c) for c in socket.default_value[:3])
        img = self._find_image(socket)
        if img is not None and img.size[0] > 0:
            self.w, self.h = img.size
            self.pixels = list(img.pixels[:])  # RGBA floats, in the image's own space (sRGB for colour maps)

    @staticmethod
    def _find_image(socket, depth=0):
        if depth > 6 or not socket.is_linked:
            return None
        node = socket.links[0].from_node
        if node.type == "TEX_IMAGE":
            return node.image
        for inp in node.inputs:
            found = TextureSampler._find_image(inp, depth + 1)
            if found is not None:
                return found
        return None

    def at(self, uv):
        if self.pixels is None or uv is None:
            return self.flat
        x = int((uv[0] % 1.0) * (self.w - 1))
        y = int((uv[1] % 1.0) * (self.h - 1))
        i = (y * self.w + x) * 4
        return tuple(self.pixels[i:i + 3])


def classify(obj, slots, palette, passes):
    """Index of the nearest allowed slot for every face, neighbour-smoothed."""
    targets = [hex_rgb(palette[s]) for s in slots]
    samplers = [TextureSampler(m) for m in obj.data.materials] or [TextureSampler(None)]
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.active
    col = bm.loops.layers.color.active if hasattr(bm.loops.layers, "color") else None
    bm.faces.ensure_lookup_table()

    def nearest(rgb):
        return min(range(len(targets)),
                   key=lambda k: sum((a - b) ** 2 for a, b in zip(rgb, targets[k])))

    label = []
    for f in bm.faces:
        sampler = samplers[min(f.material_index, len(samplers) - 1)]
        if sampler.pixels is not None and uv is not None:
            # Three samples (centroid + two corners pulled inwards) per face.
            uvs = [l[uv].uv for l in f.loops]
            c = sum((Vector(u) for u in uvs), Vector((0, 0))) / len(uvs)
            picks = [c] + [c.lerp(Vector(u), 0.6) for u in uvs[:2]]
            rgb = [sum(ch) / len(picks) for ch in zip(*(sampler.at(p) for p in picks))]
        elif col is not None:
            cs = [l[col] for l in f.loops]
            rgb = [linear_to_srgb(sum(c[i] for c in cs) / len(cs)) for i in range(3)]
        else:
            rgb = sampler.flat
        label.append(nearest(rgb))

    for _ in range(passes):
        nxt = list(label)
        for f in bm.faces:
            votes = Counter([label[f.index]] * 2)
            for e in f.edges:
                for g in e.link_faces:
                    if g is not f:
                        votes[label[g.index]] += 1
            nxt[f.index] = votes.most_common(1)[0][0]
        label = nxt
    bm.free()
    return label


def assign_slots(obj, slots, palette, label):
    obj.data.materials.clear()
    for s in slots:
        mat = bpy.data.materials.new(f"ae_{s}")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*[srgb_to_linear(c) for c in hex_rgb(palette[s])], 1)
        bsdf.inputs["Roughness"].default_value = 0.1 if s == "glass" else 0.85
        bsdf.inputs["Metallic"].default_value = 0.0
        if s == "glass":
            bsdf.inputs["Alpha"].default_value = 0.55
        obj.data.materials.append(mat)
    for poly, k in zip(obj.data.polygons, label):
        poly.material_index = k


def triangles(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def decimate(obj, target):
    tris = triangles(obj)
    if tris <= target:
        return tris
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = target / tris
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return triangles(obj)


def fit_and_pivot(obj, size):
    """Uniform scale to the manifest size; pivot at footprint centre, on the ground.

    Blender is Z-up; the export maps Blender (x, y, z) to USD (x, z, -y), so
    app x (length) = Blender x, app y (height) = Blender z, app z (width) = Blender -y.
    """
    co = [v.co for v in obj.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    ext = hi - lo
    current = {"x": ext.x, "y": ext.z, "z": ext.y}
    # Scale by the most reliable spec dimension: length, else height, else
    # width. check_usdz.py then catches proportions that are off.
    axis = next((k for k in ("x", "y", "z") if size.get(k) and current[k] > 1e-6), None)
    s = size[axis] / current[axis] if axis else 1.0
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    obj.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation(-centre))
    obj.data.update()
    return s


def split_by_slot(obj, slots):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = []
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            continue
        if not o.data.polygons:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        # Blender 5 compacts material slots on separate, so read the slot
        # from the material's name, not from its index.
        used = {p.material_index for p in o.data.polygons}
        slot = o.data.materials[used.pop()].name.removeprefix("ae_").split(".")[0]
        o.name = o.data.name = f"ae_{slot}"
        # Keep only the one material the part uses.
        mat = bpy.data.materials[f"ae_{slot}"]
        o.data.materials.clear()
        o.data.materials.append(mat)
        parts.append(o)
    return parts


def finish(parts, slot):
    root = bpy.data.objects.new(f"Hub_{slot}", None)
    bpy.context.scene.collection.objects.link(root)
    for o in parts:
        o.parent = root
        bpy.context.view_layer.objects.active = o
        for p in bpy.context.scene.objects:
            p.select_set(p is o)
        try:
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
        except (AttributeError, RuntimeError):
            bpy.ops.object.shade_smooth()
    for img in list(bpy.data.images):
        bpy.data.images.remove(img)
    return root


def export(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.wm.usd_export(
        filepath=path, export_materials=True, export_textures_mode="KEEP",
        export_animation=False, export_lights=False, export_cameras=False,
        convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y", convert_scene_units="METERS",
        root_prim_path="", generate_preview_surface=True, export_uvmaps=False)


def main():
    a = args()
    manifest = json.load(open(a.manifest))
    if a.slot not in manifest["models"]:
        sys.exit(f"{a.slot} is not in {a.manifest}")
    spec = manifest["models"][a.slot]
    slots, palette = spec["slots"], manifest["palette"]
    out = a.out or os.path.join(HERE, "..", "..", "AirlineEmpireApp", "Resources", "HubModels", spec["file"])

    if a.input.lower().endswith(".blend"):
        # Hand-fixed file from a previous run: re-check names and export as is.
        bpy.ops.wm.open_mainfile(filepath=os.path.abspath(a.input))
        parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        bad = [o.name for o in parts if not o.name.startswith(("ae_", "cutaway_", "tunnel_", "cab", "bogie"))
               and o.parent is None]
        if bad:
            print(f"warning: unparented meshes outside the slot scheme: {bad}")
        export(out)
        print(f"{a.slot}: re-exported {len(parts)} parts")
        print(f"wrote {os.path.abspath(out)}")
        return

    obj = import_model(a.input)
    if a.yaw:
        obj.matrix_world = Matrix.Rotation(math.radians(a.yaw), 4, "Z") @ obj.matrix_world
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    raw = triangles(obj)

    label = classify(obj, slots, palette, a.smooth_passes)
    assign_slots(obj, slots, palette, label)
    lo, hi = spec["triangles"]
    tris = decimate(obj, a.target_tris or (lo + hi) // 2)
    scale = fit_and_pivot(obj, spec["size_m"])
    parts = split_by_slot(obj, slots)
    finish(parts, a.slot)
    if a.save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.save_blend))
    export(out)
    counts = {o.name: triangles(o) for o in parts}
    print(f"{a.slot}: {raw} -> {tris} triangles, scale x{scale:.3f}, parts {counts}")
    print(f"wrote {os.path.abspath(out)}")


if __name__ == "__main__":
    main()
