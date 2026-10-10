# Hub View model tools

See [docs/HUB_MODEL_PIPELINE.md](../../docs/HUB_MODEL_PIPELINE.md).

- `manifest.json` — spec per model (size, budget, slots), mirrors docs/HUB_MODEL_LIST.md
- `clean_model.py` — generated GLB → `Hub_<slot>.usdz` (run in Blender or with `pip install bpy`, Python 3.11)
- `check_usdz.py` — validate models (`pip install usd-core pillow`); CI: `.github/workflows/hub-models.yml`
