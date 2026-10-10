"""Hub_aircraft_narrowbody.usdz — the hero jet (docs/HUB_MODEL_LIST.md §1.1).

A320-class twin: 38 m long, 35.8 m span, 11.8 m to the fin tip. Matches the
app's procedural metrics where other code relies on them (HubModels.metrics:
fuselage radius 2 m, axis 3.5 m up, forward left door 4.94 m behind the
nose; engines near HubModels.enginePosition, where the pulse rings sit).

    blender --background --python scripts/hub-models/procedural/aircraft_narrowbody.py -- --preview <dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

NOSE, TAIL = 19.0, -19.0
SEG = 48  # fuselage segments round

# Fuselage profile: (x, radius, centre height). Full section between the
# nose taper and the tail cone; the cone sweeps the belly up to the APU.
PROFILE = [
    (19.00, 0.06, 3.30), (18.95, 0.30, 3.31), (18.85, 0.50, 3.32), (18.70, 0.70, 3.34),
    (18.50, 0.88, 3.36), (18.25, 1.06, 3.38), (17.95, 1.24, 3.40), (17.60, 1.42, 3.43),
    (17.20, 1.58, 3.45), (16.75, 1.72, 3.47), (16.25, 1.84, 3.48), (15.70, 1.93, 3.49),
    (15.00, 1.99, 3.50), (14.00, 2.00, 3.50), (8.0, 2.00, 3.50), (2.0, 2.00, 3.50),
    (-4.0, 2.00, 3.50), (-7.0, 2.00, 3.50), (-8.5, 1.96, 3.57), (-9.5, 1.88, 3.65),
    (-10.5, 1.76, 3.75), (-11.5, 1.63, 3.85), (-12.5, 1.49, 3.95), (-13.5, 1.34, 4.05),
    (-14.5, 1.19, 4.15), (-15.5, 1.03, 4.25), (-16.5, 0.86, 4.34), (-17.4, 0.67, 4.42),
    (-18.2, 0.46, 4.49), (-18.7, 0.30, 4.53), (-19.0, 0.18, 4.55),
]
SQUASH = 1.03  # sections a touch taller than wide


def skin(x):
    """(radius, centre height) of the fuselage at station x."""
    for (x0, r0, c0), (x1, r1, c1) in zip(PROFILE, PROFILE[1:]):
        if x1 <= x <= x0:
            t = (x0 - x) / (x0 - x1)
            return r0 + (r1 - r0) * t, c0 + (c1 - c0) * t
    return (PROFILE[0][1], PROFILE[0][2]) if x > NOSE else (PROFILE[-1][1], PROFILE[-1][2])


def on_skin(x, phi, off=0.03):
    """Point on the skin; phi = angle from the top, positive towards port (+Y)."""
    r, cz = skin(x)
    return Vector((x, (r + off) * math.sin(phi), cz + (r * SQUASH + off) * math.cos(phi)))


def phi_at(z, x=0.0):
    """Angle from the top where the side of the full section is at height z (port)."""
    r, cz = skin(x)
    return math.acos(max(-1.0, min(1.0, (z - cz) / (r * SQUASH))))


def axis_point(c):
    r, cz = skin(c.x)
    return Vector((c.x, 0, cz))


def patch(kit, slot, x0, x1, p0, p1, nx=4, np_=4, shear=0.0):
    """Decal on the skin over x0..x1, phi p0..p1; `shear` slants x with phi."""
    rows = []
    for i in range(np_ + 1):
        p = p0 + (p1 - p0) * i / np_
        dx = shear * (p - (p0 + p1) / 2)
        rows.append([on_skin(x0 + (x1 - x0) * j / nx + dx, p) for j in range(nx + 1)])
    return K.Piece().grid(rows, slot).face_away_from(axis_point)


def oval(slot, xc, pc, ax, az, n=12):
    r, _ = skin(xc)
    pts = [on_skin(xc + ax * math.cos(2 * math.pi * k / n), pc + (az / r) * math.sin(2 * math.pi * k / n))
           for k in range(n)]
    return K.Piece().fan(pts, slot).face_away_from(axis_point)


def fuselage(kit):
    xs = [x for x, _, _ in PROFILE]
    rings = []
    for x in xs:
        r, cz = skin(x)
        rings.append([Vector((x, r * math.sin(t), cz + r * SQUASH * math.cos(t)))
                      for t in (2 * math.pi * k / SEG for k in range(SEG))])
    kit.add(K.Piece().loft(rings, "white", cap0="white", cap1="white").seal())
    # APU exhaust.
    kit.add(kit.lathe([(0, 0.16), (0.25, 0.16), (0.25, 0.0)], "darkMetal",
                      center=(TAIL + 0.05, 0, 4.55), axis=(-1, 0, 0), n=10, cap0="darkMetal"))
    # Belly fairing under the wing root.
    rings = []
    for x, s in [(5.6, 0.05), (5.0, 0.55), (3.8, 0.88), (2.0, 1.0), (-1.5, 1.0), (-3.6, 0.88),
                 (-4.8, 0.55), (-5.4, 0.05)]:
        rings.append(kit.circle((x, 0, 2.15), (1, 0, 0), 1.0, 24, scale=(0.8 * s, 1.86 * s)))
    kit.add(K.Piece().loft(rings, "white", cap0="white", cap1="white").seal())


def windows(kit):
    # Cockpit: four panes in one dark band, thin white posts between them.
    for side in (1, -1):
        s = side
        kit.add(patch(kit, "windowDark", 17.0, 17.75, s * math.radians(1.6), s * math.radians(37),
                      nx=4, np_=4, shear=-0.5 * s))
        kit.add(patch(kit, "windowDark", 16.1, 16.95, s * math.radians(39.5), s * math.radians(68),
                      nx=4, np_=3, shear=-0.9 * s))
    # Cabin windows: 28 a side, just above mid-height, gaps at the doors.
    p = phi_at(3.95)
    xs = [12.9 - k * 0.72 for k in range(28)]
    for side in (1, -1):
        for x in xs:
            if -8.3 < x < -6.9:
                continue
            kit.add(oval("windowDark", x, side * p, 0.15, 0.2))
    # Door outlines (forward door where the bridge docks: 4.94 m behind the nose).
    w = 0.05
    for side in (1, -1):
        for xc, width, z0, z1 in [(NOSE - 4.94, 0.82, 2.05, 3.95), (-7.6, 0.82, 2.05, 3.95),
                                   (0.95, 0.52, 2.95, 4.15), (0.05, 0.52, 2.95, 4.15)]:
            pa, pb = side * phi_at(z1, xc), side * phi_at(z0, xc)
            dp = side * w / 2 / 2.0  # strip half-width in radians on a 2 m radius
            x0, x1 = xc - width / 2, xc + width / 2
            for a, b, c, d in [(x0, x1, pa - dp, pa + dp), (x0, x1, pb - dp, pb + dp),
                               (x0 - w / 2, x0 + w / 2, pa, pb), (x1 - w / 2, x1 + w / 2, pa, pb)]:
                kit.add(patch(kit, "darkMetal", a, b, c, d, nx=1, np_=3 if a != x0 else 1))


def wings(kit):
    dihedral = math.tan(math.radians(5))
    z0 = 2.62

    def z(y):
        return z0 + (y - 1.5) * dihedral

    up = Vector((0, -math.sin(math.radians(5)), math.cos(math.radians(5))))
    secs = [
        (Vector((3.7, 1.5, z(1.5))), 6.8, 0.82, up),
        (Vector((1.26, 6.3, z(6.3))), 5.06, 0.52, up),
        (Vector((-1.45, 11.6, z(11.6))), 3.25, 0.32, up),
        (Vector((-4.15, 16.9, z(16.9))), 1.5, 0.18, up),
    ]
    # Sharklet: curves up and slightly out from the tip, sweeps back.
    zt = z(16.9)
    secs += [
        (Vector((-4.35, 17.45, zt + 0.35)), 1.3, 0.15, Vector((0, -0.7, 0.7))),
        (Vector((-4.75, 17.75, zt + 1.0)), 1.0, 0.13, Vector((0, -0.97, 0.25))),
        (Vector((-5.55, 17.9, zt + 2.35)), 0.55, 0.1, Vector((0, -1, 0.05))),
    ]
    wing = kit.surface(secs, ["white", "white", "white", "livery", "livery", "livery"], n=20,
                       cap0="white", cap1="livery")
    kit.add(wing, mirror_y=True)
    # Flap-track fairings under the trailing edge.
    for y in (4.2, 8.0, 11.6, 14.6):
        frac = (y - 1.5) / 15.4
        te = 3.7 - 6.8 + (-5.65 - (3.7 - 6.8)) * frac
        kit.add(kit.lathe([(0, 0.0), (0.5, 0.17), (1.6, 0.2), (2.6, 0.12), (3.0, 0.0)], "white",
                          center=(te + 1.6, y, z(y) - 0.25), axis=(-1, 0, 0), n=8), mirror_y=True)


def engines(kit):
    y, zc, xf = 5.95, 1.42, 2.45  # nacelle centre span, height; front of the lip
    prof = [  # (distance aft of the front, radius), closed solid
        (0.75, 0.0), (0.75, 0.82), (0.06, 0.86), (0.0, 0.94), (0.08, 1.03), (0.3, 1.08),
        (1.3, 1.12), (3.0, 1.06), (3.8, 0.88), (4.3, 0.64), (4.3, 0.0),
    ]
    slots = ["darkMetal", "white", "white", "white", "white", "livery", "livery", "livery", "livery", "darkMetal"]
    kit.add(kit.lathe(prof, slots, center=(xf, y, zc), axis=(-1, 0, 0), n=24), mirror_y=True)
    # Spinner and exhaust plug.
    kit.add(kit.lathe([(0.45, 0.0), (0.75, 0.26), (0.76, 0.0)], "white",
                      center=(xf, y, zc), axis=(-1, 0, 0), n=12), mirror_y=True)
    kit.add(kit.lathe([(4.3, 0.5), (5.0, 0.0)], "darkMetal", center=(xf, y, zc), axis=(-1, 0, 0), n=12,
                      cap0="darkMetal"), mirror_y=True)
    # Pylon from the nacelle's top to the wing's underside.
    top = zc + 0.9
    sec = [(Vector((xf - 0.5, y, top)), 3.6, 0.32, Vector((0, 1, 0))),
           (Vector((xf - 1.2, y, top + 0.75)), 3.4, 0.32, Vector((0, 1, 0)))]
    rings = []
    for le, chord, thick, nrm in sec:
        rings.append([le + Vector((-u * chord, 0, 0)) + nrm * (t * thick) for u, t in kit.airfoil(12)])
    kit.add(K.Piece().loft(rings, "white", cap0="white", cap1="white").seal(), mirror_y=True)


def tail(kit):
    # Horizontal stabilisers.
    up = Vector((0, -math.sin(math.radians(6)), math.cos(math.radians(6))))
    dz = math.tan(math.radians(6))
    hs = [(Vector((-13.0, 0.3, 4.0)), 3.7, 0.4, up),
          (Vector((-16.55, 6.2, 4.0 + 5.9 * dz)), 1.3, 0.16, up)]
    kit.add(kit.surface(hs, "white", n=16, cap0="white", cap1="white"), mirror_y=True)
    # Fin in the livery with the diagonal accent flash, root to trailing edge.
    side = Vector((0, 1, 0))
    fin = [(Vector((-10.2, 0, 4.8)), 7.4, 0.55, side),
           (Vector((-12.1, 0, 5.9)), 5.6, 0.5, side),
           (Vector((-14.1, 0, 8.9)), 3.8, 0.36, side),
           (Vector((-16.1, 0, 11.8)), 2.0, 0.22, side)]
    piece = kit.surface(fin, "livery", n=20, cap0="livery", cap1="livery")
    n = Vector((0.9, 0, 1.0)).normalized()
    p0 = Vector((-12.9, 0, 6.3))
    p1 = p0 + n * 1.25
    piece.bisect(p0, n).bisect(p1, n)
    piece.retag(lambda c: 0 < (c - p0).dot(n) < 1.25, "liveryAccent")
    kit.add(piece.seal())


def gear(kit):
    # Nose gear: strut and twin wheels.
    def wheel(x, y, r, w):
        prof = [(-w / 2, 0.0), (-w / 2, r * 0.55), (-w / 2, r * 0.8), (-w * 0.4, r * 0.97), (0, r),
                (w * 0.4, r * 0.97), (w / 2, r * 0.8), (w / 2, r * 0.55), (w / 2, 0.0)]
        slots = ["white", "tyre", "tyre", "tyre", "tyre", "tyre", "tyre", "white"]
        return kit.lathe(prof, slots, center=(x, y, r), axis=(0, 1, 0), n=14)

    xn = NOSE - 5.1
    for y in (0.28, -0.28):
        kit.add(wheel(xn, y, 0.38, 0.26))
    kit.add(kit.lathe([(0.2, 0.09), (1.75, 0.09)], "white", center=(xn, 0, 0), axis=(0, 0, 1), n=8,
                      cap0="white", cap1="white"))
    kit.add(kit.lathe([(-0.42, 0.06), (0.42, 0.06)], "white", center=(xn, 0, 0.38), axis=(0, 1, 0), n=8,
                      cap0="white", cap1="white"))
    # Main gear: a leg with two wheels under each wing.
    xm, ym = -1.6, 3.8
    for y in (ym - 0.45, ym + 0.45):
        kit.add(wheel(xm, y, 0.58, 0.4), mirror_y=True)
    kit.add(kit.lathe([(0.3, 0.14), (2.45, 0.14)], "white", center=(xm, ym, 0), axis=(0, 0, 1), n=8,
                      cap0="white", cap1="white"), mirror_y=True)
    kit.add(kit.lathe([(-0.65, 0.09), (0.65, 0.09)], "white", center=(xm, ym, 0.58), axis=(0, 1, 0), n=8,
                      cap0="white", cap1="white"), mirror_y=True)


def build(kit):
    fuselage(kit)
    windows(kit)
    wings(kit)
    engines(kit)
    tail(kit)
    gear(kit)


VIEWS = [
    # The gate shot: behind and above, port (door) side.
    ("gate", (-34, 42, 24), (1, 0, 3)),
    ("front", (52, 30, 12), (0, 0, 3.5)),
    ("side", (0, 70, 5), (0, 0, 4.5)),
    ("top", (0, 0.01, 95), (0, 0, 0)),
    ("nose", (28, 10, 6), (16, 0, 3.6)),
    ("tail", (-30, 16, 12), (-15, 0, 7)),
]

K.run("aircraft_narrowbody", build, VIEWS)
