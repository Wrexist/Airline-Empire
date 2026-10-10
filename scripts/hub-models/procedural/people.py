"""Hub_person_*.usdz — passengers a–d and the ground crew (docs/HUB_MODEL_LIST.md §3).

Slightly stylised adults, 1.75 m, facing +X; the app draws them 1.8–2× and
recolours `ae_cloth` per person (and `ae_skin`). One shared body —
capsule limbs, a lofted torso, an egg head with a cap of hair — dressed
and posed per variant:

  a  jacket, walking, pulling a rolling suitcase
  b  long coat, standing, shoulder bag, longer hair
  c  hoodie with the hood down, backpack
  d  shirt, reaching forward to a kiosk screen
  crew  dark overalls, hi-vis vest, ear defenders

Writes all five files:

    blender --background --python scripts/hub-models/procedural/people.py -- --preview <dir>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit as K  # noqa: E402
from mathutils import Vector  # noqa: E402

SHOULDER = 1.4


def torso(kit, slot, rings):
    loops = [kit.circle((0, 0, z), (0, 0, 1), 1.0, 12, start=(1, 0, 0), scale=(rx, ry)) for z, rx, ry in rings]
    return K.Piece().loft(loops, slot, cap0=slot, cap1=slot).seal()


def body(kit, top="cloth", legs="darkMetal", arms=None, stride=0.0, reach=None, swing=0.0,
         right_hand=None, coat=False, hair="short"):
    """The shared figure. `stride` puts the left foot forward and the right back;
    `swing` the opposite for the arms; `reach`/`right_hand` place the right hand."""
    arms = arms or top
    for side, step in ((1, stride), (-1, -stride)):
        hip = Vector((0, side * 0.1, 0.93))
        ankle = Vector((step, side * 0.11, 0.11))
        kit.add(kit.limb(hip, ankle, 0.085, 0.058, legs))
        kit.add(kit.ellipsoid((step + 0.05, side * 0.11, 0.055), (0.125, 0.055, 0.055), "darkMetal", n=8, rings=4))
    kit.add(torso(kit, top, [(0.86, 0.12, 0.17), (0.96, 0.13, 0.18), (1.1, 0.12, 0.165), (1.28, 0.13, 0.19),
                             (1.4, 0.12, 0.21), (1.46, 0.08, 0.14), (1.485, 0.02, 0.03)]))
    if coat:
        kit.add(torso(kit, top, [(0.5, 0.15, 0.19), (0.7, 0.14, 0.185), (0.9, 0.13, 0.18)]))
    for side in (1, -1):
        shoulder = Vector((0, side * 0.21, SHOULDER))
        if side == -1 and right_hand is not None:
            hand = Vector(right_hand)
        else:
            hand = Vector((-side * swing if stride else 0.02, side * 0.25, 0.86))
        kit.add(kit.limb(shoulder, hand, 0.056, 0.045, arms))
        kit.add(kit.ellipsoid(hand + (hand - shoulder).normalized() * 0.04, (0.045, 0.035, 0.055), "skin",
                              n=8, rings=4))
    kit.add(kit.limb((0, 0, 1.44), (0, 0, 1.53), 0.05, 0.05, "skin", n=8))
    kit.add(kit.ellipsoid((0.012, 0, 1.63), (0.1, 0.09, 0.115), "skin", n=12, rings=7))
    if hair != "none":  # the crew's cap covers it
        kit.add(kit.ellipsoid((-0.012, 0, 1.672), (0.1, 0.095, 0.083), "darkMetal", n=12, rings=5))
    if hair == "long":
        kit.add(kit.ellipsoid((-0.05, 0, 1.56), (0.07, 0.095, 0.12), "darkMetal", n=10, rings=5))


def passenger_a(kit):
    kit.recentre = True
    kit.smooth = 70
    body(kit, stride=0.17, swing=0.14, right_hand=(-0.18, -0.27, 0.86))
    # Rolling suitcase trailing behind the right hand.
    kit.add(K.Piece().box((-0.43, -0.3, 0.37), (0.24, 0.4, 0.58), "darkMetal", bevel=0.05, segments=1).seal())
    kit.add(kit.beam((-0.36, -0.3, 0.66), (-0.2, -0.28, 0.85), 0.03, 0.03, "darkMetal"))


def passenger_b(kit):
    kit.recentre = True
    kit.smooth = 70
    body(kit, coat=True, hair="long")
    # Shoulder bag on the left hip, strap to the right shoulder.
    kit.add(K.Piece().box((0.02, 0.25, 0.98), (0.22, 0.08, 0.18), "darkMetal", bevel=0.03, segments=1).seal())
    kit.add(kit.beam((0.02, 0.24, 1.07), (0.0, -0.17, 1.44), 0.035, 0.02, "darkMetal", side=(1, 0, 0)))


def passenger_c(kit):
    kit.recentre = True
    kit.smooth = 70
    body(kit)
    kit.add(kit.ellipsoid((-0.09, 0, 1.46), (0.08, 0.14, 0.07), "cloth", n=10, rings=4))
    kit.add(K.Piece().box((-0.2, 0, 1.17), (0.16, 0.3, 0.4), "darkMetal", bevel=0.05, segments=1).seal())


def passenger_d(kit):
    kit.recentre = True
    kit.smooth = 70
    body(kit, right_hand=(0.4, -0.17, 1.24))


def crew(kit):
    kit.recentre = True
    kit.smooth = 70
    body(kit, top="darkMetal", legs="darkMetal", arms="darkMetal", hair="none")
    # Hi-vis vest over the overalls, no sleeves.
    kit.add(torso(kit, "hiVis", [(0.98, 0.14, 0.19), (1.1, 0.135, 0.18), (1.28, 0.145, 0.2), (1.38, 0.135, 0.2)]))
    # Ear defenders and their band; a cloth cap.
    for side in (1, -1):
        kit.add(kit.ellipsoid((0.0, side * 0.095, 1.625), (0.04, 0.03, 0.045), "darkMetal", n=8, rings=4))
    kit.add(kit.limb((0, 0.09, 1.66), (0, -0.09, 1.66), 0.02, 0.02, "darkMetal", n=6))
    kit.add(kit.ellipsoid((0.0, 0, 1.69), (0.105, 0.098, 0.07), "cloth", n=12, rings=4))


VIEWS = [("front", (4.4, 2.6, 1.6), (0, 0, 0.88)), ("side", (0, 5.0, 1.0), (0, 0, 0.88))]

for slot, build in [("person_passenger_a", passenger_a), ("person_passenger_b", passenger_b),
                    ("person_passenger_c", passenger_c), ("person_passenger_d", passenger_d),
                    ("person_crew", crew)]:
    K.run(slot, build, VIEWS)
