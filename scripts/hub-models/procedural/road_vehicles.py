"""Cars, the service pick-up, the apron bus and the baggage train (docs/HUB_MODEL_LIST.md §2).

  vehicle_car_sedan     rounded saloon, body in ae_cloth, dark glasshouse,
                        head and tail light strips in ae_lamp; ~400 triangles
                        because car parks hold hundreds
  vehicle_car_suv       taller, squarer
  vehicle_serviceCar    white pick-up: cab, open bed
  vehicle_bus           12 m apron bus: full-length windows, livery band, doors
  vehicle_baggageTrain  tractor and three dollies of bags

    blender --background --python scripts/hub-models/procedural/road_vehicles.py -- --preview <dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402


def rrect(x, hw, z0, z1, r=0.18, n=3):
    """Rounded-rectangle section at station x: half width hw, from z0 to z1."""
    r = min(r, hw * 0.9, (z1 - z0) * 0.45)
    pts = []
    for cy, cz, a0 in ((hw - r, z1 - r, 0), (-hw + r, z1 - r, 90), (-hw + r, z0 + r, 180), (hw - r, z0 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append(Vector((x, cy + r * math.cos(a), cz + r * math.sin(a))))
    return pts


def loft(kit, slot, stations, r=0.18):
    kit.add(K.Piece().loft([rrect(x, hw, z0, z1, r) for x, hw, z0, z1 in stations], slot, cap0=slot, cap1=slot).seal())


def wheel(kit, x, y, r, w):
    kit.add(kit.lathe([(-w / 2, 0.0), (-w / 2, r), (w / 2, r), (w / 2, 0.0)], ["darkMetal", "tyre", "darkMetal"],
                      center=(x, y, r), axis=(0, 1, 0), n=8))


def car(body, length, height, wheel_r, suv=False):
    def build(kit):
        h = length / 2
        top = height
        belt = 0.88 if not suv else 1.02
        loft(kit, body, [(h, 0.78, 0.36, belt - 0.12), (h - 0.12, 0.88, 0.3, belt), (h - 0.9, 0.9, 0.28, belt + 0.02),
                         (-h + 0.6, 0.9, 0.28, belt + 0.04), (-h + 0.06, 0.82, 0.34, belt - 0.04)])
        wind = 0.95 if not suv else 0.6
        loft(kit, "windowDark", [(h - wind - 0.55, 0.8, belt - 0.02, belt + 0.03), (h - wind - 1.1, 0.76, belt - 0.02, top - 0.06),
                                 (-h + (1.0 if not suv else 0.45), 0.76, belt - 0.02, top - 0.06),
                                 (-h + (0.4 if not suv else 0.2), 0.8, belt - 0.02, belt + (0.08 if not suv else 0.5))],
             r=0.12)
        loft(kit, body, [(h - wind - 1.15, 0.72, top - 0.08, top), (-h + (1.05 if not suv else 0.5), 0.72, top - 0.08, top)],
             r=0.04)
        for y in (0.55, -0.55):
            kit.add(K.Piece().box((h - 0.02, y, belt - 0.22), (0.06, 0.32, 0.09), "lamp").seal())
            kit.add(K.Piece().box((-h + 0.08, y, belt - 0.12), (0.06, 0.3, 0.08), "lamp").seal())
        for x in (h - 0.95, -h + 0.95):
            for y in (0.8, -0.8):
                wheel(kit, x, y, wheel_r, 0.22)
    return build


def service_car(kit):
    h = 2.3
    loft(kit, "white", [(h, 0.8, 0.38, 0.86), (h - 0.15, 0.9, 0.32, 0.98), (-h + 0.1, 0.9, 0.32, 0.98)])
    loft(kit, "windowDark", [(0.95, 0.8, 0.96, 1.0), (0.45, 0.76, 0.96, 1.62), (-0.55, 0.76, 0.96, 1.64),
                             (-0.62, 0.8, 0.96, 1.0)], r=0.1)
    loft(kit, "white", [(0.42, 0.72, 1.6, 1.7), (-0.6, 0.72, 1.6, 1.7)], r=0.04)
    # Open bed: dark floor, white sides and tailgate.
    kit.add(K.Piece().box((-1.45, 0, 1.0), (1.7, 1.66, 0.05), "darkMetal").seal())
    for y in (0.86, -0.86):
        kit.add(K.Piece().box((-1.45, y, 1.18), (1.7, 0.08, 0.38), "white", bevel=0.03, segments=1).seal())
    kit.add(K.Piece().box((-2.27, 0, 1.18), (0.08, 1.8, 0.38), "white", bevel=0.03, segments=1).seal())
    for y in (0.55, -0.55):
        kit.add(K.Piece().box((h - 0.02, y, 0.7), (0.06, 0.3, 0.1), "lamp").seal())
    for x in (1.45, -1.45):
        for y in (0.8, -0.8):
            wheel(kit, x, y, 0.36, 0.24)


def bus(kit):
    kit.add(K.Piece().box((0, 0, 1.68), (12.0, 2.6, 2.66), "white", bevel=0.3, segments=2).seal())
    for y in (1.302, -1.302):
        kit.add(K.Piece().box((-0.1, y, 2.05), (10.4, 0.02, 1.05), "windowDark").seal())
        kit.add(K.Piece().box((0, y * 1.001, 0.95), (11.2, 0.02, 0.28), "livery").seal())
    kit.add(K.Piece().box((6.01, 0, 2.0), (0.04, 2.1, 1.5), "windowDark").seal())
    kit.add(K.Piece().box((-6.01, 0, 2.2), (0.04, 1.9, 0.9), "windowDark").seal())
    for x in (3.6, 0.0, -3.6):  # doors on the kerb side
        kit.add(K.Piece().box((x, -1.31, 1.45), (1.3, 0.02, 2.3), "darkMetal").seal())
    for x in (3.9, -3.7):
        for y in (1.1, -1.1):
            wheel(kit, x, y, 0.5, 0.36)


def baggage_train(kit):
    kit.recentre = True
    # Tractor.
    kit.add(K.Piece().box((4.9, 0, 0.62), (2.2, 1.5, 0.8), "white", bevel=0.15, segments=2).seal())
    kit.add(K.Piece().box((4.5, 0, 1.42), (0.9, 1.3, 0.8), "hiVis", bevel=0.08, segments=1).seal())
    for x in (5.5, 4.3):
        for y in (0.7, -0.7):
            wheel(kit, x, y, 0.32, 0.22)
    # Three dollies with bags and tow bars.
    for k, x in enumerate((2.0, -1.0, -4.0)):
        kit.add(K.Piece().box((x, 0, 0.5), (2.6, 1.5, 0.16), "darkMetal").seal())
        for y in (0.72, -0.72):
            kit.add(K.Piece().box((x, y, 0.95), (2.6, 0.05, 0.05), "darkMetal").seal())
            for dx in (-1.25, 1.25):
                kit.add(K.Piece().box((x + dx, y, 0.75), (0.05, 0.05, 0.45), "darkMetal").seal())
        for j, (bx, by, bz) in enumerate(((-0.75, -0.3, 0.75), (0.2, 0.3, 0.75), (0.85, -0.25, 0.75), (-0.2, 0.0, 1.1))):
            kit.add(K.Piece().box((x + bx, by, bz), (0.6 + 0.1 * (j % 2), 0.45, 0.4), "cloth", bevel=0.05,
                                  segments=1).seal())
        for dx in (0.9, -0.9):
            for y in (0.62, -0.62):
                wheel(kit, x + dx, y, 0.26, 0.16)
        kit.add(kit.beam((x + 1.3, 0, 0.45), (x + 1.7 if k else 3.8, 0, 0.42), 0.08, 0.08, "darkMetal"))


V = lambda d: [("front", (d, d * 0.75, d * 0.5), (0, 0, 0.8))]  # noqa: E731
K.run("vehicle_car_sedan", car("cloth", 4.6, 1.44, 0.33), V(7))
K.run("vehicle_car_suv", car("cloth", 4.8, 1.78, 0.38, suv=True), V(7))
K.run("vehicle_serviceCar", service_car, V(7))
K.run("vehicle_bus", bus, V(15))
K.run("vehicle_baggageTrain", baggage_train, V(14))
