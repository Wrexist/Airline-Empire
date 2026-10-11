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

    blender --background --python scripts/hub-models/procedural/interior.py -- --preview <dir>
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


V = lambda d, z: [("front", (d, -d * 0.8, d * 0.6), (0, 0, z))]  # noqa: E731
K.run("kiosk_selfService", kiosk, V(2.4, 0.8))
K.run("checkInDesk", desk, V(3.4, 0.6))
K.run("eGate", egate, V(3.4, 0.6))
K.run("shop_shelving", shelving, V(5.0, 1.1))
K.run("seatRow", seat_row, [("front", (3.0, -4.0, 2.4), (0, 0, 0.4))])
