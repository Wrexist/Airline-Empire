# Screenshots

Empty, and blocking a submission. They need a simulator, and therefore a Mac.

## Layout

```
screenshots/<locale>/<APP_STORE_CONNECT_DISPLAY_TYPE>/01-map.png
```

The directory name is the App Store Connect `screenshotDisplayType` enum value
and is passed to the API verbatim — no mapping table in this repository can go
stale that way. The two required today, from `config.json`:

| Directory | Canvas | Device |
|---|---|---|
| `APP_IPHONE_67` | 1320×2868 (or 1290×2796) | iPhone 6.9" / 6.7" |
| `APP_IPAD_PRO_3GEN_129` | 2064×2752 (or 2048×2732) | iPad 13" / 12.9" |

Sizes read off Apple's screenshot specification on 2026-08-07. Apple revises
them most years and a guessed dimension is a rejected submission — re-verify
before the first upload.

Files upload in **filename order**, which is the order they appear on the
product page, so the numeric prefix is the storyboard.

## Rules

- PNG, **no alpha channel** (Apple rejects transparency; the validator catches it first).
- At most ten per display type per locale.
- Captured from a **real mid-game world**, one seed, one airline, across all six.
- Caption text legible at gallery-thumbnail size.
- Nothing on screen the app cannot actually do.

The six shots, what each one has to prove, and the captions:
[`docs/ASO.md`](../../docs/ASO.md) §5.
