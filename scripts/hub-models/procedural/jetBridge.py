"""Hub_jetBridge.usdz — the gate shot's glass bridge (docs/HUB_MODEL_LIST.md §4.3).

22 m at rest, root (rotunda) at -X, aircraft end (cab) at +X. Three named
sub-prims the app moves separately (HubSceneBuilder.extendBridge): the
`rotunda` stays on the root, the `cab` (with the drive bogie) goes to the
door, and the `tunnel` — two telescoping glass sections with white rib
rings and a white floor, sloping down from the concourse to the door —
stretches between them.

    blender --background --python scripts/hub-models/procedural/jetBridge.py -- --preview <dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

ROT_X = -8.7                  # rotunda centre
T0, T1 = -6.5, 7.3            # tunnel from the rotunda to the cab
Z0, Z1 = 4.9, 3.55            # tube centre height at each end (slopes to the door)
SEG = 20


def zc(x):
    return Z0 + (Z1 - Z0) * (x - T0) / (T1 - T0)


def ring(x, ry, rz):
    return K.Kit.circle((x, 0, zc(x)), (1, 0, 0), 1.0, SEG, scale=(rz, ry))


def rect(x, half_w, z_top, thick):
    return [Vector((x, -half_w, z_top)), Vector((x, half_w, z_top)),
            Vector((x, half_w, z_top - thick)), Vector((x, -half_w, z_top - thick))]


def section(kit, x0, x1, ry, rz):
    # Glass tube, closed at both ends so it reads as a solid volume.
    kit.add(K.Piece().loft([ring(x0, ry, rz), ring(x1, ry, rz)], "glass", cap0="glass", cap1="glass").seal())
    # White rib rings, the ends heavier.
    xs = [x0 + 0.1] + [x0 + 0.1 + k * 1.4 for k in range(1, int((x1 - x0 - 0.2) / 1.4) + 1)] + [x1 - 0.1]
    for k, x in enumerate(xs):
        w = 0.32 if k in (0, len(xs) - 1) else 0.16
        a, b = x - w / 2, x + w / 2
        o = 0.09
        rings = [ring(a, ry - 0.02, rz - 0.02), ring(a, ry + o, rz + o), ring(b, ry + o, rz + o),
                 ring(b, ry - 0.02, rz - 0.02), ring(a, ry - 0.02, rz - 0.02)]
        kit.add(K.Piece().loft(rings, "white").seal())
    # Floor slab along the bottom, and a dark beam under it.
    top = lambda x: zc(x) - rz + 0.35  # noqa: E731
    kit.add(K.Piece().loft([rect(x0, ry * 0.86, top(x0), 0.45), rect(x1, ry * 0.86, top(x1), 0.45)],
                           "white", cap0="white", cap1="white").seal())
    kit.add(K.Piece().loft([rect(x0 + 0.3, 0.5, top(x0 + 0.3) - 0.45, 0.35),
                            rect(x1 - 0.3, 0.5, top(x1 - 0.3) - 0.45, 0.35)],
                           "darkMetal", cap0="darkMetal", cap1="darkMetal").seal())


def build(kit):
    # Rotunda: column, drum with a glazed band, overhanging roof.
    kit.group = "rotunda"
    kit.add(kit.lathe([(0, 0.0), (0, 0.75), (2.7, 0.75), (2.7, 0.0)], "darkMetal",
                      center=(ROT_X, 0, 0), axis=(0, 0, 1), n=12))
    prof = [(0, 0.0), (0, 2.3), (1.6, 2.3), (1.6, 2.2), (3.0, 2.2), (3.0, 2.3), (3.8, 2.3), (3.8, 2.45),
            (4.1, 2.45), (4.1, 0.0)]
    slots = ["white", "white", "white", "glass", "white", "white", "white", "white", "white"]
    kit.add(kit.lathe(prof, slots, center=(ROT_X, 0, 2.6), axis=(0, 0, 1), n=24))

    # Tunnel: two telescoping sections, the outer one a little larger.
    kit.group = "tunnel"
    section(kit, T0, 1.2, 1.45, 1.5)
    section(kit, 0.8, T1, 1.56, 1.62)

    # Cab with side windows and a dark bellows canopy; drive bogie behind it.
    kit.group = "cab"
    kit.add(K.Piece().box((9.05, 0, 3.3), (3.1, 4.0, 3.0), "white", bevel=0.3, segments=2).seal())
    for side in (1, -1):
        kit.add(K.Piece().box((9.0, side * 2.0, 3.95), (2.0, 0.06, 0.9), "glass", bevel=0.03, segments=1).seal())
    # Bellows: a dark frame with three folds stepping out to the door.
    kit.add(K.Piece().box((10.85, 0, 3.15), (0.3, 3.0, 2.4), "darkMetal", bevel=0.1, segments=2).seal())
    for k in range(3):
        kit.add(K.Piece().box((10.62 + k * 0.1, 0, 3.15), (0.07, 3.4 - k * 0.12, 2.75 - k * 0.1), "darkMetal",
                              bevel=0.02, segments=1).seal())
    xb = 5.6
    kit.add(K.Piece().box((xb, 0, 1.65), (0.55, 0.55, 1.7), "darkMetal", bevel=0.06, segments=1).seal())
    kit.add(K.Piece().box((xb, 0, 0.88), (0.9, 3.2, 0.32), "darkMetal", bevel=0.06, segments=1).seal())
    for side in (1, -1):
        prof = [(-0.16, 0.0), (-0.16, 0.25), (-0.16, 0.38), (-0.1, 0.45), (0.1, 0.45), (0.16, 0.38),
                (0.16, 0.25), (0.16, 0.0)]
        kit.add(kit.lathe(prof, ["darkMetal", "tyre", "tyre", "tyre", "tyre", "tyre", "darkMetal"],
                          center=(xb, side * 1.45, 0.45), axis=(0, 1, 0), n=12))
    kit.group = None


VIEWS = [
    ("gate", (14, 22, 12), (0, 0, 3.5)),
    ("side", (0, 30, 4), (0, 0, 3.5)),
    ("cab", (18, -9, 6), (8, 0, 3.4)),
]

K.run("jetBridge", build, VIEWS)
