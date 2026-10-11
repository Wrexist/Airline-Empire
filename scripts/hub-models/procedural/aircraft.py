"""Hub_aircraft_<category>.usdz — every aircraft category (docs/HUB_MODEL_LIST.md §1).

One parametric airliner, tuned on the A320-class hero jet and scaled per
category: fuselage radius and gear height from HubModels.metrics, length
and span from HubAircraftEnvelope, engines exactly where
HubModels.enginePosition puts the focused jet's pulse rings, the forward
left door 13 % of the length behind the nose where the bridge docks.

  turboprop        ATR 72 class: high wing, prop discs, T-tail, gear sponsons
  regionalJet      E-Jet class: small winglets
  narrowbody       A320 class, the hero: sharklets
  largeNarrowbody  A321 class: stretched, four doors a side
  widebody         A330/787 class: bigger engines, four doors, four-wheel bogies
  largeWidebody    777-9 class: raked wingtips, six-wheel bogies

    blender --background --python scripts/hub-models/procedural/aircraft.py -- [--only narrowbody] --preview <dir>
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

SEG = 48     # fuselage segments round
SQUASH = 1.03

# length, model span (to the wingtip devices), app span (HubAircraftEnvelope),
# fuselage radius and gear height (HubModels.metrics), height to the fin tip.
CATEGORIES = {
    "turboprop": dict(L=27, span=27, app_span=27, r=1.35, gear=1.1, H=7.6, tip="none"),
    "regionalJet": dict(L=33, span=28, app_span=28, r=1.5, gear=1.125, H=9.9, tip="winglet"),
    "narrowbody": dict(L=38, span=35.8, app_span=35, r=2.0, gear=1.5, H=11.8, tip="sharklet"),
    "largeNarrowbody": dict(L=44.5, span=35.8, app_span=36, r=2.0, gear=1.5, H=11.8, tip="sharklet"),
    "widebody": dict(L=60, span=60, app_span=60, r=2.9, gear=2.175, H=17.3, tip="sharklet"),
    "largeWidebody": dict(L=70, span=65, app_span=65, r=3.2, gear=2.4, H=19.5, tip="raked"),
}

# Nose (distance behind the tip, radius fraction, centre offset) and tail cone
# (distance ahead of the tail end, ...), in units of the hero jet's 2 m radius.
NOSE = [(0.0, 0.03, -0.55), (0.05, 0.225, -0.5), (0.15, 0.36, -0.45), (0.30, 0.49, -0.4), (0.50, 0.61, -0.33),
        (0.75, 0.725, -0.25), (1.05, 0.815, -0.18), (1.40, 0.885, -0.12), (1.80, 0.94, -0.07),
        (2.25, 0.975, -0.03), (2.75, 0.995, -0.01), (3.30, 1.0, 0.0)]
TAIL = [(12.0, 1.0, 0.0), (10.5, 0.98, 0.07), (9.5, 0.94, 0.15), (8.5, 0.88, 0.25), (7.5, 0.815, 0.35),
        (6.5, 0.745, 0.45), (5.5, 0.67, 0.55), (4.5, 0.595, 0.65), (3.5, 0.515, 0.75), (2.5, 0.43, 0.84),
        (1.6, 0.335, 0.92), (0.8, 0.23, 0.99), (0.3, 0.15, 1.03), (0.0, 0.09, 1.05)]


class Plane:
    def __init__(self, name, L, span, app_span, r, gear, H, tip):
        self.name, self.L, self.span, self.app_span, self.r, self.gear, self.H, self.tip = \
            name, L, span, app_span, r, gear, H, tip
        self.k = r / 2.0                      # against the hero jet's radius
        self.axis = gear + r
        self.nose, self.tail = L / 2, -L / 2
        self.high = name == "turboprop"
        self.wide = name in ("widebody", "largeWidebody")
        prof = [(self.nose - d * self.k, f * r, self.axis + o * self.k) for d, f, o in NOSE]
        prof += [(self.tail + e * self.k, f * r, self.axis + o * self.k) for e, f, o in TAIL]
        self.profile = prof

    def skin(self, x):
        for (x0, r0, c0), (x1, r1, c1) in zip(self.profile, self.profile[1:]):
            if x1 <= x <= x0:
                t = (x0 - x) / (x0 - x1) if x0 != x1 else 0
                return r0 + (r1 - r0) * t, c0 + (c1 - c0) * t
        return (self.profile[0][1], self.profile[0][2]) if x > self.nose else (self.profile[-1][1], self.profile[-1][2])

    def on_skin(self, x, phi, off=0.03):
        r, cz = self.skin(x)
        return Vector((x, (r + off) * math.sin(phi), cz + (r * SQUASH + off) * math.cos(phi)))

    def phi_at(self, z, x=0.0):
        r, cz = self.skin(x)
        return math.acos(max(-1.0, min(1.0, (z - cz) / (r * SQUASH))))

    def axis_point(self, c):
        return Vector((c.x, 0, self.skin(c.x)[1]))

    def engine(self):
        """HubModels.enginePosition and the nacelle size, in this frame (+Y = port)."""
        L, r, cy = self.L, self.r, self.axis
        wing_y = cy + r * 0.85 if self.high else cy - r * 0.45
        root_le = L * 0.06 if self.high else L * 0.08
        semi = self.app_span / 2
        sweep = 0.06 if self.high else 0.55
        s = 0.36 if self.name == "largeWidebody" else (0.3 if self.high else 0.34)
        er = r * 0.42 if self.high else r * (0.48 if self.wide else 0.5)
        elen = L * 0.13 if self.high else L * (0.11 if self.wide else 0.12)
        e_le = root_le - semi * s * sweep + (L * 0.05 if self.high else L * 0.06)
        ey = wing_y - er * 0.2 if self.high else wing_y - er - 0.25
        return Vector((e_le - elen / 2, semi * s, ey)), er, elen


def patch(p, slot, x0, x1, p0, p1, nx=4, np_=4):
    rows = [[p.on_skin(x0 + (x1 - x0) * j / nx, p0 + (p1 - p0) * i / np_) for j in range(nx + 1)]
            for i in range(np_ + 1)]
    return K.Piece().grid(rows, slot).face_away_from(p.axis_point)


def pane(p, slot, corners, n=4):
    """Decal through four (x, phi) corners: fwd-inner, aft-inner, aft-outer, fwd-outer."""
    a, b, c, d = corners
    rows = []
    for i in range(n + 1):
        t = i / n
        lo = (a[0] + (d[0] - a[0]) * t, a[1] + (d[1] - a[1]) * t)
        hi = (b[0] + (c[0] - b[0]) * t, b[1] + (c[1] - b[1]) * t)
        rows.append([p.on_skin(lo[0] + (hi[0] - lo[0]) * j / n, lo[1] + (hi[1] - lo[1]) * j / n)
                     for j in range(n + 1)])
    return K.Piece().grid(rows, slot).face_away_from(p.axis_point)


def oval(p, slot, xc, pc, ax, az, n=12):
    r, _ = p.skin(xc)
    pts = [p.on_skin(xc + ax * math.cos(2 * math.pi * k / n), pc + (az / r) * math.sin(2 * math.pi * k / n))
           for k in range(n)]
    return K.Piece().fan(pts, slot).face_away_from(p.axis_point)


# ---- parts -----------------------------------------------------------------

def fuselage(kit, p):
    rings = []
    for x, r, cz in p.profile:
        rings.append([Vector((x, r * math.sin(t), cz + r * SQUASH * math.cos(t)))
                      for t in (2 * math.pi * k / SEG for k in range(SEG))])
    kit.add(K.Piece().loft(rings, "white", cap0="white", cap1="white").seal())
    tail_z = p.profile[-1][2]
    kit.add(kit.lathe([(0, 0.08 * p.r), (0.25 * p.k, 0.08 * p.r), (0.25 * p.k, 0.0)], "darkMetal",
                      center=(p.tail + 0.05, 0, tail_z), axis=(-1, 0, 0), n=10, cap0="darkMetal"))
    if p.high:
        # Main-gear sponsons low on each side, a fairing where the wing meets the roof.
        for side in (1, -1):
            rings = [kit.circle((x, side * p.r * 0.78, p.gear + 0.45), (1, 0, 0), 1.0, 16, scale=(0.55 * s, 0.5 * s))
                     for x, s in [(2.4, 0.0), (1.8, 0.75), (0.8, 1.0), (-2.2, 1.0), (-3.4, 0.7), (-4.2, 0.0)]]
            kit.add(K.Piece().loft(rings, "white").seal())
        wing_z = p.axis + p.r * 0.85
        rings = [kit.circle((x, 0, wing_z + 0.05), (1, 0, 0), 1.0, 16, scale=(0.32 * s, 0.75 * s))
                 for x, s in [(2.6, 0.0), (2.0, 0.8), (0.5, 1.0), (-1.4, 0.9), (-3.0, 0.0)]]
        kit.add(K.Piece().loft(rings, "white").seal())
        return
    # Belly fairing under the wing root.
    wy = p.span / 35.8
    xc = p.L * (0.5 / 38)
    rings = [kit.circle((xc + x * wy, 0, p.axis - 0.675 * p.r), (1, 0, 0), 1.0, 24, scale=(0.4 * p.r * s, 0.93 * p.r * s))
             for x, s in [(5.1, 0.05), (4.5, 0.55), (3.3, 0.88), (1.5, 1.0), (-2.0, 1.0), (-4.1, 0.88),
                          (-5.3, 0.55), (-5.9, 0.05)]]
    kit.add(K.Piece().loft(rings, "white", cap0="white", cap1="white").seal())


def doors(p):
    """Door stations (x) and the over-wing exits."""
    aft = p.tail + 11.4 * p.k
    fwd = p.nose - 0.13 * p.L
    if p.name in ("widebody", "largeWidebody"):
        return [fwd, p.nose - 0.3 * p.L, p.nose - 0.62 * p.L, aft], []
    if p.name == "largeNarrowbody":
        return [fwd, p.nose - 0.36 * p.L, p.nose - 0.62 * p.L, aft], []
    if p.name == "turboprop":
        return [fwd, aft], []
    mid = p.nose - 0.48 * p.L
    return [fwd, aft], ([mid] if p.name == "regionalJet" else [mid + 0.45, mid - 0.45])


def windows(kit, p):
    d = math.radians
    for s in (1, -1):  # Cockpit: four panes on the sloping crown of the nose.
        n = lambda dist: p.nose - dist * p.k  # noqa: E731
        kit.add(pane(p, "windowDark", [(n(0.62), s * d(1.2)), (n(1.5), s * d(1.2)), (n(1.62), s * d(34)),
                                       (n(0.78), s * d(37.5))]))
        kit.add(pane(p, "windowDark", [(n(0.85), s * d(40)), (n(1.67), s * d(36.5)), (n(2.35), s * d(66)),
                                       (n(1.45), s * d(76))]))
    main, exits = doors(p)
    pitch = max(0.6, 0.36 * p.r)
    size = max(0.8, p.k)
    first, last = p.nose - 0.16 * p.L, p.tail + 0.32 * p.L
    # No windows under the door outlines or the over-wing exits (their
    # frames sit at the same height off the skin and would flicker).
    gaps = [(x - 0.75 * size, x + 0.75 * size) for x in main] + [(x - 0.45, x + 0.45) for x in exits]
    phi = p.phi_at(p.axis + 0.45 * p.k)
    x = first
    while x >= last:
        if not any(a <= x <= b for a, b in gaps):
            for s in (1, -1):
                kit.add(oval(p, "windowDark", x, s * phi, 0.15 * size, 0.2 * size))
        x -= pitch
    w = 0.05
    outlines = [(x, 0.82, p.axis - 1.45 * p.k, p.axis + 0.45 * p.k) for x in main]
    outlines += [(x, 0.52, p.axis - 0.55 * p.k, p.axis + 0.65 * p.k) for x in exits]
    for s in (1, -1):
        for xc, width, z0, z1 in outlines:
            r, _ = p.skin(xc)
            pa, pb = s * p.phi_at(z1, xc), s * p.phi_at(z0, xc)
            dp = s * w / 2 / r
            x0, x1 = xc - width / 2, xc + width / 2
            for a, b, c, e, n in [(x0, x1, pa - dp, pa + dp, 1), (x0, x1, pb - dp, pb + dp, 1),
                                  (x0 - w / 2, x0 + w / 2, pa, pb, 3), (x1 - w / 2, x1 + w / 2, pa, pb, 3)]:
                kit.add(patch(p, "darkMetal", a, b, c, e, nx=1, np_=n))


def wing_sections(p):
    """Leading edge, chord, thickness, normal per section (port side)."""
    if p.high:
        z = p.axis + p.r * 0.85
        up = Vector((0, 0, 1))
        le = p.L * 0.06
        half = p.span / 2
        return [(Vector((le, 0.0, z)), 2.97, 0.45, up), (Vector((le - 0.15, half * 0.36, z)), 2.85, 0.42, up),
                (Vector((le - 0.35, half * 0.98, z + 0.08)), 1.55, 0.2, up)], ["white", "white"]
    wy = p.span / 35.8
    dih = math.radians(6 if p.wide else 5)
    up = Vector((0, -math.sin(dih), math.cos(dih)))
    root_x = p.L * (3.7 / 38) + 0.3 * (wy - 1)
    z0 = p.axis - 0.44 * p.r
    y0 = 0.75 * p.r
    base = [(3.7, 1.5, 6.8, 0.82), (1.26, 6.3, 5.06, 0.52), (-1.45, 11.6, 3.25, 0.32), (-4.15, 16.9, 1.5, 0.18)]
    secs = []
    for bx, by, chord, thick in base:
        y = y0 + (by - 1.5) * wy
        secs.append((Vector((root_x + (bx - 3.7) * wy, y, z0 + (y - y0) * math.tan(dih))), chord * wy, thick * wy, up))
    slots = ["white", "white", "white"]
    tip_le, tip_y, tip_z = secs[-1][0].x, secs[-1][0].y, secs[-1][0].z
    if p.tip in ("sharklet", "winglet"):
        g = wy * (1.0 if p.tip == "sharklet" else 0.7)
        secs += [(Vector((tip_le - 0.2 * g, tip_y + 0.55 * g, tip_z + 0.35 * g)), 1.3 * g, 0.15 * g, Vector((0, -0.7, 0.7))),
                 (Vector((tip_le - 0.6 * g, tip_y + 0.85 * g, tip_z + 1.0 * g)), 1.0 * g, 0.13 * g, Vector((0, -0.97, 0.25))),
                 (Vector((tip_le - 1.4 * g, tip_y + 1.0 * g, tip_z + 2.35 * g)), 0.55 * g, 0.1 * g, Vector((0, -1, 0.05)))]
        slots += ["livery", "livery", "livery"]
    elif p.tip == "raked":
        secs.append((Vector((tip_le - 2.2 * wy, p.span / 2, tip_z + 0.12)), 0.55 * wy, 0.08 * wy, up))
        slots.append("white")
    return secs, slots


def wings(kit, p):
    secs, slots = wing_sections(p)
    kit.add(kit.surface(secs, slots, n=20, cap0="white", cap1=slots[-1]), mirror_y=not p.high)
    if p.high:
        # One continuous wing: mirror the port half's sections for starboard.
        secs2 = [(Vector((le.x, -le.y, le.z)), c, t, nrm) for le, c, t, nrm in secs]
        kit.add(kit.surface(secs2, slots, n=20, cap0="white", cap1=slots[-1]))
        return
    wy = p.span / 35.8
    z0 = secs[0][0].z
    for frac in (0.17, 0.42, 0.66, 0.86):
        a, b = secs[0], secs[3]
        y = a[0].y + (b[0].y - a[0].y) * frac
        te = (a[0].x - a[1]) + ((b[0].x - b[1]) - (a[0].x - a[1])) * frac
        z = a[0].z + (b[0].z - a[0].z) * frac - 0.25 * wy
        kit.add(kit.lathe([(0, 0.0), (0.5 * wy, 0.17 * wy), (1.6 * wy, 0.2 * wy), (2.6 * wy, 0.12 * wy), (3.0 * wy, 0.0)],
                          "white", center=(te + 1.6 * wy, y, z), axis=(-1, 0, 0), n=8), mirror_y=True)


def wing_underside(p, y):
    secs, _ = wing_sections(p)
    for (a, ca, ta, _), (b, cb, tb, _) in zip(secs, secs[1:]):
        if a.y <= y <= b.y:
            t = (y - a.y) / (b.y - a.y)
            return a.z + (b.z - a.z) * t - (ta + (tb - ta) * t) / 2, a.x + (b.x - a.x) * t, ca + (cb - ca) * t
    a, c, th, _ = secs[0]
    return a.z - th / 2, a.x, c


def engines(kit, p):
    centre, er, elen = p.engine()
    y, zc = centre.y, centre.z
    k, f = er / 1.0, elen / 4.3
    xf = centre.x + 2.15 * f  # front of the lip
    if p.high:
        prof = [(0.0, 0.0), (0.0, 0.5 * k), (0.1 * f, 0.9 * k), (0.4 * f, 1.0 * k), (2.6 * f, 0.95 * k),
                (3.6 * f, 0.6 * k), (4.3 * f, 0.15 * k), (4.3 * f, 0.0)]
        kit.add(kit.lathe(prof, ["livery"] * 7, center=(xf, y, zc), axis=(-1, 0, 0), n=16), mirror_y=True)
        # Spinner and a dark six-blade propeller disc.
        kit.add(kit.lathe([(-0.55, 0.0), (-0.3, 0.2), (0.0, 0.3), (0.05, 0.0)], "white",
                          center=(xf, y, zc), axis=(-1, 0, 0), n=12), mirror_y=True)
        kit.add(kit.lathe([(-0.06, 0.0), (-0.06, p.r * 1.25), (0.06, p.r * 1.25), (0.06, 0.0)], "darkMetal",
                          center=(xf - 0.12, y, zc), axis=(-1, 0, 0), n=24), mirror_y=True)
        return
    prof = [(0.75 * f, 0.0), (0.75 * f, 0.82 * k), (0.06 * f, 0.86 * k), (0.0, 0.94 * k), (0.08 * f, 1.03 * k),
            (0.3 * f, 1.08 * k), (1.3 * f, 1.12 * k), (3.0 * f, 1.06 * k), (3.8 * f, 0.88 * k), (4.3 * f, 0.64 * k),
            (4.3 * f, 0.0)]
    slots = ["darkMetal", "white", "white", "white", "white", "livery", "livery", "livery", "livery", "darkMetal"]
    kit.add(kit.lathe(prof, slots, center=(xf, y, zc), axis=(-1, 0, 0), n=24), mirror_y=True)
    kit.add(kit.lathe([(0.45 * f, 0.0), (0.75 * f, 0.26 * k), (0.76 * f, 0.0)], "white",
                      center=(xf, y, zc), axis=(-1, 0, 0), n=12), mirror_y=True)
    kit.add(kit.lathe([(4.3 * f, 0.5 * k), (5.0 * f, 0.0)], "darkMetal", center=(xf, y, zc), axis=(-1, 0, 0), n=12,
                      cap0="darkMetal"), mirror_y=True)
    under, _, _ = wing_underside(p, y)
    top = zc + 0.9 * k
    rings = []
    for le, chord, z in [(xf - 0.5 * f, 3.6 * f, top - 0.2), (xf - 1.2 * f, 3.4 * f, under + 0.25)]:
        rings.append([Vector((le - u * chord, y + t * 0.32 * k, z)) for u, t in kit.airfoil(12)])
    kit.add(K.Piece().loft(rings, "white", cap0="white", cap1="white").seal(), mirror_y=True)


def tail(kit, p):
    tail_top = p.axis + 0.65 * p.r
    if p.high:
        z_base, fin_top = p.axis + 0.6 * p.r, p.H
    else:
        z_base, fin_top = tail_top, p.H
    f = (fin_top - z_base) / 7.0
    side = Vector((0, 1, 0))
    fin = [(Vector((p.tail + 8.8 * f, 0, z_base)), 7.4 * f, 0.55 * f, side),
           (Vector((p.tail + 6.9 * f, 0, z_base + 1.1 * f)), 5.6 * f, 0.5 * f, side),
           (Vector((p.tail + 4.9 * f, 0, z_base + 4.1 * f)), 3.8 * f, 0.36 * f, side),
           (Vector((p.tail + 2.9 * f, 0, fin_top)), 2.0 * f, 0.22 * f, side)]
    if p.high:  # T-tail: an upright, less swept fin
        fin = [(Vector((p.tail + 6.6 * f, 0, z_base)), 5.6 * f, 0.5 * f, side),
               (Vector((p.tail + 4.6 * f, 0, z_base + 1.0 * f)), 3.9 * f, 0.45 * f, side),
               (Vector((p.tail + 2.9 * f, 0, fin_top)), 2.4 * f, 0.3 * f, side)]
    piece = kit.surface(fin, "livery", n=20, cap0="livery", cap1="livery")
    n = Vector((0.9, 0, 1.0)).normalized()
    p0 = Vector((p.tail + 6.1 * f, 0, z_base + 1.5 * f))
    piece.bisect(p0, n).bisect(p0 + n * 1.25 * f, n)
    piece.retag(lambda c: 0 < (c - p0).dot(n) < 1.25 * f, "liveryAccent")
    kit.add(piece.seal())
    # Horizontal stabilisers (on the fin's tip for the T-tail).
    semi = 0.173 * p.span
    sp = semi / 6.2
    dih = math.radians(0 if p.high else 6)
    up = Vector((0, -math.sin(dih), math.cos(dih)))
    if p.high:
        x_root, z_root = fin[-1][0].x + 0.6, fin_top - 0.15
    else:
        x_root, z_root = p.tail + 6.0 * p.k, p.axis + 0.25 * p.r
    c = 0.75 if p.high else 1.0  # the T-tail's stabiliser is shallower
    hs = [(Vector((x_root, 0.3 * p.k, z_root)), 3.7 * sp * c, 0.4 * sp, up),
          (Vector((x_root - 3.55 * sp * c, semi, z_root + (semi - 0.3) * math.tan(dih))), 1.3 * sp * c, 0.16 * sp, up)]
    kit.add(kit.surface(hs, "white", n=16, cap0="white", cap1="white"), mirror_y=True)


def gear(kit, p):
    def strut(x, y, z0, z1, rad):
        return kit.lathe([(z0, rad), (z1, rad)], "white", center=(x, y, 0), axis=(0, 0, 1), n=8,
                         cap0="white", cap1="white")

    def axle(x, y, half, z, rad=0.06):
        return kit.lathe([(-half, rad), (half, rad)], "white", center=(x, y, z), axis=(0, 1, 0), n=8,
                         cap0="white", cap1="white")

    rn = 0.19 * p.r
    xn = p.nose - 0.134 * p.L
    for y in (0.14 * p.r, -0.14 * p.r):
        kit.add(kit.wheel(xn, y, rn, 0.13 * p.r, n=14))
    kit.add(strut(xn, 0, rn * 0.5, p.gear + 0.25, 0.045 * p.r))
    kit.add(axle(xn, 0, 0.21 * p.r, rn))
    rm = 0.29 * p.r
    if p.high:
        xm, ym = -0.6, p.r * 0.78
        for x in (xm + 0.55, xm - 0.55):
            kit.add(kit.wheel(x, ym, 0.42, 0.3, n=14), mirror_y=True)
        return
    xm, ym = -0.042 * p.L, 1.9 * p.r
    under, _, _ = wing_underside(p, ym)
    axles = [0.0] if not p.wide else ([-0.85, 0.85] if p.name == "widebody" else [-1.5, 0.0, 1.5])
    rm = 0.29 * p.r if not p.wide else 0.21 * p.r
    for dx in axles:
        for dy in (-0.45 * p.k, 0.45 * p.k):
            kit.add(kit.wheel(xm + dx, ym + dy, rm, 0.2 * p.r, n=14), mirror_y=True)
        kit.add(axle(xm + dx, ym, 0.65 * p.k, rm, 0.045 * p.r), mirror_y=True)
    if p.wide:
        kit.add(kit.beam((xm + axles[0], ym, rm), (xm + axles[-1], ym, rm), 0.12 * p.r, 0.1 * p.r, "white"),
                mirror_y=True)
    kit.add(strut(xm, ym, rm * 0.5, under + 0.2, 0.07 * p.r), mirror_y=True)


def builder(p):
    def build(kit):
        fuselage(kit, p)
        windows(kit, p)
        wings(kit, p)
        engines(kit, p)
        tail(kit, p)
        gear(kit, p)
    return build


def views(p):
    s = p.L / 38
    return [("gate", (-34 * s, 42 * s, 24 * s), (1, 0, 3 * s)), ("front", (52 * s, 30 * s, 12 * s), (0, 0, p.axis)),
            ("side", (0, 70 * s, 5 * s), (0, 0, p.axis + 1)), ("cockpit", (p.nose + 11 * p.k, 9 * p.k, p.axis + 4 * p.k),
                                                                   (p.nose - 1.5 * p.k, 0, p.axis + 0.7 * p.k))]


if __name__ == "__main__":  # importable by inspector_renders.py
    only = None
    if "--only" in sys.argv:
        i = sys.argv.index("--only")
        only = sys.argv[i + 1]
        del sys.argv[i:i + 2]
    for name, spec in CATEGORIES.items():
        if only and name != only:
            continue
        plane = Plane(name, **spec)
        K.run(f"aircraft_{name}", builder(plane), views(plane))
