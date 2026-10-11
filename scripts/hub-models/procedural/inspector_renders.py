"""Soft studio renders of every aircraft category for the inspector card (gap F1).

The reference's inspector shows a rendered jet, not a drawing. For each
category this renders the authored airliner (aircraft.py) three times from
the same camera, on a transparent background:

  HubJet_<category>          shaded, livery parts in white
  HubJet_<category>_livery   mask of the livery parts (fin, nacelles, sharklets)
  HubJet_<category>_accent   mask of the accent flash

The app multiplies the airline's colours through the masks
(HubAircraftProfile), so every airline's jet shows in its own livery.
Writes image sets into AirlineEmpireApp/Resources/Assets.xcassets.

    blender --background --factory-startup --python scripts/hub-models/procedural/inspector_renders.py
    python scripts/hub-models/procedural/inspector_renders.py --post   # masks -> alpha (needs Pillow)
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
ASSETS = os.path.join(ROOT, "AirlineEmpireApp", "Resources", "Assets.xcassets")
W, H = 840, 360  # @2x for a ~420 x 180 pt card
SUFFIXES = ("", "_livery", "_accent")


def imageset(name):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "Contents.json"), "w", newline="\n") as f:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "2x"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    return os.path.join(folder, f"{name}.png")


def post():
    """Turn the white-on-black masks into white images with luminance as alpha."""
    from PIL import Image
    for entry in sorted(os.listdir(ASSETS)):
        if not entry.startswith("HubJet_") or not entry.endswith(("_livery.imageset", "_accent.imageset")):
            continue
        name = entry[:-len(".imageset")]
        path = os.path.join(ASSETS, entry, f"{name}.png")
        im = Image.open(path).convert("RGBA")
        lum = im.convert("L")
        alpha = Image.composite(lum, Image.new("L", im.size, 0), im.split()[3])
        out = Image.new("RGBA", im.size, (255, 255, 255, 0))
        out.putalpha(alpha)
        out.save(path, optimize=True)
        print("mask", name)


def render_all():
    import bpy
    from mathutils import Vector
    sys.path.insert(0, HERE)
    import kit as K
    import aircraft as A

    for name, spec in A.CATEGORIES.items():
        plane = A.Plane(name, **spec)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        kit = K.Kit()
        A.builder(plane)(kit)
        objs = kit.objects(f"aircraft_{name}")
        for o in objs:
            bpy.context.view_layer.objects.active = o
            for other in bpy.context.scene.objects:
                other.select_set(other is o)
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
        scene = bpy.context.scene
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.render.film_transparent = True
        scene.render.resolution_x, scene.render.resolution_y = W, H
        scene.display.shading.color_type = "MATERIAL"
        # Camera: the starboard side from slightly ahead and above, nose to the right.
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = max(plane.L, plane.span * 0.8) * 1.22
        scene.collection.objects.link(cam)
        scene.camera = cam
        target = Vector((plane.L * 0.02, 0, plane.H * 0.5))
        cam.location = target + Vector((0.42, -1.0, 0.36)).normalized() * 200
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.clip_end = 1000

        def paint(rule):
            for o in objs:
                o.data.materials[0].diffuse_color = rule(o.name.removeprefix("ae_"))

        palette = K.MANIFEST["palette"]

        def srgb(h):
            import clean_model
            return (*[clean_model.srgb_to_linear(c) for c in clean_model.hex_rgb(h)], 1)

        passes = {
            # Shaded, livery parts white so the tint multiplies over them.
            "": (lambda s: srgb("#FFFFFF") if s in ("livery", "liveryAccent") else srgb(palette[s]), "STUDIO", True),
            "_livery": (lambda s: (1, 1, 1, 1) if s == "livery" else (0, 0, 0, 1), "FLAT", False),
            "_accent": (lambda s: (1, 1, 1, 1) if s == "liveryAccent" else (0, 0, 0, 1), "FLAT", False),
        }
        for suffix, (rule, light, soft) in passes.items():
            paint(rule)
            sh = scene.display.shading
            sh.light = light
            sh.show_shadows = soft
            sh.show_cavity = soft
            sh.show_specular_highlight = soft
            sh.show_object_outline = False
            scene.view_settings.view_transform = "Standard"
            scene.view_settings.exposure = 0.75 if soft else 0.0  # white reads white, like the clay world
            scene.render.filepath = imageset(f"HubJet_{name}{suffix}")
            bpy.ops.render.render(write_still=True)
        print("rendered", name)


if "--post" in sys.argv:
    post()
else:
    render_all()
