"""Hub_vehicle_beltLoader.usdz — belt loader (docs/HUB_MODEL_LIST.md §2.2).

7.5 × 2 m: a white chassis with a boxy cab-over cab (big dark windscreen)
at the back, carrying a long belt ramp — metal-grey belt between dark side
frames, yellow hand rails — raised to ~3.5 m at the aircraft end (+X).

    blender --background --python scripts/hub-models/procedural/vehicle_beltLoader.py -- --preview <dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

RY = 0.3                         # the ramp runs beside the cab, not through it
LOW = Vector((-3.75, RY, 1.05))  # ramp's low end (belt surface)
HIGH = Vector((3.75, RY, 3.45))  # aircraft end


def on_ramp(t, dz=0.0):
    """Point along the belt (t = 0 low end, 1 high end), dz above its surface."""
    p = LOW.lerp(HIGH, t)
    d = (HIGH - LOW).normalized()
    n = Vector((-d.z, 0, d.x))
    return p + n * dz


def build(kit):
    for x in (1.75, -1.75):
        for y in (0.8, -0.8):
            kit.add(kit.wheel(x, y, 0.38, 0.32))
    # Chassis and cab at the back.
    kit.add(K.Piece().box((-0.15, 0, 0.68), (5.6, 1.9, 0.6), "white", bevel=0.18, segments=2).seal())
    kit.add(K.Piece().box((-0.15, 0, 0.36), (5.2, 1.5, 0.14), "darkMetal").seal())
    kit.add(K.Piece().box((-2.55, -0.64, 1.55), (1.25, 0.66, 1.15), "white", bevel=0.12, segments=2).seal())
    kit.add(K.Piece().box((-1.93, -0.64, 1.7), (0.04, 0.54, 0.6), "windowDark").seal())
    kit.add(K.Piece().box((-2.6, -0.95, 1.7), (0.9, 0.04, 0.55), "windowDark").seal())
    # Ramp: belt (dark metal) between side frames, on two struts.
    d = (HIGH - LOW).normalized()
    kit.add(kit.beam(on_ramp(0, -0.12), on_ramp(1, -0.12), 0.9, 0.18, "darkMetal"))
    for y in (0.52, -0.52):
        kit.add(kit.beam(on_ramp(0, -0.2) + Vector((0, y, 0)), on_ramp(1, -0.2) + Vector((0, y, 0)),
                         0.14, 0.42, "darkMetal"))
    # Rollers at both ends.
    for t in (0.0, 1.0):
        kit.add(kit.lathe([(-0.5, 0.0), (-0.5, 0.13), (0.5, 0.13), (0.5, 0.0)], "darkMetal",
                          center=on_ramp(t, -0.12), axis=(0, 1, 0), n=10))
    for x0, x1 in ((-0.4, 0.9), (1.4, 2.2)):
        t0 = (x1 - LOW.x) / (HIGH.x - LOW.x)
        top = on_ramp(t0, -0.4)
        for y in (0.3, -0.3):
            kit.add(kit.beam(Vector((x0, RY + y, 0.98)), top + Vector((0, y, 0)), 0.12, 0.12, "darkMetal"))
    # Yellow hand rails: posts and a top rail each side, upper two thirds.
    for y in (0.58, -0.58):
        posts = [0.3, 0.52, 0.74, 0.97]
        for t in posts:
            base = on_ramp(t, 0.0) + Vector((0, y, 0))
            kit.add(kit.beam(base, base + Vector((0, 0, 0.9)), 0.06, 0.06, "hiVis"))
        a = on_ramp(posts[0], 0.0) + Vector((0, y, 0.9))
        b = on_ramp(posts[-1], 0.0) + Vector((0, y, 0.9))
        kit.add(kit.beam(a, b, 0.07, 0.07, "hiVis"))


VIEWS = [
    ("front", (9, 8, 5), (0, 0, 1.8)),
    ("side", (0, -14, 2.5), (0, 0, 1.8)),
]

K.run("vehicle_beltLoader", build, VIEWS)
