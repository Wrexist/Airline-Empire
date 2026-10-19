"""Airside and landside buildings (docs/HUB_MODEL_LIST.md §4.5, §4.7–4.8, §7.2–7.3).

Each is sized to the plot the layout gives it, since the app fits them
uniformly (see the manifest notes); the main face is +X.

  hangar             barrel-vault roof rolling down over a dark panelled
                     door, white walls with louvre bands
  cargoShed          long white shed, loading doors under a canopy
  fuelTank           white tank with a domed roof and dark bands in a bund wall
  controlTower       tapered white shaft, glazed cab, roof, antenna
  office_low         two storeys, long dark window bands, plant on the roof
  midrise_apartment  five storeys, recessed balconies with glass rails
  terminal_pavilion  pier head: white block, glazed entrances, ribbon window
  guardhouse         security booth, boom barrier, sliding gate section

    blender --background --python scripts/hub-models/procedural/buildings.py -- --preview <dir> [--only slot,...]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402


def box(kit, slot, x0, x1, y0, y1, z0, z1, bevel=0.0, seg=1):
    kit.add(K.Piece().box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), slot,
                          bevel=bevel, segments=seg).seal())


def hangar(kit):
    L, W, EAVE, CROWN = 40.0, 40.0, 14.0, 25.0
    # Walls and louvre bands.
    for side in (1, -1):
        box(kit, "building", -L, L - 1.0, side * W - 0.4, side * W + 0.4, 0, EAVE, 0.2, 2)
        for k in range(6):
            z = 8.6 + k * 0.6
            box(kit, "buildingShade", -L + 2, L - 3, side * (W + 0.42), side * (W + 0.5), z, z + 0.3)
    box(kit, "building", -L - 0.4, -L + 0.4, -W, W, 0, EAVE, 0.2, 2)
    # Vault: an arched shell from back to front, its front edge rolling down.
    arcs = []
    for x, drop in ((-L - 0.6, 0.0), (L - 3.0, 0.0), (L - 1.2, 1.4), (L + 0.2, 3.6)):
        outer = [Vector((x, (W + 0.6) * math.cos(t), EAVE + (CROWN - EAVE - drop) * math.sin(t)))
                 for t in (math.pi * i / 16 for i in range(17))]
        inner = [Vector((x, (W - 0.2) * math.cos(t), EAVE - 0.6 + (CROWN - EAVE - drop - 0.2) * math.sin(t)))
                 for t in (math.pi * i / 16 for i in range(16, -1, -1))]
        arcs.append(outer + inner)
    kit.add(K.Piece().loft(arcs, "roof", cap0="roof", cap1="roof").seal())
    # Gable fills over the door and at the back.
    for x in (L - 1.0, -L):
        pts = [Vector((x, (W - 0.3) * math.cos(t), EAVE + (CROWN - EAVE - (3.6 if x > 0 else 0) - 0.8) * math.sin(t)))
               for t in (math.pi * i / 16 for i in range(17))]
        kit.add(K.Piece().fan(pts, "building").face_away_from(lambda c: Vector((0, 0, c.z))))
    # The door: dark panels with light mullions, a strip of panes above.
    box(kit, "darkMetal", L - 1.2, L - 0.8, -W + 1.5, W - 1.5, 0, EAVE - 1.6)
    for k in range(13):
        y = -W + 1.5 + k * (2 * W - 3) / 12
        box(kit, "buildingShade", L - 0.85, L - 0.6, y - 0.25, y + 0.25, 0, EAVE - 1.6)
    box(kit, "buildingShade", L - 0.95, L - 0.7, -W + 1.5, W - 1.5, EAVE - 1.5, EAVE - 0.3)
    for k in range(17):
        y = -W + 1.5 + k * (2 * W - 3) / 16
        box(kit, "darkMetal", L - 0.75, L - 0.6, y - 0.08, y + 0.08, EAVE - 1.5, EAVE - 0.3)
    box(kit, "darkMetal", L - 0.9, L - 0.6, -3, 3, EAVE + 3.0, EAVE + 4.4)  # name plate


def cargo_shed(kit):
    D, W, H = 24.0, 45.0, 12.0
    box(kit, "building", -D, D, -W, W, 0, H, 0.2, 2)
    box(kit, "roof", -D - 0.5, D + 0.5, -W - 0.5, W + 0.5, H, H + 0.6, 0.1, 1)
    for x0, x1, y0, y1 in ((-D - 0.6, D + 0.6, -W - 0.6, -W - 0.5), (-D - 0.6, D + 0.6, W + 0.5, W + 0.6),
                           (-D - 0.6, -D - 0.5, -W - 0.5, W + 0.5), (D + 0.5, D + 0.6, -W - 0.5, W + 0.5)):
        box(kit, "darkMetal", x0, x1, y0, y1, H + 0.3, H + 0.6)  # roof edge trim
    for k in range(8):
        y = -W + 6 + k * (2 * W - 12) / 7
        box(kit, "darkMetal", D, D + 0.12, y - 2.4, y + 2.4, 0.9, 5.4)
        box(kit, "buildingShade", D, D + 0.6, y - 2.8, y + 2.8, 0, 0.9)  # dock leveller
    box(kit, "buildingShade", D, D + 3.0, -W + 1, W - 1, 6.0, 6.4, 0.08, 1)  # canopy
    box(kit, "windowDark", D, D + 0.1, -W + 2, W - 2, 8.2, 10.0)
    # Cladding ribs every 3 m on the long sides and the back.
    for k in range(16):
        x = -D + 1.5 + k * 3.0
        for side in (1, -1):
            box(kit, "buildingShade", x - 0.12, x + 0.12, side * W - 0.12, side * W + 0.12, 0.3, H - 0.2)
    for k in range(29):
        y = -W + 1.5 + k * 3.0
        box(kit, "buildingShade", -D - 0.12, -D + 0.12, y - 0.12, y + 0.12, 0.3, H - 0.2)
    for y in (-30, -10, 10, 30):
        box(kit, "darkMetal", -8, -4, y - 2, y + 2, H + 0.6, H + 1.6, 0.1, 1)  # roof plant


def fuel_tank(kit):
    R, H = 11.5, 11.0
    prof = [(0, 0.0), (0, R), (H, R), (H + 1.4, R * 0.75), (H + 2.2, R * 0.35), (H + 2.4, 0.0)]
    kit.add(kit.lathe(prof, "white", center=(0, 0, 0), axis=(0, 0, 1), n=32))
    for z in (3.5, 7.5):
        kit.add(kit.lathe([(z, R + 0.08), (z + 0.35, R + 0.08)], "darkMetal", center=(0, 0, 0), axis=(0, 0, 1),
                          n=32, cap0="darkMetal", cap1="darkMetal"))
    # Bund wall round it and a stair up the side.
    ring_o = [Vector((13 * math.cos(t), 13 * math.sin(t), 0)) for t in (2 * math.pi * k / 32 for k in range(32))]
    ring_i = [Vector((12.4 * math.cos(t), 12.4 * math.sin(t), 0)) for t in (2 * math.pi * k / 32 for k in range(32))]
    rings = [ring_i, ring_o, [v + Vector((0, 0, 0.8)) for v in ring_o], [v + Vector((0, 0, 0.8)) for v in ring_i], ring_i]
    kit.add(K.Piece().loft(rings, "building").seal())
    steps = [Vector(((R + 0.5) * math.cos(a), (R + 0.5) * math.sin(a), z)) for a, z in
             ((math.radians(-60 + 12 * k), 0.4 + k * 1.15) for k in range(10))]
    for a, b in zip(steps, steps[1:]):
        kit.add(kit.beam(a, b, 0.5, 0.06, "darkMetal", side=(0, 0, 1)))


def control_tower(kit):
    # Podium, tapered shaft, cab underslab, outward-leaning glazed cab, roof, cap, antenna.
    box(kit, "building", -8, 8, -8, 8, 0, 5, 0.3, 2)
    kit.add(kit.lathe([(5, 3.4), (46, 2.6), (46, 0.0)], "building", center=(0, 0, 0), axis=(0, 0, 1), n=20,
                      cap0="building"))
    kit.add(kit.lathe([(46, 2.6), (47.4, 5.6), (48.6, 6.4), (48.6, 0.0)], "buildingShade", center=(0, 0, 0),
                      axis=(0, 0, 1), n=20))
    kit.add(kit.lathe([(48.6, 0.0), (48.6, 6.3), (53.6, 7.0), (53.6, 0.0)], "glass", center=(0, 0, 0), axis=(0, 0, 1),
                      n=20))
    for k in range(12):
        t = 2 * math.pi * k / 12
        kit.add(kit.beam((6.35 * math.cos(t), 6.35 * math.sin(t), 48.6), (7.05 * math.cos(t), 7.05 * math.sin(t), 53.6),
                         0.18, 0.18, "darkMetal", side=(0, 0, 1)))
    kit.add(kit.lathe([(53.6, 0.0), (53.6, 7.6), (54.5, 7.6), (54.9, 5.2), (55.8, 4.6), (55.8, 0.0)], "roof",
                      center=(0, 0, 0), axis=(0, 0, 1), n=20))
    kit.add(kit.lathe([(55.8, 0.18), (59.4, 0.08), (59.4, 0.0)], "darkMetal", center=(0, 0, 0), axis=(0, 0, 1), n=6,
                      cap0="darkMetal"))
    kit.add(kit.ellipsoid((0, 0, 59.6), (0.3, 0.3, 0.3), "lamp", n=8, rings=4))


def office_low(kit):
    D, W, H = 24.0, 27.0, 8.0
    box(kit, "building", -D, D, -W, W, 0, H, 0.25, 2)
    box(kit, "roof", -D - 0.6, D + 0.6, -W - 0.6, W + 0.6, H, H + 0.4, 0.1, 1)
    for z0, z1 in ((1.0, 2.9), (5.0, 6.9)):
        box(kit, "windowDark", D, D + 0.08, -W + 1.5, W - 1.5, z0, z1)
        box(kit, "windowDark", -D - 0.08, -D, -W + 1.5, W - 1.5, z0, z1)
        box(kit, "windowDark", -D + 1.5, D - 1.5, W, W + 0.08, z0, z1)
        box(kit, "windowDark", -D + 1.5, D - 1.5, -W - 0.08, -W, z0, z1)
    # Fins between the panes of both bands, all round.
    for z0, z1 in ((1.0, 2.9), (5.0, 6.9)):
        for k in range(17):
            y = -W + 1.5 + k * (2 * W - 3) / 16
            box(kit, "building", D, D + 0.25, y - 0.12, y + 0.12, z0, z1)
            box(kit, "building", -D - 0.25, -D, y - 0.12, y + 0.12, z0, z1)
        for k in range(15):
            x = -D + 1.5 + k * (2 * D - 3) / 14
            box(kit, "building", x - 0.12, x + 0.12, W, W + 0.25, z0, z1)
            box(kit, "building", x - 0.12, x + 0.12, -W - 0.25, -W, z0, z1)
    box(kit, "roof", D, D + 4, -5, 5, 3.6, 4.0, 0.08, 1)  # entrance canopy
    for x, y in ((-12, -12), (-12, 10), (6, -4)):
        box(kit, "roof", x - 3, x + 3, y - 2.5, y + 2.5, H + 0.4, H + 2.0, 0.15, 1)


def midrise(kit):
    D, W, F, N = 22.0, 28.0, 4.2, 5
    H = F * N
    box(kit, "building", -D, D, -W, W, 0, H, 0.25, 2)
    box(kit, "roof", -D - 0.4, D + 0.4, -W - 0.4, W + 0.4, H, H + 0.5, 0.1, 1)
    bays = 8
    for f in range(N):
        z = f * F
        for b in range(bays):
            y = -W + (b + 0.5) * (2 * W) / bays
            # Street front: recessed balcony — dark glazing set back, a slab and a glass rail.
            box(kit, "windowDark", D - 1.6, D - 1.5, y - 2.4, y + 2.4, z + 0.9, z + 3.6)
            box(kit, "buildingShade", D - 1.6, D + 0.3, y - 2.9, y + 2.9, z + 0.6, z + 0.9)
            box(kit, "glass", D + 0.2, D + 0.3, y - 2.8, y + 2.8, z + 0.9, z + 1.9)
            box(kit, "windowDark", -D - 0.08, -D, y - 2.0, y + 2.0, z + 1.0, z + 3.3)
        for b in range(5):
            x = -D + (b + 0.5) * (2 * D) / 5
            for side in (1, -1):
                box(kit, "windowDark", x - 1.6, x + 1.6, side * W - 0.04, side * W + 0.04, z + 1.0, z + 3.3)
    # Recess the balconies into the block: carve by covering the front with column fins.
    for b in range(bays + 1):
        y = -W + b * (2 * W) / bays
        box(kit, "building", D - 1.6, D + 0.35, y - 0.15, y + 0.15, 0.6, H)


def pavilion(kit):
    """Pier head where a pier meets the terminal: a white flat-roofed block
    22 m along the pier (+X runs along it) and 28 m across, so it caps the
    26 m pier, and taller than the fitted glass vault (16 m) whose open end
    butts into it. Glazed entrances on the long sides (the stands), a dark
    ribbon window wrapping round, parapet and rooftop plant boxes."""
    X, Y = 11.0, 14.0
    box(kit, "buildingShade", -X - 0.2, X + 0.2, -Y - 0.2, Y + 0.2, 0, 0.9, 0.12, 1)
    box(kit, "building", -X, X, -Y, Y, 0.9, 8.2, 0.25, 1)
    for side in (1, -1):
        # Glazed entrance band on each long side, white mullions and transom.
        box(kit, "glass", -7.6, 7.6, side * (Y - 0.1), side * (Y + 0.06), 1.2, 6.8)
        for k in range(9):
            x = -7.6 + k * 1.9
            box(kit, "white", x - 0.12, x + 0.12, side * (Y - 0.1), side * (Y + 0.14), 1.2, 6.8)
        box(kit, "white", -7.8, 7.8, side * (Y - 0.1), side * (Y + 0.18), 6.8, 7.2)
    # Ribbon window, recessed, with white fins every 2.4 m.
    box(kit, "windowDark", -X + 0.25, X - 0.25, -Y + 0.25, Y - 0.25, 8.2, 11.0)
    for side in (1, -1):
        for k in range(11):
            y = -Y + 1.6 + k * (2 * Y - 3.2) / 10
            box(kit, "white", side * (X - 0.3), side * X, y - 0.09, y + 0.09, 8.2, 11.0)
        for k in range(8):
            x = -X + 1.6 + k * (2 * X - 3.2) / 7
            box(kit, "white", x - 0.09, x + 0.09, side * (Y - 0.3), side * Y, 8.2, 11.0)
    box(kit, "building", -X, X, -Y, Y, 11.0, 16.2, 0.25, 1)
    # Roof, parapet coping, plant boxes with louvres.
    box(kit, "roof", -X + 0.35, X - 0.35, -Y + 0.35, Y - 0.35, 16.2, 16.3)
    for side in (1, -1):
        box(kit, "white", -X - 0.05, X + 0.05, side * (Y - 0.35), side * (Y + 0.05), 16.2, 16.7, 0.05, 1)
        box(kit, "white", side * (X - 0.35), side * (X + 0.05), -Y + 0.3, Y - 0.3, 16.2, 16.7, 0.05, 1)
    for (x0, x1, y0, y1, h) in ((-6.5, -1.0, -9.5, -4.0, 1.3), (1.5, 7.0, 3.0, 9.5, 1.1)):
        box(kit, "buildingShade", x0, x1, y0, y1, 16.3, 16.3 + h, 0.1, 1)
        for k in range(3):
            z = 16.55 + k * 0.3
            box(kit, "darkMetal", x0 - 0.04, x1 + 0.04, y0 + 0.4, y1 - 0.4, z, z + 0.08)


def guardhouse(kit):
    """Security booth (window to +X), a boom barrier whose white arm with red
    stripes (ae_cloth, painted red by the app) reaches 6 m along +X, and a
    sliding gate section along +Y beside it."""
    kit.recentre = True
    box(kit, "buildingShade", -1.45, 1.45, -1.35, 1.35, 0, 0.25, 0.04, 1)
    box(kit, "building", -1.25, 1.25, -1.15, 1.15, 0.25, 3.0, 0.08, 1)
    box(kit, "windowDark", -1.28, 1.28, -1.18, 1.18, 1.2, 2.35)
    for x, y in ((1.25, 1.15), (1.25, -1.15), (-1.25, 1.15), (-1.25, -1.15)):
        box(kit, "building", x - 0.12, x + 0.12, y - 0.12, y + 0.12, 0.25, 3.0)
    box(kit, "darkMetal", -1.3, -1.26, -0.42, 0.42, 0.25, 2.2)  # door at the back
    box(kit, "roof", -1.6, 1.6, -1.5, 1.5, 3.0, 3.3, 0.05, 1)
    box(kit, "white", -1.62, 1.62, -1.52, 1.52, 3.0, 3.1)
    box(kit, "lamp", 1.6, 1.64, -0.3, 0.3, 2.86, 2.98)
    # Boom barrier: housing, counterweight, arm with stripes.
    box(kit, "white", 1.55, 1.95, -1.85, -1.45, 0, 1.05, 0.05, 1)
    box(kit, "darkMetal", 1.5, 2.0, -1.9, -1.4, 1.05, 1.12)
    box(kit, "darkMetal", 1.15, 1.55, -1.72, -1.58, 0.88, 1.08)
    box(kit, "white", 1.95, 7.75, -1.7, -1.6, 0.9, 1.02)
    for k in range(4):
        x = 2.6 + k * 1.4
        box(kit, "cloth", x, x + 0.6, -1.705, -1.595, 0.895, 1.025)
    # Sliding gate section on its track.
    box(kit, "darkMetal", 0.9, 1.1, 1.6, 5.6, 0, 0.08)
    for z in (0.15, 1.5):
        box(kit, "darkMetal", 0.95, 1.05, 1.6, 5.6, z, z + 0.08)
    for k in range(14):
        y = 1.65 + k * 0.3
        box(kit, "darkMetal", 0.97, 1.03, y - 0.025, y + 0.025, 0.15, 1.55)
    box(kit, "darkMetal", 0.9, 1.1, 5.5, 5.7, 0, 1.7)


VIEW = lambda s: [("front", (60 * s, 46 * s, 36 * s), (0, 0, 6 * s))]  # noqa: E731
K.run("hangar", hangar, VIEW(2.6))
K.run("cargoShed", cargo_shed, VIEW(2.6))
K.run("fuelTank", fuel_tank, VIEW(0.9))
K.run("controlTower", control_tower, [("front", (95, 70, 60), (0, 0, 30))])
K.run("office_low", office_low, VIEW(2.0))
K.run("midrise_apartment", midrise, VIEW(1.9))
K.run("terminal_pavilion", pavilion, [("front", (40, -46, 30), (0, 0, 7)), ("side", (-30, 40, 22), (0, 0, 7))])
K.run("guardhouse", guardhouse, [("front", (13, -11, 8), (0, 0, 1.5)), ("back", (-10, 12, 7), (0, 0, 1.5))])
