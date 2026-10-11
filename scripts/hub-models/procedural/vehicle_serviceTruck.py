"""Hub_vehicle_serviceTruck.usdz — apron box truck (docs/HUB_MODEL_LIST.md §2.4).

6 × 2.2 × 2.6 m: white cab-over cab with a dark windscreen and side
windows, a white box body with a dark roller shutter at the back and a
thin stripe, dark chassis, four wheels with light hubs.

    blender --background --python scripts/hub-models/procedural/vehicle_serviceTruck.py -- --preview <dir>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402


def build(kit):
    for x in (2.05, -1.7):
        for y in (0.88, -0.88):
            kit.add(kit.wheel(x, y, 0.42, 0.34))
    kit.add(K.Piece().box((0.0, 0, 0.66), (5.7, 1.7, 0.32), "darkMetal", bevel=0.05, segments=1).seal())
    # Cab.
    kit.add(K.Piece().box((2.35, 0, 1.45), (1.3, 2.15, 1.75), "white", bevel=0.2, segments=2).seal())
    kit.add(K.Piece().box((2.99, 0, 1.78), (0.04, 1.9, 0.68), "windowDark").seal())
    for y in (1.08, -1.08):
        kit.add(K.Piece().box((2.45, y, 1.75), (0.85, 0.04, 0.6), "windowDark").seal())
    kit.add(K.Piece().box((2.98, 0, 0.82), (0.12, 2.1, 0.32), "darkMetal", bevel=0.04, segments=1).seal())
    # Box body, stripe each side, roller shutter at the back.
    kit.add(K.Piece().box((-0.62, 0, 1.68), (4.5, 2.2, 1.84), "white", bevel=0.12, segments=2).seal())
    for y in (1.11, -1.11):  # thin livery stripe (spec §2.4; the depot paints it)
        kit.add(K.Piece().box((-0.62, y, 1.25), (4.2, 0.02, 0.16), "livery").seal())
    kit.add(K.Piece().box((-2.88, 0, 1.6), (0.04, 1.8, 1.5), "darkMetal").seal())
    for k in range(5):
        kit.add(K.Piece().box((-2.9, 0, 1.0 + k * 0.3), (0.03, 1.8, 0.03), "white").seal())


VIEWS = [
    ("front", (10, 7, 4), (0, 0, 1.3)),
    ("back", (-9, -7, 4), (0, 0, 1.3)),
]

K.run("vehicle_serviceTruck", build, VIEWS)
