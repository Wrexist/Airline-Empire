"""Shared toolkit for Hub View models built from code in Blender.

The alternative to generated models (docs/HUB_MODEL_PIPELINE.md): each
model is a script that builds clean, slot-coloured geometry directly, so it
comes out at real size, facing +X, on budget and split into `ae_<slot>`
prims without any colour matching or decimation.

Coordinates are Blender's: +X forward, +Y left (port), +Z up, metres. The
export maps them to the app's frame (x forward, y up, port side on -z).

A model script defines `build(kit)` and ends with `kit.run("<slot>", build)`;
run it with

    blender --background --python scripts/hub-models/procedural/<slot>.py -- \
        [--out file.usdz] [--save-blend file.blend] [--preview dir]
"""
import argparse
import json
import math
import os
import sys
from collections import defaultdict

import bpy  # must come first: bmesh only exists once bpy is loaded
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import clean_model  # noqa: E402  (export and the slot material scheme)

MANIFEST = json.load(open(os.path.join(TOOLS, "manifest.json")))


class Piece:
    """One closed (or deliberately open) shape, each face tagged with a slot."""

    def __init__(self):
        self.bm = bmesh.new()
        self.tag = self.bm.faces.layers.int.new("slot")
        self.slots = []

    def _slot(self, name):
        if name not in self.slots:
            self.slots.append(name)
        return self.slots.index(name)

    def verts(self, points):
        return [self.bm.verts.new(p) for p in points]

    def face(self, vs, slot):
        f = self.bm.faces.new(vs)
        f[self.tag] = self._slot(slot)
        return f

    def loft(self, rings, slots, cap0=None, cap1=None):
        """Quads between consecutive rings of equal length (closed loops).

        `slots` is one slot for every band, or a list with one per band.
        `cap0`/`cap1` close the first/last ring with a fan in that slot.
        """
        bands = len(rings) - 1
        slots = [slots] * bands if isinstance(slots, str) else slots
        vr = [self.verts(r) for r in rings]
        n = len(rings[0])
        for i in range(bands):
            a, b = vr[i], vr[i + 1]
            for k in range(n):
                k2 = (k + 1) % n
                self.face([a[k], a[k2], b[k2], b[k]], slots[i])
        for ring, slot in ((vr[0], cap0), (vr[-1], cap1)):
            if slot is None:
                continue
            c = sum((v.co for v in ring), Vector()) / n
            if max((v.co - c).length for v in ring) < 1e-5:
                continue  # ring collapsed to a point: already closed
            cv = self.bm.verts.new(c)
            for k in range(n):
                self.face([ring[k], ring[(k + 1) % n], cv], slot)
        return self

    def box(self, center, size, slot, bevel=0.0, segments=2):
        """Box, optionally with rounded (bevelled) edges."""
        c, (sx, sy, sz) = Vector(center), size
        pts = [c + Vector((x * sx / 2, y * sy / 2, z * sz / 2))
               for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        v = self.verts(pts)
        for quad in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]:
            self.face([v[i] for i in quad], slot)
        if bevel > 0:
            edges = [e for e in self.bm.edges if all(x in v for x in e.verts)]
            out = bmesh.ops.bevel(self.bm, geom=edges + v, offset=bevel, segments=segments, profile=0.5,
                                  affect="EDGES", clamp_overlap=True)
            k = self._slot(slot)
            for f in out["faces"]:
                f[self.tag] = k
        return self

    def grid(self, points, slot):
        """Open patch from a 2-D list of points (rows x cols)."""
        vs = [self.verts(row) for row in points]
        for i in range(len(vs) - 1):
            for j in range(len(vs[0]) - 1):
                self.face([vs[i][j], vs[i][j + 1], vs[i + 1][j + 1], vs[i + 1][j]], slot)
        return self

    def fan(self, points, slot):
        """Disc-like decal: triangles from the centre to each edge (cabin windows,
        logos). Never one n-gon: on a curved surface viewers triangulate it badly."""
        ring = self.verts(points)
        c = self.bm.verts.new(sum((Vector(p) for p in points), Vector()) / len(points))
        for k in range(len(ring)):
            self.face([ring[k], ring[(k + 1) % len(ring)], c], slot)
        return self

    def seal(self):
        """Weld coincident vertices (collapsed ring ends) and point every face outwards."""
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        return self

    def face_away_from(self, origin_of):
        """Open patches: flip faces whose normal points towards origin_of(centre)."""
        for f in self.bm.faces:
            f.normal_update()  # new faces carry no normal until asked
            c = f.calc_center_median()
            if f.normal.dot(c - origin_of(c)) < 0:
                f.normal_flip()
        return self

    def bisect(self, co, no):
        geom = list(self.bm.verts) + list(self.bm.edges) + list(self.bm.faces)
        bmesh.ops.bisect_plane(self.bm, geom=geom, dist=1e-5, plane_co=co, plane_no=no)
        return self

    def retag(self, test, slot):
        """Give every face whose centre passes `test` the slot `slot`."""
        k = self._slot(slot)
        for f in self.bm.faces:
            if test(f.calc_center_median()):
                f[self.tag] = k
        return self


class Kit:
    def __init__(self):
        self.parts = defaultdict(lambda: ([], []))  # slot -> (verts, faces)
        # Authored materials the app leaves alone (no ae_ prefix):
        # name -> (hex colour, metallic, roughness).
        self.custom = {}

    def add(self, piece, mirror_y=False):
        """Collect a piece's faces per slot; `mirror_y` adds its starboard twin too."""
        piece.bm.normal_update()
        copies = [False, True] if mirror_y else [False]
        for flip in copies:
            for f in piece.bm.faces:
                verts, faces = self.parts[piece.slots[f[piece.tag]]]
                base = len(verts)
                loop = list(f.verts)
                if flip:
                    loop.reverse()  # mirroring turns the winding inside out
                for v in loop:
                    verts.append((v.co.x, -v.co.y if flip else v.co.y, v.co.z))
                faces.append(tuple(range(base, base + len(loop))))
        piece.bm.free()

    # ---- shapes ---------------------------------------------------------

    @staticmethod
    def circle(center, axis, radius, n, start=None, scale=(1.0, 1.0)):
        """Ring of n points around `axis`; `start` is the direction of point 0."""
        axis = Vector(axis).normalized()
        u = Vector(start) if start else (Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0)))
        u = (u - axis * u.dot(axis)).normalized()
        w = axis.cross(u)
        c = Vector(center)
        return [c + (u * math.cos(t) * scale[0] + w * math.sin(t) * scale[1]) * radius
                for t in (2 * math.pi * k / n for k in range(n))]

    def lathe(self, profile, slots, center=(0, 0, 0), axis=(1, 0, 0), n=16, start=None, cap0=None, cap1=None):
        """Surface of revolution: profile = [(along-axis offset, radius)]."""
        a = Vector(axis).normalized()
        rings = [self.circle(Vector(center) + a * t, a, max(r, 0.0), n, start) for t, r in profile]
        return Piece().loft(rings, slots, cap0, cap1).seal()

    @staticmethod
    def airfoil(n=16, thickness=1.0):
        """Closed symmetric section, (chord fraction 0 = leading edge, half-thickness)."""
        pts = []
        for k in range(n):
            th = 2 * math.pi * k / n
            u = (1 - math.cos(th)) / 2
            yt = 5 * 0.12 * (0.2969 * math.sqrt(u) - 0.126 * u - 0.3516 * u ** 2
                             + 0.2843 * u ** 3 - 0.1036 * u ** 4) / 0.12
            yt = max(yt, 0.02)
            pts.append((u, math.copysign(yt * thickness, math.sin(th)) if k else 0.0))
        return pts

    def surface(self, sections, slots, n=16, cap0=None, cap1=None):
        """Lifting surface lofted through sections.

        Each section is (leading_edge Vector, chord, thickness, normal Vector):
        the chord runs aft (-X), thickness along `normal`.
        """
        rings = []
        for le, chord, thick, normal in sections:
            nrm = Vector(normal).normalized()
            rings.append([Vector(le) + Vector((-u * chord, 0, 0)) + nrm * (t * thick)
                          for u, t in self.airfoil(n)])
        return Piece().loft(rings, slots, cap0, cap1).seal()

    # ---- output ---------------------------------------------------------

    def objects(self, slot_name):
        palette = MANIFEST["palette"]
        allowed = MANIFEST["models"][slot_name]["slots"]
        objs = []
        for slot, (verts, faces) in self.parts.items():
            custom = self.custom.get(slot)
            if custom is None and slot not in allowed:
                sys.exit(f"{slot_name}: slot {slot} is not allowed by manifest.json ({allowed})")
            name = slot if custom else f"ae_{slot}"
            mesh = bpy.data.meshes.new(name)
            mesh.from_pydata(verts, [], faces)
            mesh.validate()
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            bm.to_mesh(mesh)
            bm.free()
            mat = bpy.data.materials.new(name)
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes["Principled BSDF"]
            colour, metallic, rough = custom or (palette[slot], 0.0, 0.1 if slot == "glass" else 0.85)
            rgb = [clean_model.srgb_to_linear(c) for c in clean_model.hex_rgb(colour)]
            bsdf.inputs["Base Color"].default_value = (*rgb, 1)
            bsdf.inputs["Roughness"].default_value = rough
            bsdf.inputs["Metallic"].default_value = metallic
            mat.diffuse_color = (*rgb, 1)  # workbench previews
            mesh.materials.append(mat)
            obj = bpy.data.objects.new(name, mesh)
            bpy.context.scene.collection.objects.link(obj)
            objs.append(obj)
        return objs


def preview(directory, slot, views):
    """Workbench renders from (name, camera location, look-at) views."""
    os.makedirs(directory, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.show_object_outline = False
    scene.render.resolution_x, scene.render.resolution_y = 1400, 900
    world = bpy.data.worlds.new("preview")
    world.color = (0.62, 0.66, 0.8)
    scene.world = world
    ground = bpy.data.meshes.new("ground")
    ground.from_pydata([(-200, -200, -0.01), (200, -200, -0.01), (200, 200, -0.01), (-200, 200, -0.01)], [],
                       [(0, 1, 2, 3)])
    gm = bpy.data.materials.new("ground")
    gm.diffuse_color = (0.39, 0.42, 0.67, 1)
    ground.materials.append(gm)
    g = bpy.data.objects.new("ground", ground)
    scene.collection.objects.link(g)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, loc, target in views:
        cam.location = Vector(loc)
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(directory, f"{slot}-{name}.png")
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(g)
    bpy.data.objects.remove(cam)


def run(slot, build, views=()):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", help="default AirlineEmpireApp/Resources/HubModels/Hub_<slot>.usdz")
    p.add_argument("--save-blend")
    p.add_argument("--preview", help="folder for workbench preview renders")
    a = p.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit = Kit()
    build(kit)
    objs = kit.objects(slot)
    clean_model.finish(objs, slot)
    spec = MANIFEST["models"][slot]
    out = a.out or os.path.join(TOOLS, "..", "..", "AirlineEmpireApp", "Resources", "HubModels", spec["file"])
    if a.save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.save_blend))
    clean_model.export(out)
    counts = {o.name: clean_model.triangles(o) for o in objs}
    lo = Vector((min(min(v.co[i] for v in o.data.vertices) for o in objs) for i in range(3)))
    hi = Vector((max(max(v.co[i] for v in o.data.vertices) for o in objs) for i in range(3)))
    print(f"{slot}: {sum(counts.values())} triangles {counts}")
    print(f"size: length {hi.x - lo.x:.2f}  width {hi.y - lo.y:.2f}  height {hi.z - lo.z:.2f}  "
          f"(x {lo.x:.2f}..{hi.x:.2f}, y {lo.y:.2f}..{hi.y:.2f}, z {lo.z:.2f}..{hi.z:.2f})")
    print(f"wrote {os.path.abspath(out)}")
    if a.preview:
        preview(a.preview, slot, views)
