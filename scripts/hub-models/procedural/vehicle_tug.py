"""Hub_vehicle_tug.usdz — pushback tractor (docs/HUB_MODEL_LIST.md §2.3).

White, low and wide, 5 × 2.6 × 1.7 m: a rounded slab body on four big
wheels, a small cab offset to the left at the back with dark windows, a
yellow beacon, dark bumpers and a tow bar at the front.

    blender --background --python scripts/hub-models/procedural/vehicle_tug.py -- --preview <dir>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402


def build(kit):
    for x in (1.55, -1.55):
        for y in (1.05, -1.05):
            kit.add(kit.wheel(x, y, 0.46, 0.42))
    # Body: a low rounded slab with wheel-arch cut-outs suggested by a dark skirt.
    kit.add(K.Piece().box((0, 0, 0.72), (4.7, 2.1, 0.76), "white", bevel=0.24, segments=3).seal())
    kit.add(K.Piece().box((0, 0, 0.42), (4.5, 1.7, 0.22), "darkMetal", bevel=0.04, segments=1).seal())
    # Bumpers, grille, tow hitch and bar.
    for x in (2.42, -2.42):
        kit.add(K.Piece().box((x, 0, 0.55), (0.2, 2.3, 0.32), "darkMetal", bevel=0.06, segments=1).seal())
    kit.add(K.Piece().box((2.36, 0, 0.88), (0.04, 1.3, 0.16), "darkMetal").seal())
    kit.add(kit.beam((2.4, 0, 0.5), (2.62, 0, 0.5), 0.28, 0.2, "darkMetal"))
    # Cab: offset left at the back, glazed all round, beacon on the roof.
    cx, cy = -1.25, 0.45
    kit.add(K.Piece().box((cx, cy, 1.28), (1.3, 1.2, 0.5), "white", bevel=0.1, segments=2).seal())
    kit.add(K.Piece().box((cx, cy, 1.52), (1.24, 1.14, 0.06), "white", bevel=0.02, segments=1).seal())
    for dx, dy, sx, sy in [(0.62, 0, 0.04, 0.98), (-0.62, 0, 0.04, 0.98), (0, 0.59, 1.08, 0.04), (0, -0.59, 1.08, 0.04)]:
        kit.add(K.Piece().box((cx + dx, cy + dy, 1.32), (sx, sy, 0.3), "windowDark").seal())
    kit.add(K.Piece().box((cx, cy, 1.6), (1.36, 1.26, 0.1), "white", bevel=0.04, segments=1).seal())
    kit.add(kit.lathe([(0, 0.0), (0, 0.1), (0.12, 0.1), (0.16, 0.06), (0.16, 0.0)], "hiVis",
                      center=(cx, cy, 1.65), axis=(0, 0, 1), n=10))


VIEWS = [
    ("front", (9, 6, 4), (0, 0, 0.8)),
    ("back", (-8, -6, 4), (0, 0, 0.8)),
]

K.run("vehicle_tug", build, VIEWS)
