"""Hub_vehicle_fuelTruck.usdz — the hero vehicle (docs/HUB_MODEL_LIST.md §2.1).

Rigid three-axle tanker, 9.5 × 2.5 × 3.3 m: white cab-over cab with a big
dark windscreen, a polished-silver elliptical tank (its own un-prefixed
material, so the app leaves it shiny) with three straps and a round yellow
logo (an original mark: a disc with a white drop), dark chassis and skirts,
hose cabinet, rear ladder, six wheels with light hubs.

    blender --background --python scripts/hub-models/procedural/vehicle_fuelTruck.py -- --preview <dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

FRONT, BACK = 4.75, -4.75
TANK_Z, TANK_W, TANK_H = 2.2, 1.2, 1.1  # centre height, half-width, half-height


def wheel(kit, x, y, r=0.5, w=0.36):
    prof = [(-w / 2, 0.0), (-w / 2, r * 0.55), (-w / 2, r * 0.82), (-w * 0.4, r * 0.97), (0, r),
            (w * 0.4, r * 0.97), (w / 2, r * 0.82), (w / 2, r * 0.55), (w / 2, 0.0)]
    slots = ["white", "tyre", "tyre", "tyre", "tyre", "tyre", "tyre", "white"]
    return kit.lathe(prof, slots, center=(x, y, r), axis=(0, 1, 0), n=12)


def tank(kit):
    # Elliptical tank with dished ends.
    stations = [(2.95, 0.0), (2.93, 0.45), (2.85, 0.75), (2.7, 0.92), (2.45, 1.0), (-4.2, 1.0),
                (-4.45, 0.92), (-4.6, 0.75), (-4.68, 0.45), (-4.7, 0.0)]
    rings = [kit.circle((x, 0, TANK_Z), (1, 0, 0), 1.0, 28, scale=(TANK_H * s, TANK_W * s))
             for x, s in stations]
    kit.custom["tank_silver"] = ("#C9D0E4", 0.6, 0.35)
    kit.add(K.Piece().loft(rings, "tank_silver").seal())
    # Three straps.
    for x in (1.7, -0.75, -3.2):
        rings = [kit.circle((x + dx, 0, TANK_Z), (1, 0, 0), 1.0, 20, scale=(TANK_H + 0.035, TANK_W + 0.035))
                 for dx in (0.07, -0.07)]
        kit.add(K.Piece().loft(rings, "darkMetal", cap0="darkMetal", cap1="darkMetal").seal())
    # Round logo on each side, laid on the curved tank: a yellow disc with a
    # white drop.
    def on_tank(x, dz, side, off):
        f = max(0.0, 1 - (dz / TANK_H) ** 2) ** 0.5
        return Vector((x, side * (TANK_W * f + off), TANK_Z + dz))

    def decal(shape, off, slot, side):
        """Concentric rings laid on the tank, so the decal bends with it."""
        rings = [[on_tank(*shape(t, f), side, off) for t in (2 * math.pi * k / 16 for k in range(16))]
                 for f in (0.0, 0.5, 1.0)]
        return K.Piece().loft(rings, slot).seal().face_away_from(lambda c: Vector((c.x, 0, TANK_Z)))

    for side in (1, -1):
        kit.add(decal(lambda t, f: (0.47 + f * 0.42 * math.cos(t), 0.05 + f * 0.42 * math.sin(t)),
                      0.015, "hiVis", side))
        # Teardrop, point up.
        kit.add(decal(lambda t, f: (0.47 + f * 0.24 * math.sin(t) * math.sin(t / 2),
                                    0.0 + f * 0.24 * math.cos(t) + (1 - f) * 0.05), 0.03, "white", side))


def cab(kit):
    kit.add(K.Piece().box((3.95, 0, 2.0), (1.6, 2.45, 2.0), "white", bevel=0.22, segments=3).seal())
    # Windscreen wrapping the front corners, side windows, roof beacon base.
    kit.add(K.Piece().box((4.74, 0, 2.38), (0.06, 2.1, 0.78), "windowDark", bevel=0.025, segments=1).seal())
    for side in (1, -1):
        kit.add(K.Piece().box((4.05, side * 1.224, 2.33), (1.0, 0.04, 0.68), "windowDark", bevel=0.02,
                              segments=1).seal())
    # Bumper with grille and headlights.
    kit.add(K.Piece().box((4.55, 0, 0.8), (0.4, 2.4, 0.5), "white", bevel=0.12, segments=2).seal())
    kit.add(K.Piece().box((4.76, 0, 1.25), (0.05, 1.7, 0.22), "darkMetal", bevel=0.02, segments=1).seal())
    for side in (1, -1):
        kit.add(kit.lathe([(0, 0.0), (0, 0.11), (0.05, 0.11), (0.05, 0.0)], "lamp",
                          center=(4.74, side * 0.92, 1.25), axis=(1, 0, 0), n=12))


def chassis(kit):
    kit.add(K.Piece().box((-0.3, 0, 0.78), (9.0, 1.9, 0.36), "darkMetal", bevel=0.05, segments=1).seal())
    # Saddle under the tank.
    kit.add(K.Piece().box((-0.9, 0, 1.08), (7.1, 1.6, 0.3), "darkMetal", bevel=0.05, segments=1).seal())
    # Side skirts between the axles.
    for side in (1, -1):
        kit.add(K.Piece().box((0.55, side * 1.13, 0.78), (2.9, 0.06, 0.5), "darkMetal", bevel=0.02,
                              segments=1).seal())
    # Hose-reel cabinet behind the cab, with two shutter lines.
    kit.add(K.Piece().box((2.75, 0, 1.75), (0.75, 2.3, 1.55), "white", bevel=0.1, segments=2).seal())
    for side in (1, -1):
        for z in (1.45, 2.05):
            kit.add(K.Piece().box((2.75, side * 1.152, z), (0.6, 0.02, 0.04), "darkMetal").seal())
    # Rear bumper, ladder (two rails, five rungs) and walkway rail on top.
    kit.add(K.Piece().box((-4.6, 0, 0.7), (0.3, 2.3, 0.3), "darkMetal", bevel=0.05, segments=1).seal())
    for y in (0.35, -0.35):
        kit.add(K.Piece().box((-4.78, y, 1.85), (0.06, 0.06, 2.2), "darkMetal").seal())
    for k in range(5):
        kit.add(K.Piece().box((-4.78, 0, 1.0 + k * 0.42), (0.05, 0.7, 0.05), "darkMetal").seal())
    for y in (0.55, -0.55):
        kit.add(K.Piece().box((-1.0, y, 3.32), (6.4, 0.05, 0.05), "darkMetal").seal())
        for x in (2.1, -1.0, -4.1):
            kit.add(K.Piece().box((x, y, 3.2), (0.05, 0.05, 0.25), "darkMetal").seal())


def build(kit):
    for x in (3.55, -1.75, -3.15):
        for y in (1.03, -1.03):
            kit.add(wheel(kit, x, y))
    chassis(kit)
    tank(kit)
    cab(kit)


VIEWS = [
    ("front", (15, 9, 5), (0, 0, 1.6)),
    ("side", (0, 16, 2.5), (0, 0, 1.6)),
    ("back", (-14, -8, 5), (0, 0, 1.6)),
    ("logo", (4.5, 5.5, 3.2), (0.47, 1.2, 2.25)),
]

K.run("vehicle_fuelTruck", build, VIEWS)
