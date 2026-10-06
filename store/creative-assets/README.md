# App Store creative assets — Header and Search Results

For **App Store Connect → Product Page → Header and Search Results**.

| File | Placement | Size | Source art |
|------|-----------|------|------------|
| `header.png` | Product page header | 3840 × 1646 (21:9) | `artwork/cinematic/06-progression.png` |
| `search-results.png` | Search results | 3840 × 2560 (3:2) | `artwork/cinematic/01-network.png` |

- Opaque RGB PNG, no alpha.
- **No text, logos, prices or URLs.** The App Store sets the icon, name and Get
  button around the art itself, and a text-free image works in every locale.
- The aircraft stays inside Apple's centred art-safe area (header x 520–3320).
  Soft navy gradients at the top and bottom keep App Store UI legible.
- The source art is 1536 × 1024. It is upscaled 4× with Real-ESRGAN, then
  resampled down, so the final images are sharp at full size rather than
  stretched. Re-render with `render.py` (instructions in its header).

## Upload

1. App Store Connect → the app → **Header and Search Results**.
2. **Header** tab → **Upload** → `header.png`.
3. **Search Results** tab → **Upload** → `search-results.png`.
4. Use **Preview** to check the iPhone and iPad crops, then submit with the
   next version. The assets go through App Review.
