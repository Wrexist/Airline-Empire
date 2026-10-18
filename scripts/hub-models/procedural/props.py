"""Small Hub View props (docs/HUB_MODEL_LIST.md §4.4, §6, §7.5).

  gateSign     dark panel facing the app's +Z (Blender -Y), bottom on the
               ground plane; a white label bar, a blue flight-info strip and
               a white arrow on the left, the right half kept clear for the
               gate number the app writes at x 0.4, z 0.25
  cone         orange cone with a white band, 0.7 m
  tree_round   lollipop tree, ~9 m: egg-shaped canopy on a thin grey trunk
  tree_tall    ~12 m, slimmer canopy
  tree_small   ~6 m, rounder canopy
  barrier_fin  red fin barrier on a white post, 1.2 m, in line along +X
  wheelChock   pair of yellow chocks on a rope
  gpu          ground power unit: white cart, cable coil, tow bar at +X
  apronMast    32 m floodlight mast, four lamps facing +X
  streetLamp   7.5 m pole at -X, flat head reaching +X
  pathLight    0.6 m bollard with a lamp band

    blender --background --python scripts/hub-models/procedural/props.py -- --preview <dir> [--only slot,...]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402


def gate_sign(kit):
    front = -0.16  # Blender -Y is the app's +Z, where the number goes
    kit.add(K.Piece().box((0, 0, 1.1), (3.0, 0.3, 2.2), "darkMetal", bevel=0.08, segments=2).seal())
    # Mounting rails on the back (and they keep the footprint centred on the decals).
    for z in (0.5, 1.7):
        kit.add(kit.beam((-1.2, 0.17, z), (1.2, 0.17, z), 0.04, 0.08, "darkMetal", side=(0, 1, 0)))
    for a, b in [((-1.42, front, 0.08), (1.42, front, 0.08)), ((-1.42, front, 2.12), (1.42, front, 2.12)),
                 ((-1.42, front, 0.08), (-1.42, front, 2.12)), ((1.42, front, 0.08), (1.42, front, 2.12))]:
        kit.add(kit.beam(a, b, 0.05, 0.02, "white", side=(0, 1, 0)))
    kit.add(K.Piece().box((-0.55, front, 1.85), (1.5, 0.02, 0.18), "white").seal())
    kit.add(K.Piece().box((0.0, front, 1.38), (2.6, 0.02, 0.32), "screen").seal())
    # Arrow pointing left, in the bottom-left corner.
    kit.add(K.Piece().box((-0.62, front, 0.45), (0.6, 0.02, 0.14), "white").seal())
    head = [Vector((-1.25, front - 0.012, 0.45)), Vector((-0.9, front - 0.012, 0.72)),
            Vector((-0.9, front - 0.012, 0.18))]
    kit.add(K.Piece().fan(head, "white").face_away_from(lambda c: Vector((c.x, 0, c.z))))


def cone(kit):
    kit.add(K.Piece().box((0, 0, 0.02), (0.44, 0.44, 0.04), "cone", bevel=0.015, segments=1).seal())
    kit.add(kit.lathe([(0.04, 0.0), (0.04, 0.17), (0.3, 0.125), (0.44, 0.1), (0.66, 0.045), (0.7, 0.0)],
                      ["cone", "cone", "cone", "cone", "cone"], center=(0, 0, 0), axis=(0, 0, 1), n=12))
    kit.add(kit.lathe([(0.3, 0.128), (0.42, 0.105)], "white", center=(0, 0, 0), axis=(0, 0, 1), n=12))


def tree(height, width, egg):
    def build(kit):
        trunk_top = height * 0.42
        kit.add(kit.lathe([(0, 0.0), (0, 0.16 * width), (trunk_top, 0.1 * width), (trunk_top, 0.0)], "trunk",
                          center=(0, 0, 0), axis=(0, 0, 1), n=8))
        # Egg-shaped canopy, a little fuller below the middle, with soft lumps.
        cz = height * 0.66
        rz = height - cz
        rings = []
        for i in range(10):
            a = math.pi * i / 9
            z = cz - rz * math.cos(a) * (0.92 if i < 5 else 1.0)
            rr = math.sin(a) * width * (1 + egg * math.sin(a) * (0.12 if i < 5 else -0.05))
            rings.append([Vector((rr * (1 + 0.05 * math.sin(3 * t + i)) * math.cos(t),
                                  rr * (1 + 0.05 * math.sin(3 * t + i)) * math.sin(t), z))
                          for t in (2 * math.pi * k / 14 for k in range(14))])
        kit.add(K.Piece().loft(rings, "tree").seal())
        kit.smooth = 80
    return build


def box(kit, slot, c, s, bevel=0.0, seg=1):
    kit.add(K.Piece().box(c, s, slot, bevel=bevel, segments=seg).seal())


def prism(kit, slot, outline, y0, y1):
    """A flat shape in the x-z plane (`outline`, anticlockwise from +Y), extruded from y0 to y1."""
    rings = [[Vector((x, y, z)) for x, z in outline] for y in (y0, y1)]
    kit.add(K.Piece().loft(rings, slot, cap0=slot, cap1=slot).seal())


def barrier_fin(kit):
    """Crowd-control fin: a slanted panel (ae_cloth, painted red by the app)
    on a white post with a weighted base, in line along +X."""
    kit.recentre = True
    kit.add(kit.lathe([(0, 0.0), (0, 0.2), (0.03, 0.19), (0.05, 0.05), (0.05, 0.0)], "darkMetal",
                      center=(0, 0, 0), axis=(0, 0, 1), n=8))
    kit.add(kit.lathe([(0.05, 0.0), (0.05, 0.035), (1.17, 0.035), (1.2, 0.0)], "white",
                      center=(0, 0, 0), axis=(0, 0, 1), n=6))
    prism(kit, "cloth", [(0.03, 0.3), (0.52, 0.56), (0.36, 1.1), (0.03, 1.17)], -0.016, 0.016)


def wheel_chock(kit):
    """A pair of yellow wedge chocks on a rope, lying side by side."""
    wedge = [(-0.13, 0.0), (0.13, 0.0), (0.05, 0.15), (-0.05, 0.15)]
    for x in (0.32, -0.32):
        prism(kit, "hiVis", [(x + a, b) for a, b in wedge], -0.17, 0.17)
    kit.add(kit.beam((-0.2, 0.12, 0.05), (0.2, 0.12, 0.05), 0.025, 0.025, "darkMetal"))


def torus(kit, slot, center, radius, tube, axis_y=True, n=12, m=6):
    """Ring of tube, axis along Y (a cable coil hanging on a side)."""
    c = Vector(center)
    rings = []
    for k in range(n + 1):
        t = 2 * math.pi * k / n
        d = Vector((math.cos(t), 0, math.sin(t)))
        tangent = Vector((-math.sin(t), 0, math.cos(t)))
        rings.append(kit.circle(c + d * radius, tangent, tube, m, start=d))
    kit.add(K.Piece().loft(rings, slot).seal())


def gpu(kit):
    """Ground power unit: small white cart, cable coil on its side, tow bar at +X."""
    kit.recentre = True
    for x in (0.72, -0.72):
        for y in (0.6, -0.6):
            kit.add(kit.lathe([(-0.07, 0.0), (-0.07, 0.21), (0.07, 0.21), (0.07, 0.0)],
                              ["darkMetal", "tyre", "darkMetal"], center=(x, y, 0.21), axis=(0, 1, 0), n=10))
    box(kit, "darkMetal", (0, 0, 0.32), (2.2, 1.0, 0.14))
    box(kit, "white", (-0.05, 0, 0.88), (2.1, 1.32, 1.12), 0.14, 2)
    for y in (0.665, -0.665):
        box(kit, "hiVis", (-0.05, y, 0.6), (1.9, 0.02, 0.1))
    box(kit, "darkMetal", (0.6, -0.668, 1.05), (0.6, 0.02, 0.5))
    box(kit, "screen", (0.6, -0.676, 1.12), (0.4, 0.01, 0.2))
    for k in range(4):  # vents on the roof
        box(kit, "darkMetal", (-0.7 + k * 0.22, 0, 1.445), (0.1, 0.9, 0.02))
    torus(kit, "darkMetal", (-0.45, -0.72, 0.95), 0.26, 0.05)
    kit.add(kit.beam((-0.45, -0.7, 1.2), (-0.45, -0.68, 1.4), 0.06, 0.06, "darkMetal"))
    kit.add(kit.beam((1.0, 0, 0.32), (1.5, 0, 0.3), 0.08, 0.08, "darkMetal"))
    kit.add(kit.lathe([(0, 0.0), (0, 0.09), (0.04, 0.09), (0.04, 0.0)], "darkMetal", center=(1.52, 0, 0.28),
                      axis=(0, 0, 1), n=8))


def apron_mast(kit):
    """32 m floodlight mast (the layout's height): concrete footing, tapered
    pole, a head frame with four lamps tilted down towards +X."""
    box(kit, "concrete", (0, 0, 0.25), (2.0, 2.0, 0.5), 0.08, 1)
    kit.add(kit.lathe([(0.5, 0.0), (0.5, 0.42), (30.6, 0.26), (30.7, 0.0)], "darkMetal", center=(0, 0, 0),
                      axis=(0, 0, 1), n=8))
    kit.add(kit.lathe([(0, 0.0), (0, 0.95), (0.12, 0.95), (0.12, 0.0)], "darkMetal", center=(0, 0, 29.6),
                      axis=(0, 0, 1), n=10))
    for z in (30.7, 31.95):
        kit.add(kit.beam((0, 2.75, z), (0, -2.75, z), 0.22, 0.2, "darkMetal"))
    for y in (2.65, -2.65):
        kit.add(kit.beam((0, y, 30.6), (0, y, 32.05), 0.16, 0.16, "darkMetal"))
    a = math.radians(-25)  # lamps tilted down towards the apron
    for y in (-1.95, -0.65, 0.65, 1.95):
        for slot, cx, sx in (("darkMetal", 0.0, 0.5), ("lamp", 0.27, 0.04)):
            pc = K.Piece().box((cx, 0, 0), (sx, 1.08 if slot == "darkMetal" else 0.92, 0.82 if slot == "darkMetal" else 0.66), slot,
                               bevel=0.04 if slot == "darkMetal" else 0.0, segments=1)
            for v in pc.bm.verts:
                x, z = v.co.x, v.co.z
                v.co.x, v.co.z = x * math.cos(a) - z * math.sin(a), x * math.sin(a) + z * math.cos(a)
                v.co += Vector((0.3, y, 31.32))
            kit.add(pc.seal())


def street_lamp(kit):
    """7.5 m pole (base 0.2 m in radius) at the -X end; an arm and a flat head
    reaching +X over the road, the lamp face (ae_lamp) underneath."""
    kit.recentre = True
    kit.add(kit.lathe([(0, 0.0), (0, 0.2), (0.12, 0.17), (0.5, 0.1), (7.42, 0.075), (7.5, 0.0)], "darkMetal",
                      center=(0, 0, 0), axis=(0, 0, 1), n=6))
    kit.add(kit.beam((0, 0, 7.32), (1.45, 0, 7.48), 0.08, 0.08, "darkMetal"))
    box(kit, "darkMetal", (1.7, 0, 7.52), (0.9, 0.38, 0.14), 0.04, 1)
    box(kit, "lamp", (1.72, 0, 7.44), (0.78, 0.3, 0.03))


def path_light(kit):
    """0.6 m bollard with a glowing band under its cap."""
    kit.add(kit.lathe([(0, 0.0), (0, 0.095), (0.04, 0.065), (0.47, 0.065), (0.47, 0.0)], "darkMetal",
                      center=(0, 0, 0), axis=(0, 0, 1), n=6))
    kit.add(kit.lathe([(0.47, 0.0), (0.47, 0.06), (0.55, 0.06), (0.55, 0.0)], "lamp",
                      center=(0, 0, 0), axis=(0, 0, 1), n=6))
    kit.add(kit.lathe([(0.55, 0.0), (0.55, 0.085), (0.6, 0.06), (0.6, 0.0)], "darkMetal",
                      center=(0, 0, 0), axis=(0, 0, 1), n=6))


K.run("gateSign", gate_sign, [("front", (2.5, -6, 1.6), (0, 0, 1.1))])
K.run("cone", cone, [("front", (1.6, -1.2, 0.9), (0, 0, 0.35))])
K.run("tree_round", tree(9.0, 2.6, 1.0), [("front", (16, -12, 8), (0, 0, 4.5))])
K.run("tree_tall", tree(12.0, 2.3, 0.6), [("front", (20, -15, 10), (0, 0, 6))])
K.run("tree_small", tree(6.0, 2.0, 1.2), [("front", (11, -8, 5), (0, 0, 3))])
K.run("barrier_fin", barrier_fin, [("front", (2.2, -2.0, 1.4), (0.2, 0, 0.6))])
K.run("wheelChock", wheel_chock, [("front", (1.4, -1.2, 0.9), (0, 0, 0.08))])
K.run("gpu", gpu, [("front", (5, -4, 2.5), (0, 0, 0.8)), ("back", (-5, 4, 2.5), (0, 0, 0.8))])
K.run("apronMast", apron_mast, [("front", (40, -30, 20), (0, 0, 16)), ("head", (9, -6, 33), (0, 0, 31.2))])
K.run("streetLamp", street_lamp, [("front", (6, -8, 5), (0, 0, 4))])
K.run("pathLight", path_light, [("front", (1.4, -1.2, 0.9), (0, 0, 0.3))])
