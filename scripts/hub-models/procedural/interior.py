"""Terminal interior props (docs/HUB_MODEL_LIST.md §5), at real size.

Orientation follows HubSceneBuilder.authored(): the kiosk, desk and shelf
are turned to the hall's front, so their front is +X; the e-gate and the
seat row are placed unturned, so they match the procedural pieces' axes.
App +Z is Blender -Y here.

  kiosk_selfService  rounded white pedestal, tilted blue screen, printer slot
  checkInDesk        white counter, dark top, monitor, bag belt
  eGate              white pedestal along z, glass flap towards +X, screen
  shop_shelving      wood unit stocked with products in mixed colours
  seatRow            four linked seats facing app +Z
  metalDetector      white walk-through arch, walked along +X
  stanchion_belt     2 m queue segment: two posts, a dark belt
  shop_pharmacy      shop unit, open front +X under a dark fascia
  shop_gondola       white island shelf along z, stocked both faces
  cafe_counter       wood counter along z, glass case, coffee machine
  luggageTrolley     white trolley with suitcases, pushed towards +X
  electricCart       indoor passenger cart, two benches
  plant_pot          round planter with a leafy plant

    blender --background --python scripts/hub-models/procedural/interior.py -- --preview <dir> [--only slot,...]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402


def box(kit, slot, c, s, bevel=0.0, seg=1):
    kit.add(K.Piece().box(c, s, slot, bevel=bevel, segments=seg).seal())


def kiosk(kit):
    kit.recentre = True
    box(kit, "white", (0, 0, 0.55), (0.42, 0.5, 1.1), 0.08, 2)
    box(kit, "white", (0, 0, 0.03), (0.6, 0.6, 0.06), 0.02, 1)
    # Head tilted back towards the user, screen on its front (+X).
    head = K.Piece().box((0, 0, 0), (0.3, 0.62, 0.48), "white", bevel=0.05, segments=2)
    screen = K.Piece().box((0.155, 0, 0.02), (0.02, 0.52, 0.36), "screen")
    for pc in (head, screen):
        for v in pc.bm.verts:
            x, z = v.co.x, v.co.z
            a = math.radians(-28)  # lean back
            v.co.x, v.co.z = x * math.cos(a) - z * math.sin(a), x * math.sin(a) + z * math.cos(a)
            v.co += Vector((0.02, 0, 1.3))
        kit.add(pc.seal())
    box(kit, "darkMetal", (0.215, 0, 0.82), (0.02, 0.24, 0.04))  # printer slot


def desk(kit):
    kit.recentre = True
    box(kit, "white", (0, 0, 0.52), (0.85, 2.0, 1.04), 0.06, 2)
    box(kit, "darkMetal", (0, 0, 1.07), (0.95, 2.1, 0.06), 0.02, 1)
    box(kit, "darkMetal", (0.43, 0, 0.5), (0.02, 1.7, 0.08))  # kick strip
    # Monitor on a stalk, and the bag belt beside the counter.
    box(kit, "darkMetal", (-0.15, 0.5, 1.2), (0.05, 0.05, 0.22))
    box(kit, "screen", (-0.14, 0.5, 1.42), (0.04, 0.5, 0.32), 0.01, 1)
    box(kit, "darkMetal", (0.05, -1.25, 0.25), (0.8, 0.5, 0.5), 0.04, 1)


def egate(kit):
    kit.recentre = True
    box(kit, "white", (-0.25, 0, 0.6), (0.36, 2.5, 1.2), 0.08, 2)
    box(kit, "darkMetal", (-0.25, 0, 1.21), (0.38, 2.52, 0.03))
    box(kit, "glass", (0.25, 0.2, 0.75), (0.64, 0.05, 0.8), 0.02, 1)
    box(kit, "glass", (0.25, -0.2, 0.75), (0.64, 0.05, 0.8), 0.02, 1)
    box(kit, "screen", (-0.25, 0.95, 1.33), (0.26, 0.04, 0.2), 0.01, 1)
    box(kit, "darkMetal", (-0.25, 0.95, 1.25), (0.04, 0.04, 0.1))


def shelving(kit):
    kit.recentre = True
    box(kit, "houseWood", (-0.2, 0, 1.1), (0.2, 4.0, 2.2), 0.03, 1)
    for side in (1, -1):
        box(kit, "houseWood", (0.0, side * 1.97, 1.1), (0.6, 0.06, 2.2), 0.02, 1)
    colours = ["cloth", "hiVis", "cone", "water", "grassBright", "white"]
    for k in range(5):
        z = 0.12 + k * 0.48
        box(kit, "houseWood", (0.0, 0, z), (0.6, 3.9, 0.04))
        if k == 4:
            break
        n = 9
        for i in range(n):
            y = -1.75 + (i + 0.5) * 3.5 / n
            slot = colours[(i * 5 + k * 2) % len(colours)]
            h = 0.18 + 0.1 * ((i + k) % 3)
            box(kit, slot, (0.08, y, z + 0.02 + h / 2), (0.34, 3.5 / n * 0.8, h))


def seat_row(kit):
    kit.recentre = True
    # App +Z is Blender -Y: seats face -Y, backrest at +Y.
    box(kit, "darkMetal", (0, 0.05, 0.22), (4.0, 0.08, 0.06))
    for x in (-1.7, 1.7):
        box(kit, "darkMetal", (x, 0.05, 0.11), (0.08, 0.5, 0.22))
    for k in range(4):
        x = -1.5 + k * 1.0
        box(kit, "cloth", (x, -0.02, 0.44), (0.88, 0.56, 0.1), 0.04, 1)
        box(kit, "cloth", (x, 0.28, 0.72), (0.88, 0.1, 0.5), 0.04, 1)
        if k:
            box(kit, "white", (x - 0.5, -0.02, 0.6), (0.06, 0.5, 0.05))


PRODUCTS = ["cloth", "hiVis", "cone", "water", "grassBright", "white"]


def stock(kit, x, y0, y1, z, depth, n, seed, h0=0.16, step=0.08):
    """A row of n product boxes on a shelf at height z, from y0 to y1, their
    fronts at x (facing +X when depth > 0, -X when depth < 0)."""
    pitch = (y1 - y0) / n
    for i in range(n):
        slot = PRODUCTS[(i * 5 + seed * 3) % len(PRODUCTS)]
        h = h0 + step * ((i + seed) % 3)
        box(kit, slot, (x - depth / 2, y0 + (i + 0.5) * pitch, z + h / 2), (abs(depth), pitch * 0.82, h))


def metal_detector(kit):
    # Walk through along +X; posts at the sides, a lintel with a status strip.
    for side in (1, -1):
        box(kit, "white", (0, side * 0.52, 1.08), (0.62, 0.26, 2.16), 0.05, 2)
        box(kit, "darkMetal", (0, side * 0.52, 0.03), (0.7, 0.32, 0.06), 0.02, 1)
    box(kit, "white", (0, 0, 2.27), (0.62, 1.3, 0.26), 0.05, 2)
    box(kit, "screen", (0.32, 0, 2.27), (0.02, 0.5, 0.08))
    box(kit, "darkMetal", (0, 0, 0.01), (0.9, 0.78, 0.02))  # floor mat


def stanchion(kit):
    # One 2 m segment along x: posts exactly at ±1 so tiled segments share them.
    for x in (-1.0, 1.0):
        kit.add(kit.lathe([(0, 0.0), (0, 0.16), (0.025, 0.15), (0.035, 0.03), (0.92, 0.028), (0.93, 0.042),
                           (0.97, 0.04), (0.98, 0.0)],
                          ["darkMetal", "darkMetal", "white", "white", "white", "white", "white"],
                          center=(x, 0, 0), axis=(0, 0, 1), n=8))
    box(kit, "darkMetal", (0, 0, 0.87), (2.0, 0.012, 0.06))


def pharmacy(kit):
    """Shop unit 10 m wide (along y) and 5 m deep, open front at +X under a
    dark fascia with a green-cross sign; wood shelving packed with products
    on the back and side walls, a white counter by the door. The app writes
    the shop's name on the fascia."""
    D, W, H = 2.5, 5.0, 4.3
    box(kit, "white", (-D + 0.08, 0, H / 2), (0.16, 2 * W, H))  # back wall
    for side in (1, -1):
        box(kit, "white", (0, side * (W - 0.08), H / 2), (2 * D, 0.16, H))
        box(kit, "darkMetal", (D - 0.15, side * (W - 0.2), 1.65), (0.3, 0.4, 3.3), 0.03, 1)  # pilasters
    box(kit, "darkMetal", (D - 0.15, 0, 3.8), (0.3, 2 * W, 1.0), 0.04, 1)  # fascia
    # Green cross in a white light box at one end of the fascia.
    box(kit, "white", (D + 0.03, 3.9, 3.8), (0.06, 0.8, 0.8), 0.02, 1)
    box(kit, "grassBright", (D + 0.07, 3.9, 3.8), (0.04, 0.56, 0.18))
    box(kit, "grassBright", (D + 0.07, 3.9, 3.8), (0.04, 0.18, 0.56))
    # Back wall shelving: a wood unit, four shelves of stock.
    bx = -D + 0.16
    box(kit, "houseWood", (bx + 0.03, 0, 1.4), (0.06, 2 * W - 0.4, 2.8))
    for k in range(5):
        z = 0.1 + k * 0.62
        box(kit, "houseWood", (bx + 0.27, 0, z), (0.5, 2 * W - 0.4, 0.05))
        if k < 4:
            stock(kit, bx + 0.48, -W + 0.4, W - 0.4, z + 0.025, 0.4, 16, k)
    for side in (1, -1):
        box(kit, "houseWood", (bx + 0.27, side * (W - 0.24), 1.4), (0.5, 0.06, 2.8))
    # Side wall shelving facing into the shop.
    for side in (1, -1):
        y = side * (W - 0.16)
        box(kit, "houseWood", (-0.2, y - side * 0.2, 0.06), (3.2, 0.4, 0.12))
        for k in range(3):
            z = 0.12 + k * 0.62
            box(kit, "houseWood", (-0.2, y - side * 0.2, z + 0.62), (3.2, 0.4, 0.04))
            for i in range(6):
                slot = PRODUCTS[(i * 2 + k + (side > 0)) % len(PRODUCTS)]
                h = 0.2 + 0.08 * ((i + k) % 3)
                box(kit, slot, (-1.55 + (i + 0.5) * 0.45, y - side * 0.24, z + h / 2), (0.36, 0.3, h))
    # Counter by the door, its till facing the staff behind it.
    box(kit, "white", (1.0, 2.6, 0.52), (0.8, 2.4, 1.04), 0.05, 1)
    box(kit, "darkMetal", (1.0, 2.6, 1.07), (0.9, 2.5, 0.06))
    box(kit, "screen", (0.85, 2.0, 1.25), (0.04, 0.4, 0.3))
    box(kit, "darkMetal", (0.88, 2.0, 1.12), (0.08, 0.08, 0.1))


def gondola(kit):
    """Island shelf along y, stocked on both faces (±X)."""
    L = 1.7
    box(kit, "darkMetal", (0, 0, 0.05), (0.9, 2 * L - 0.1, 0.1))
    box(kit, "white", (0, 0, 0.72), (0.12, 2 * L - 0.1, 1.3), 0.02, 1)
    for side in (1, -1):
        box(kit, "white", (0, side * (L - 0.04), 0.7), (0.98, 0.08, 1.4), 0.03, 1)
    for k in range(3):
        z = 0.1 + k * 0.42
        box(kit, "white", (0, 0, z), (0.94, 2 * L - 0.16, 0.03))
        for face in (1, -1):
            stock(kit, face * 0.45, -L + 0.12, L - 0.12, z + 0.015, face * 0.36, 7, k + (face > 0), h0=0.18, step=0.06)


def cafe_counter(kit):
    """Wood counter 5 m long (along y), customers at +X: glass display case,
    coffee machine and a menu board on the back edge."""
    L = 2.5
    box(kit, "houseWood", (0, 0, 0.5), (1.0, 2 * L, 1.0), 0.03, 1)
    box(kit, "darkMetal", (0.49, 0, 0.06), (0.04, 2 * L - 0.1, 0.12))
    box(kit, "white", (0.02, 0, 1.03), (1.14, 2 * L + 0.1, 0.06), 0.02, 1)
    # Display case with cakes.
    box(kit, "darkMetal", (0.15, 1.2, 1.09), (0.62, 2.0, 0.06))
    box(kit, "glass", (0.15, 1.2, 1.34), (0.6, 1.96, 0.44), 0.02, 1)
    for i, slot in enumerate(["cone", "white", "hiVis", "cone", "white"]):
        box(kit, slot, (0.15, 0.45 + i * 0.38, 1.18), (0.26, 0.24, 0.12))
    # Coffee machine, cups, menu board.
    box(kit, "darkMetal", (-0.18, -1.3, 1.32), (0.5, 0.9, 0.52), 0.04, 1)
    box(kit, "white", (0.08, -1.3, 1.3), (0.04, 0.6, 0.08))
    for i in range(3):
        kit.add(kit.lathe([(0, 0.0), (0, 0.04), (0.1, 0.05), (0.1, 0.0)], "white",
                          center=(-0.15, -0.55 + i * 0.12, 1.06), axis=(0, 0, 1), n=6))
    box(kit, "darkMetal", (-0.53, -1.0, 1.5), (0.06, 2.6, 0.9), 0.02, 1)
    box(kit, "screen", (-0.49, -1.0, 1.5), (0.02, 2.4, 0.74))


def luggage_trolley(kit):
    """Pushed towards +X, handle at the back; suitcases in ae_cloth (the app paints them blue)."""
    kit.recentre = True
    box(kit, "white", (0.02, 0, 0.16), (1.1, 0.6, 0.05), 0.015, 1)
    box(kit, "white", (0.6, 0, 0.22), (0.05, 0.6, 0.16), 0.01, 1)
    for y in (0.27, -0.27):
        kit.add(kit.beam((-0.5, y, 0.16), (-0.62, y, 1.04), 0.04, 0.04, "white"))
    kit.add(kit.beam((-0.62, 0.31, 1.04), (-0.62, -0.31, 1.04), 0.05, 0.05, "white"))
    kit.add(kit.beam((-0.64, 0.2, 1.06), (-0.64, -0.2, 1.06), 0.06, 0.06, "darkMetal"))
    for x in (0.42, -0.42):
        for y in (0.24, -0.24):
            kit.add(kit.lathe([(-0.02, 0.0), (-0.02, 0.07), (0.02, 0.07), (0.02, 0.0)], ["darkMetal", "tyre", "darkMetal"],
                              center=(x, y, 0.07), axis=(0, 1, 0), n=6))
    box(kit, "cloth", (0.03, 0, 0.32), (0.92, 0.52, 0.28), 0.04, 1)
    box(kit, "cloth", (-0.05, 0.02, 0.59), (0.7, 0.46, 0.26), 0.04, 1)
    box(kit, "cloth", (-0.3, -0.02, 0.88), (0.4, 0.4, 0.32), 0.04, 1)
    box(kit, "darkMetal", (-0.3, -0.02, 1.06), (0.12, 0.04, 0.04))


def electric_cart(kit):
    """Indoor passenger cart, 2.8 m, front +X: two bench seats, dash, beacon."""
    for x in (0.95, -0.95):
        for y in (0.56, -0.56):
            kit.add(kit.wheel(x, y, 0.19, 0.14, n=10))
    box(kit, "darkMetal", (0, 0, 0.26), (2.6, 1.0, 0.16))
    box(kit, "white", (0.02, 0, 0.46), (2.76, 1.3, 0.38), 0.12, 2)
    box(kit, "darkMetal", (1.39, 0, 0.36), (0.06, 1.1, 0.14), 0.02, 1)  # bumper
    for y in (0.4, -0.4):
        box(kit, "lamp", (1.4, y, 0.55), (0.03, 0.18, 0.08))
    # Dash with a screen and the wheel.
    box(kit, "white", (1.15, 0, 0.86), (0.4, 1.24, 0.46), 0.08, 2)
    box(kit, "screen", (0.94, 0.25, 0.98), (0.02, 0.3, 0.16))
    kit.add(kit.beam((1.0, -0.25, 0.9), (0.85, -0.25, 1.08), 0.04, 0.04, "darkMetal"))
    kit.add(kit.lathe([(0, 0.0), (0, 0.13), (0.03, 0.13), (0.03, 0.0)], "darkMetal", center=(0.85, -0.25, 1.08),
                      axis=(0.6, 0, 0.8), n=8))
    # Two benches.
    for x in (0.35, -0.75):
        box(kit, "cloth", (x, 0, 0.72), (0.56, 1.16, 0.14), 0.05, 1)
        box(kit, "cloth", (x - 0.3, 0, 0.98), (0.12, 1.16, 0.46), 0.05, 1)
    # Beacon pole at the back.
    kit.add(kit.beam((-1.3, -0.5, 0.6), (-1.3, -0.5, 1.4), 0.04, 0.04, "darkMetal"))
    kit.add(kit.lathe([(0, 0.0), (0, 0.06), (0.1, 0.06), (0.12, 0.0)], "hiVis", center=(-1.3, -0.5, 1.4),
                      axis=(0, 0, 1), n=8))


def plant_pot(kit):
    """Round white planter, leafy plant, 1.5 m."""
    kit.smooth = 70
    kit.add(kit.lathe([(0, 0.0), (0, 0.22), (0.46, 0.29), (0.5, 0.3), (0.5, 0.27), (0.47, 0.27), (0.47, 0.0)],
                      ["white", "white", "white", "white", "darkMetal", "darkMetal"], center=(0, 0, 0),
                      axis=(0, 0, 1), n=12))
    kit.add(kit.lathe([(0.45, 0.0), (0.45, 0.035), (0.9, 0.025), (0.9, 0.0)], "trunk", center=(0, 0, 0),
                      axis=(0, 0, 1), n=6))
    for c, r in [((0.0, 0.0, 1.16), (0.3, 0.3, 0.3)), ((0.1, 0.08, 1.33), (0.2, 0.2, 0.17)),
                 ((-0.14, 0.12, 0.9), (0.24, 0.22, 0.2)), ((0.15, -0.14, 0.88), (0.22, 0.24, 0.2)),
                 ((-0.06, -0.1, 1.28), (0.2, 0.19, 0.17))]:
        kit.add(kit.ellipsoid(c, r, "tree", n=10, rings=6))


V = lambda d, z: [("front", (d, -d * 0.8, d * 0.6), (0, 0, z))]  # noqa: E731
K.run("metalDetector", metal_detector, V(4.0, 1.1))
K.run("stanchion_belt", stanchion, V(3.0, 0.5))
K.run("shop_pharmacy", pharmacy, [("front", (13, -9, 7), (0, 0, 1.8))])
K.run("shop_gondola", gondola, V(4.2, 0.7))
K.run("cafe_counter", cafe_counter, V(5.5, 1.0))
K.run("luggageTrolley", luggage_trolley, V(2.6, 0.5))
K.run("electricCart", electric_cart, V(4.6, 0.7))
K.run("plant_pot", plant_pot, V(2.6, 0.75))
K.run("kiosk_selfService", kiosk, V(2.4, 0.8))
K.run("checkInDesk", desk, V(3.4, 0.6))
K.run("eGate", egate, V(3.4, 0.6))
K.run("shop_shelving", shelving, V(5.0, 1.1))
K.run("seatRow", seat_row, [("front", (3.0, -4.0, 2.4), (0, 0, 0.4))])
