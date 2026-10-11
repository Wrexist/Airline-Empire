"""Small Hub View props (docs/HUB_MODEL_LIST.md §4.4, §6, §7.5).

  gateSign     dark panel facing the app's +Z (Blender -Y), bottom on the
               ground plane; a white label bar, a blue flight-info strip and
               a white arrow on the left, the right half kept clear for the
               gate number the app writes at x 0.4, z 0.25
  cone         orange cone with a white band, 0.7 m
  tree_round   lollipop tree, ~9 m: egg-shaped canopy on a thin grey trunk
  tree_tall    ~12 m, slimmer canopy
  tree_small   ~6 m, rounder canopy

    blender --background --python scripts/hub-models/procedural/props.py -- --preview <dir>
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


K.run("gateSign", gate_sign, [("front", (2.5, -6, 1.6), (0, 0, 1.1))])
K.run("cone", cone, [("front", (1.6, -1.2, 0.9), (0, 0, 0.35))])
K.run("tree_round", tree(9.0, 2.6, 1.0), [("front", (16, -12, 8), (0, 0, 4.5))])
K.run("tree_tall", tree(12.0, 2.3, 0.6), [("front", (20, -15, 10), (0, 0, 6))])
K.run("tree_small", tree(6.0, 2.0, 1.2), [("front", (11, -8, 5), (0, 0, 3))])
