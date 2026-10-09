"""Check Hub View models against the spec before they ship.

usage: check_usdz.py [files or folders...]   (default: AirlineEmpireApp/Resources/HubModels)
needs:  pip install usd-core

Checks every Hub_<slot>.usdz against manifest.json (docs/HUB_MODEL_LIST.md):
  - the file name is a known slot;
  - Y-up, metres;
  - real-world size within tolerance on every axis the manifest gives
    (x = length/forward, y = height, z = width);
  - pivot: sits on the ground (min y ~ 0) and is centred on the footprint;
  - faces +X: longer along x than z for aircraft and vehicles;
  - triangle count inside the budget (over budget fails, under warns);
  - prims named ae_<slot> use only known slots and include the required ones;
  - no texture larger than 512 px, and no textures at all on most models.
Exit status 1 if anything fails, so CI can gate on it.
"""
import glob
import json
import os
import sys
import zipfile

from pxr import Gf, Usd, UsdGeom, UsdShade

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
KNOWN_SLOTS = {"white", "livery", "liveryAccent", "windowDark", "window", "glass", "building",
               "buildingShade", "roof", "houseRoof", "houseWood", "wood", "darkMetal", "metal",
               "tyre", "tire", "hiVis", "cone", "cloth", "skin", "screen", "lamp", "water", "tree",
               "trunk", "grass", "grassBright", "concrete", "marking"}  # HubAssetLibrary.key(forPrim:)


def slot_of(prim_name):
    if not prim_name.startswith("ae_"):
        return None
    return prim_name[3:].split("_")[0]


def check(path, manifest):
    errors, warnings = [], []
    name = os.path.basename(path)
    slot = name.removeprefix("Hub_").removesuffix(".usdz")
    spec = manifest["models"].get(slot)
    if spec is None:
        return [f"unknown slot '{slot}' (not in manifest.json)"], [], {}

    try:
        stage = Usd.Stage.Open(path)
    except Exception as error:  # pxr raises Tf.ErrorException
        return [f"cannot open: {str(error).strip().splitlines()[-1]}"], [], {}
    if stage is None:
        return ["cannot open"], [], {}
    if UsdGeom.GetStageUpAxis(stage) != UsdGeom.Tokens.y:
        errors.append(f"up axis is {UsdGeom.GetStageUpAxis(stage)}, needs Y")
    mpu = UsdGeom.GetStageMetersPerUnit(stage)
    if abs(mpu - 1.0) > 1e-6:
        errors.append(f"metersPerUnit is {mpu}, needs 1")

    cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_, UsdGeom.Tokens.render])
    box = cache.ComputeWorldBound(stage.GetPseudoRoot()).ComputeAlignedRange()
    lo, hi = box.GetMin(), box.GetMax()
    ext = hi - lo
    size = {"x": ext[0] * mpu, "y": ext[1] * mpu, "z": ext[2] * mpu}

    tol = manifest.get("tolerance", 0.12)
    for axis, want in spec["size_m"].items():
        if want and abs(size[axis] - want) > want * tol:
            errors.append(f"{axis} size {size[axis]:.2f} m, spec {want} m (±{tol:.0%})")
    if abs(lo[1]) > max(0.05, ext[1] * 0.02):
        errors.append(f"not on the ground: min y = {lo[1]:.2f}")
    cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
    if abs(cx) > ext[0] * 0.05 or abs(cz) > ext[2] * 0.05:
        errors.append(f"pivot not centred on the footprint (centre at x {cx:.2f}, z {cz:.2f})")
    if spec["class"] in ("aircraft", "vehicle") and size["x"] < size["z"] * 0.9:
        errors.append("front does not face +X (shorter along x than z)")

    tris, slots_seen, untagged = 0, set(), 0
    for prim in stage.Traverse():
        if prim.IsA(UsdGeom.Mesh):
            counts = UsdGeom.Mesh(prim).GetFaceVertexCountsAttr().Get() or []
            n = sum(max(c - 2, 0) for c in counts)
            tris += n
            tagged = None
            p = prim
            while p and p.GetPath() != p.GetPath().absoluteRootPath:
                tagged = slot_of(p.GetName())
                if tagged:
                    break
                p = p.GetParent()
            if tagged:
                slots_seen.add(tagged)
            else:
                untagged += n
        s = slot_of(prim.GetName())
        if s and s not in KNOWN_SLOTS:
            errors.append(f"prim {prim.GetPath()} uses unknown slot '{s}'")
    lo_t, hi_t = spec["triangles"]
    if tris > hi_t:
        errors.append(f"{tris} triangles, budget {lo_t}-{hi_t}")
    elif tris < lo_t * 0.5:
        warnings.append(f"only {tris} triangles (budget {lo_t}-{hi_t}); check detail")
    missing = [s for s in spec.get("required_slots", []) if s not in slots_seen]
    if missing:
        errors.append(f"missing required slot prims: {', '.join('ae_' + s for s in missing)}")
    extra = slots_seen - set(spec["slots"]) - {"window", "wood", "metal", "tire"}
    if extra:
        warnings.append(f"slots not listed for this model: {', '.join(sorted(extra))}")
    if tris and untagged / tris > 0.15 and spec["class"] != "vehicle":
        warnings.append(f"{untagged / tris:.0%} of triangles are not under an ae_ prim (keep authored colour)")

    with zipfile.ZipFile(path) as z:
        images = [i for i in z.infolist() if i.filename.lower().endswith((".png", ".jpg", ".jpeg"))]
    if images:
        try:
            from PIL import Image
            for info in images:
                with zipfile.ZipFile(path) as z, z.open(info) as f:
                    w, h = Image.open(f).size
                if max(w, h) > 512:
                    errors.append(f"texture {info.filename} is {w}x{h}, max 512")
        except ImportError:
            warnings.append("Pillow missing; texture sizes not checked")
        if spec["class"] in ("aircraft", "person", "tree"):
            warnings.append(f"{len(images)} textures; this class should be flat colour only")

    facts = {"size_m": {k: round(v, 2) for k, v in size.items()}, "triangles": tris,
             "slots": sorted(slots_seen), "textures": len(images)}
    return errors, warnings, facts


def main():
    manifest = json.load(open(os.path.join(HERE, "manifest.json")))
    targets = sys.argv[1:] or [os.path.join(ROOT, "AirlineEmpireApp", "Resources", "HubModels")]
    files = []
    for t in targets:
        files += sorted(glob.glob(os.path.join(t, "Hub_*.usdz"))) if os.path.isdir(t) else [t]
    if not files:
        print("no Hub_*.usdz models to check")
        return 0
    failed = 0
    for f in files:
        errors, warnings, facts = check(f, manifest)
        status = "FAIL" if errors else "ok"
        print(f"{status:4} {os.path.basename(f)} {json.dumps(facts)}")
        for e in errors:
            print(f"     error: {e}")
        for w in warnings:
            print(f"     warn:  {w}")
        failed += bool(errors)
    print(f"{len(files) - failed}/{len(files)} models pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
