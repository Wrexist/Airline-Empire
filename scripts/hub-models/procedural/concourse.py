"""Hub_concourse_glass.usdz and Hub_concourse_glass_end.usdz (docs/HUB_MODEL_LIST.md §4.1).

The gate shot's glazed pier: a 30 m module, 18 m deep, 11 m to the crown —
a white base 1.2 m high, glass walls with white mullions every 3 m, and a
barrel-vaulted glass roof on white ribs. Modules have open ends so the app
tiles them along a pier (HubSceneBuilder.placeConcourse, +X towards the
tip); the end module closes in a glazed half dome at +X.

    blender --background --python scripts/hub-models/procedural/concourse.py -- --preview <dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

HALF = 9.0           # half depth (y)
WALL = 8.85          # glass wall line
BASE, EAVE, CROWN = 1.2, 6.4, 11.0
ARC = 12             # vault segments across


def arc(t, grow=0.0):
    """Vault cross-section at t in 0..pi: (y, z), `grow` metres outwards."""
    return (WALL + grow) * math.cos(t), EAVE + (CROWN - EAVE + grow) * math.sin(t)


def shell(kit, slot, point, nu, nv, thick=0.06, centre=None):
    """Closed thin glass shell over a (u, v) patch: outer and inner skins plus rims."""
    outer = [[point(i / nu, j / nv, thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    inner = [[point(i / nu, j / nv, -thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    pc = K.Piece().grid(outer, slot).grid(inner, slot)
    pc.face_away_from(centre)
    for f in list(pc.bm.faces)[len(pc.bm.faces) // 2:]:
        f.normal_flip()  # the inner skin faces inwards
    kit.add(pc)


def vault(kit, x0, x1, ribs):
    centre = lambda c: Vector((c.x, 0, EAVE))  # noqa: E731
    shell(kit, "glass", lambda u, v, g: Vector((x0 + (x1 - x0) * v, *arc(math.pi * u, g))), ARC, 1, centre=centre)
    for x in ribs:
        pts = [Vector((x, *arc(math.pi * i / ARC, 0.16))) for i in range(ARC + 1)]
        for a, b in zip(pts, pts[1:]):
            kit.add(kit.beam(a, b, 0.28, 0.3, "white", side=(1, 0, 0)))
    # Spine and two purlins along the vault.
    for t in (math.pi / 2, math.pi / 4, 3 * math.pi / 4):
        y, z = arc(t, 0.12)
        kit.add(kit.beam((x0, y, z), (x1, y, z), 0.22, 0.22, "white", side=(0, 1, 0)))


def walls(kit, x0, x1, mullions):
    for side in (1, -1):
        kit.add(K.Piece().box(((x0 + x1) / 2, side * WALL, (BASE + EAVE) / 2), (x1 - x0, 0.08, EAVE - BASE),
                              "glass").seal())
        kit.add(kit.beam((x0, side * (WALL + 0.05), EAVE - 0.1), (x1, side * (WALL + 0.05), EAVE - 0.1), 0.45, 0.4,
                         "white"))
        kit.add(kit.beam((x0, side * (WALL + 0.06), 3.8), (x1, side * (WALL + 0.06), 3.8), 0.12, 0.12, "white"))
        for x in mullions:
            kit.add(K.Piece().box((x, side * (WALL + 0.06), (BASE + EAVE) / 2), (0.2, 0.22, EAVE - BASE),
                                  "white").seal())


def base(kit, outline):
    """White plinth under an outline (convex, in the xy plane), with a floor on top."""
    lo = [Vector((x, y, 0)) for x, y in outline]
    hi = [Vector((x, y, BASE)) for x, y in outline]
    kit.add(K.Piece().loft([lo, hi], "white", cap0="white", cap1="building").seal())


def straight(kit):
    ribs = [-15 + 1.5 + 3 * k for k in range(10)]
    base(kit, [(-15, -HALF), (15, -HALF), (15, HALF), (-15, HALF)])
    walls(kit, -15, 15, ribs)
    vault(kit, -15, 15, ribs)


def end(kit):
    xa = 6.0  # where the half dome begins
    ribs = [-15 + 1.5 + 3 * k for k in range(7)]
    apse = [(xa + HALF * math.sin(p), HALF * math.cos(p)) for p in
            (math.pi * k / 12 for k in range(13))]  # from +y round the tip to -y
    base(kit, [(-15, -HALF), (xa, -HALF)] + list(reversed(apse))[1:-1] + [(xa, HALF), (-15, HALF)])
    walls(kit, -15, xa, ribs)
    vault(kit, -15, xa, ribs)
    # Half dome: the vault's arc swept round the tip.
    def dome(u, v, g):
        y, z = arc(math.pi * u, g)
        phi = math.pi / 2 * v
        return Vector((xa + abs(y) * math.sin(phi), y * math.cos(phi), z))
    shell(kit, "glass", dome, ARC, 6, centre=lambda c: Vector((xa, 0, EAVE)))
    for phi in (math.pi / 6, math.pi / 3, math.pi / 2):
        for sign in (1, -1):
            pts = [Vector((xa + abs(y) * math.sin(phi), y * math.cos(phi), z))
                   for y, z in (arc(math.pi * i / ARC, 0.16) for i in range(ARC // 2 + 1))]
            if sign < 0:
                pts = [Vector((p.x, -p.y, p.z)) for p in pts]
            for a, b in zip(pts, pts[1:]):
                kit.add(kit.beam(a, b, 0.28, 0.3, "white", side=(0, 0, 1)))
    # Curved glass wall, mullions and eave round the apse.
    ring = [Vector((xa + WALL * math.sin(p), WALL * math.cos(p), 0)) for p in (math.pi * k / 12 for k in range(13))]
    rows = [[Vector((v.x, v.y, z)) for v in ring] for z in (BASE, EAVE)]
    pc = K.Piece().grid(rows, "glass").face_away_from(lambda c: Vector((xa, 0, c.z)))
    kit.add(pc)
    for a, b in zip(ring, ring[1:]):
        kit.add(kit.beam(a + Vector((0, 0, EAVE - 0.1)), b + Vector((0, 0, EAVE - 0.1)), 0.45, 0.4, "white"))
    for v in ring[1:-1]:
        kit.add(K.Piece().box((v.x, v.y, (BASE + EAVE) / 2), (0.2, 0.2, EAVE - BASE), "white").seal())


VIEWS = [("gate", (40, 34, 22), (0, 0, 5)), ("inside", (-30, 4, 9), (0, 0, 6))]

K.run("concourse_glass", straight, VIEWS)
K.run("concourse_glass_end", end, VIEWS)
