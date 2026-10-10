# Hub View model tools

See [docs/HUB_MODEL_PIPELINE.md](../../docs/HUB_MODEL_PIPELINE.md).

- `manifest.json` — spec per model (size, budget, slots), mirrors docs/HUB_MODEL_LIST.md
- `clean_model.py` — generated GLB → `Hub_<slot>.usdz` (run in Blender or with `pip install bpy`, Python 3.11)
- `procedural/` — models built from code in Blender (free, no generator): `kit.py` plus one script per
  model, e.g. `blender --background --python procedural/aircraft_narrowbody.py -- --preview <dir>`
- `check_usdz.py` — validate models (`pip install usd-core pillow`); CI: `.github/workflows/hub-models.yml`
