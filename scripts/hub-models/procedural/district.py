"""The district shot's models (docs/HUB_MODEL_LIST.md §7, §2.6–2.7).

  house_villa      two-storey modern villa: white render, a glazed living
                   wing, navy pitched roof over the upper floor, corner
                   window, wood slats, terracotta planter, roof terrace with a
                   glass rail; front (+X) faces the street
  house_villa_b    mirrored massing, more wood
  house_villa_c    flat roofs only
  house_garden     low white boundary wall round the lot, dark gate at +X,
                   rounded hedges
  pool             white coping round an ae_water surface
  vehicle_golfCart white cart with a canopy roof
  vehicle_tankTrailer  small tank trailer (the cart's, and the apron bowser)

Villas are sized to the lot the layout gives them (about 19 × 27 m), as
the app fits them uniformly.

    blender --background --python scripts/hub-models/procedural/district.py -- --preview <dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

GF, UF = 3.4, 3.2  # storey heights


def box(kit, slot, x0, x1, y0, y1, z0, z1, bevel=0.0, seg=1, m=1):
    """Axis box from extents; m = -1 mirrors it across y."""
    if m < 0:
        y0, y1 = -y1, -y0
    kit.add(K.Piece().box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), slot,
                          bevel=bevel, segments=seg).seal())


def fascia(kit, x0, x1, y0, y1, z, m=1, h=0.14, t=0.06):
    """Thin dark trim round a flat roof's edge (not over the roof)."""
    box(kit, "darkMetal", x0 - t, x1 + t, y0 - t, y0, z - h, z, m=m)
    box(kit, "darkMetal", x0 - t, x1 + t, y1, y1 + t, z - h, z, m=m)
    box(kit, "darkMetal", x0 - t, x0, y0, y1, z - h, z, m=m)
    box(kit, "darkMetal", x1, x1 + t, y0, y1, z - h, z, m=m)


def villa(variant):
    def build(kit):
        m = -1 if variant == "b" else 1
        flat = variant == "c"
        # Ground floor: solid white volume at the back.
        box(kit, "building", -9, -1, -12, 12, 0, GF, 0.12, 2, m)
        for y in (-11, -3.5, 4, 11):  # windows on the back face
            box(kit, "windowDark", -9.06, -8.9, y - 1.2, y + 1.2, 0.9, 2.6, m=m)
        # Glazed living wing to the front, flat roof, frames.
        box(kit, "windowDark", -1, 7.9, -1, 10.9, 0.1, GF - 0.2, m=m)
        box(kit, "roof", -1.3, 8.5, -1.5, 11.5, GF - 0.2, GF + 0.15, 0.06, 1, m)
        fascia(kit, -1.3, 8.5, -1.5, 11.5, GF + 0.15, m=m)
        for y in (-0.9, 2.1, 5.0, 8.0, 10.8):
            box(kit, "darkMetal", 7.85, 8.05, y - 0.08, y + 0.08, 0, GF - 0.2, m=m)
        for x in (1.5, 4.5, 7.9):
            box(kit, "darkMetal", x - 0.08, x + 0.08, 10.85, 11.05, 0, GF - 0.2, m=m)
        box(kit, "darkMetal", 7.85, 8.05, -1, 10.9, 0, 0.18, m=m)
        # Entrance, wood slats beside it, terracotta planter.
        box(kit, "darkMetal", -0.98, -0.85, -7.0, -5.6, 0, 2.5, m=m)
        for k in range(8 if variant == "b" else 6):
            y = -11.2 + k * 0.42
            box(kit, "houseWood", -0.95, -0.8, y - 0.09, y + 0.09, 0.1, GF - 0.1, m=m)
        box(kit, "cone", 1.0, 3.2, -10.5, -7.5, 0, 0.8, 0.08, 2, m)
        # Upper floor cantilevered over the wing.
        ux0, ux1, uy0, uy1 = -7.0, 4.0, -11.0, 4.0
        box(kit, "building", ux0, ux1, uy0, uy1, GF, GF + UF, 0.12, 2, m)
        # Corner window (front and side), long band on the front.
        box(kit, "windowDark", ux1 - 0.05, ux1 + 0.06, 0.4, 3.85, GF + 0.4, GF + UF - 0.4, m=m)
        box(kit, "windowDark", 1.2, 3.85, uy1 - 0.05, uy1 + 0.06, GF + 0.4, GF + UF - 0.4, m=m)
        box(kit, "windowDark", ux1 - 0.05, ux1 + 0.06, -8.6, -1.2, GF + 0.9, GF + UF - 0.6, m=m)
        box(kit, "darkMetal", ux1, ux1 + 0.12, -8.7, -1.1, GF + 0.8, GF + 0.9, m=m)
        box(kit, "darkMetal", ux1, ux1 + 0.12, -8.7, -1.1, GF + UF - 0.6, GF + UF - 0.5, m=m)
        # Vertical wood slats on the front's far end (and the whole side for b).
        for k in range(10):
            y = -10.8 + k * 0.2
            box(kit, "houseWood", ux1, ux1 + 0.16, y - 0.06, y + 0.06, GF + 0.15, GF + UF - 0.15, m=m)
        if variant == "b":
            for k in range(18):
                x = ux0 + 0.4 + k * 0.6
                box(kit, "houseWood", x - 0.07, x + 0.07, uy0 - 0.16, uy0, GF + 0.15, GF + UF - 0.15, m=m)
        # Roof terrace over the wing, glass rail.
        box(kit, "glass", 8.2, 8.3, uy1, 11.3, GF + 0.25, GF + 1.25, m=m)
        box(kit, "glass", ux1, 8.3, 11.2, 11.3, GF + 0.25, GF + 1.25, m=m)
        box(kit, "darkMetal", 8.15, 8.35, uy1, 11.35, GF + 1.2, GF + 1.3, m=m)
        box(kit, "darkMetal", ux1, 8.35, 11.15, 11.35, GF + 1.2, GF + 1.3, m=m)
        top = GF + UF
        if flat:
            box(kit, "roof", ux0 - 0.4, ux1 + 0.4, uy0 - 0.4, uy1 + 0.4, top - 0.05, top + 0.25, 0.06, 1, m)
            fascia(kit, ux0 - 0.4, ux1 + 0.4, uy0 - 0.4, uy1 + 0.4, top + 0.25, m=m)
            box(kit, "roof", -9.2, -1, -12.2, 12.2, GF - 0.05, GF + 0.2, 0.06, 1, m)
        else:
            # Navy gable over the upper floor (ridge along y), white gable ends.
            ridge = 8.5
            eave_lo, eave_hi = ux0 - 0.5, ux1 + 0.5
            mid = (ux0 + ux1) / 2
            ring = lambda y: [Vector((eave_lo, y, top - 0.1)), Vector((eave_hi, y, top - 0.1)),  # noqa: E731
                              Vector((mid, y, ridge))]
            ya, yb = (uy0 - 0.5) * m, (uy1 + 0.5) * m
            kit.add(K.Piece().loft([ring(min(ya, yb)), ring(max(ya, yb))], "houseRoof",
                                   cap0="building", cap1="building").seal())
            box(kit, "roof", -9.2, -1, -12.2, 12.2, GF - 0.05, GF + 0.2, 0.06, 1, m)
        fascia(kit, -9.2, -1, -12.2, 12.2, GF + 0.2, m=m)
        for y in (-6.75, -4.9, -3.05):  # mullions in the upstairs band
            box(kit, "darkMetal", ux1, ux1 + 0.1, y - 0.05, y + 0.05, GF + 0.9, GF + UF - 0.6, m=m)
        box(kit, "darkMetal", 1.15, 3.9, uy1, uy1 + 0.1, GF + 0.33, GF + 0.43, m=m)  # sill
    return build


def garden(kit):
    h, t, half = 0.9, 0.3, 20.0
    for y0, y1 in ((-half, -4.0), (-1.0, half)):  # front wall with the gate gap at y -4..-1
        box(kit, "building", half - t, half, y0, y1, 0, h, 0.05)
    box(kit, "building", -half, -half + t, -half, half, 0, h, 0.05)
    box(kit, "building", -half, half, -half, -half + t, 0, h, 0.05)
    box(kit, "building", -half, half, half - t, half, 0, h, 0.05)
    for k in range(7):  # dark gate bars
        y = -3.9 + k * 0.48
        box(kit, "darkMetal", half - 0.2, half - 0.1, y - 0.03, y + 0.03, 0, 1.1)
    box(kit, "darkMetal", half - 0.2, half - 0.1, -4.0, -1.0, 1.0, 1.1)
    # Rounded hedges along the back and one side.
    for cx, cy, lx, ly in ((-17.5, 0, 1.2, 14), (0, 17.5, 12, 1.2), (12, -17.5, 6, 1.1)):
        kit.add(kit.ellipsoid((cx, cy, 0.8), (lx, ly, 0.8), "grassBright", n=12, rings=5))


def pool(kit):
    # The lot's lawn is 0.3 m thick, so the coping stands 0.55 m and the water
    # surface sits at 0.48 m, above it (as the procedural pool does).
    top, water = 0.55, 0.48
    box(kit, "white", -5.5, 5.5, -3.5, -3.0, 0, top, 0.05)
    box(kit, "white", -5.5, 5.5, 3.0, 3.5, 0, top, 0.05)
    box(kit, "white", -5.5, -5.0, -3.0, 3.0, 0, top, 0.05)
    box(kit, "white", 5.0, 5.5, -3.0, 3.0, 0, top, 0.05)
    box(kit, "water", -5.0, 5.0, -3.0, 3.0, 0.05, water)
    for y in (-0.6, 0.6):  # steps rail
        kit.add(kit.limb((4.6, y, water), (4.6, y, water + 0.65), 0.03, 0.03, "darkMetal", n=6))


def golf_cart(kit):
    for x in (0.95, -0.95):
        for y in (0.52, -0.52):
            kit.add(kit.wheel(x, y, 0.27, 0.2, n=12))
    box(kit, "white", -1.45, 1.4, -0.62, 0.62, 0.22, 0.72, 0.12, 2)
    box(kit, "white", 0.7, 1.5, -0.6, 0.6, 0.5, 0.95, 0.15, 2)
    box(kit, "darkMetal", -0.65, 0.25, -0.58, 0.58, 0.72, 0.88, 0.04, 1)
    box(kit, "darkMetal", -0.72, -0.56, -0.58, 0.58, 0.88, 1.4, 0.04, 1)
    box(kit, "darkMetal", -1.45, -0.75, -0.6, 0.6, 0.72, 0.8)
    for x, y in ((0.72, 0.55), (0.72, -0.55), (-1.25, 0.55), (-1.25, -0.55)):
        box(kit, "darkMetal", x - 0.03, x + 0.03, y - 0.03, y + 0.03, 0.72, 1.92)
    box(kit, "white", -1.45, 1.0, -0.66, 0.66, 1.9, 2.0, 0.04, 1)
    box(kit, "windowDark", 0.72, 0.76, -0.52, 0.52, 0.98, 1.82)
    box(kit, "darkMetal", 1.42, 1.5, -0.45, 0.45, 0.32, 0.44)  # bumper


def tank_trailer(kit):
    kit.recentre = True
    for y in (0.62, -0.62):
        kit.add(kit.wheel(-0.3, y, 0.32, 0.2, n=12))
        box(kit, "darkMetal", -0.75, 0.15, y - 0.11, y + 0.11, 0.62, 0.7)  # fender
    box(kit, "darkMetal", -1.4, 0.8, -0.35, 0.35, 0.4, 0.52)
    kit.add(kit.beam((0.8, 0, 0.46), (1.75, 0, 0.42), 0.1, 0.1, "darkMetal"))
    kit.add(kit.lathe([(0, 0.0), (0.05, 0.4), (0.18, 0.55), (1.8, 0.55), (1.93, 0.4), (1.98, 0.0)], "white",
                      center=(0.75, 0, 1.05), axis=(-1, 0, 0), n=16))
    for x in (0.35, -0.85):
        kit.add(kit.lathe([(-0.05, 0.57), (0.05, 0.57)], "darkMetal", center=(x, 0, 1.05), axis=(1, 0, 0), n=16,
                          cap0="darkMetal", cap1="darkMetal"))
    box(kit, "darkMetal", -1.45, -1.25, -0.25, 0.25, 0.55, 1.0, 0.03, 1)  # hose reel box


VILLA_VIEWS = [("front", (34, 26, 18), (0, 0, 3.5)), ("back", (-30, -24, 16), (0, 0, 3.5))]
K.run("house_villa", villa("a"), VILLA_VIEWS)
K.run("house_villa_b", villa("b"), VILLA_VIEWS)
K.run("house_villa_c", villa("c"), VILLA_VIEWS)
K.run("house_garden", garden, [("front", (40, 30, 26), (0, 0, 0))])
K.run("pool", pool, [("front", (10, 9, 7), (0, 0, 0))])
K.run("vehicle_golfCart", golf_cart, [("front", (5, 3.5, 2.6), (0, 0, 0.9))])
K.run("vehicle_tankTrailer", tank_trailer, [("front", (5, 3.5, 2.6), (0, 0, 0.8))])
