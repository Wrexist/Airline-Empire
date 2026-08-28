# App resources

## `PrivacyInfo.xcprivacy`

Apple's privacy manifest, required for App Store submission. It declares no
tracking, no collected data and no required-reason API use — all three derived
from the code, not from a template. Read the comment inside it before changing
anything: if one of those three facts stops being true, the file changes in the
same commit as the code that changed it.

## `Assets.xcassets`

**The app icon is missing, and it is a release blocker.** The catalogue and the
`AppIcon` set exist so the build setting resolves and the project generates,
but the 1024×1024 image itself is not here: nobody has drawn it, and inventing
one is not something an agent session should do on the project's behalf.

What the slot needs: a single 1024×1024 PNG, **no alpha channel** (Apple
flattens transparency to black), no rounded corners of its own (the system
masks it), and legible at 60 points — which is where most airline icons fail,
because a detailed aircraft silhouette becomes a smudge.

`docs/ASO.md` carries the icon brief: what it should say, what the category's
icons already look like, and what to avoid. Drop the finished PNG in as
`AppIcon.appiconset/icon-1024.png` and add its `"filename"` to
`Contents.json`.

Until then: the app compiles and runs, and an App Store submission is rejected
at validation with a missing-icon error. `xcrun altool --validate-app` in the
release workflow is what reports it, before the upload rather than after.
