"""Hub_vehicle_boxTruck.usdz — large rigid lorry (docs/HUB_MODEL_LIST.md §2.8).

8.5 × 2.5 × 3.6 m: a white cab-over cab with a dark windscreen and side
windows, grille, headlights; a plain white box body with rear doors; dark
chassis and side guards; a front axle and a rear tandem.

    blender --background --python scripts/hub-models/procedural/vehicle_boxTruck.py -- --preview <dir>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402


def box(kit, slot, c, s, bevel=0.0, seg=1):
    kit.add(K.Piece().box(c, s, slot, bevel=bevel, segments=seg).seal())


def build(kit):
    for x in (2.75, -2.15, -3.2):
        for y in (1.0, -1.0):
            kit.add(kit.wheel(x, y, 0.5, 0.4, n=10))
    box(kit, "darkMetal", (-0.15, 0, 0.66), (7.9, 1.6, 0.3), 0.04, 1)
    for y in (1.12, -1.12):  # side guards between the axles
        box(kit, "darkMetal", (0.25, y, 0.68), (3.4, 0.06, 0.24), 0.02, 1)
    # Cab.
    box(kit, "white", (3.4, 0, 1.94), (1.7, 2.44, 2.36), 0.22, 2)
    box(kit, "windowDark", (4.26, 0, 2.45), (0.04, 2.1, 0.8))
    for y in (1.225, -1.225):
        box(kit, "windowDark", (3.55, y, 2.4), (0.95, 0.04, 0.7))
    box(kit, "darkMetal", (4.26, 0, 1.25), (0.04, 1.9, 0.42))
    for y in (0.88, -0.88):
        box(kit, "lamp", (4.27, y, 1.0), (0.04, 0.32, 0.14))
    box(kit, "darkMetal", (4.2, 0, 0.72), (0.18, 2.42, 0.26), 0.04, 1)
    # Box body and its rear doors.
    box(kit, "white", (-0.95, 0, 2.24), (6.6, 2.5, 2.72), 0.1, 2)
    box(kit, "darkMetal", (-4.265, 0, 2.24), (0.03, 0.05, 2.4))
    for y in (0.5, -0.5):
        box(kit, "darkMetal", (-4.27, y, 1.7), (0.04, 0.06, 0.5))
    for y in (1.0, -1.0):
        box(kit, "lamp", (-4.27, y, 0.98), (0.04, 0.22, 0.16))


VIEWS = [
    ("front", (13, 9, 5), (0, 0, 1.8)),
    ("back", (-12, -9, 5), (0, 0, 1.8)),
]

K.run("vehicle_boxTruck", build, VIEWS)
