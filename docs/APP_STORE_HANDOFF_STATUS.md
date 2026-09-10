# App Store handoff — checked 2026-09-09

Historical snapshot. The 10 September continuation can access Apple and has
saved privacy URLs, created the three Pro products and checked active agreements.
Use the [release plan](RELEASE_PLAN.md) and [checklist](../tasks/RELEASE_CHECKLIST.md)
for current release work. The approved launch scope is now 173 regions,
excluding China mainland and Vietnam; the 16 October date is unchanged.

The repository assets and English copy are ready. Apple account completion is in progress; this is not a claim that a release has been approved or device-tested.

## Completed

- Six screenshot designs in three sizes: 18 unique RGB PNGs, mirrored for US/UK.
- All exports decode, match the native sources and meet dimensions/no-alpha requirements.
- New player-focused English descriptions, subtitle, promotional text and relevant search keywords within Apple limits.
- Verified Isac Molin review contact and copyright; no contact placeholders remain.
- Public support, privacy, terms and press website published at https://airline-empire-official.isacmolin.chatgpt.site. The deployment reports success and public access. This execution environment cannot independently fetch the public host (network restriction); no HTTP-200 verification is claimed.
- US and UK version copy, review notes and contact saved in App Store Connect.
- Pre-order date changed from 11 September to 16 October 2026 in all 175 regions, verified in Apple's availability table. Pre-order is pending review/publication, not yet live.
- 48 release-tooling tests passing, listing validation and generated copy sheet passing.

## Verified Apple account edits

- US screenshots: six in the 6.9-inch display slot (1320×2868), six in 6.5-inch (1242×2688), six in iPad 13-inch (2064×2752).
- UK screenshots: six in 6.5-inch and six in iPad 13-inch; the largest iPhone slot explicitly inherits the identical US 6.9-inch set.
- All five uploaded sets were reordered and their actual visible sequence checked: network, fleet, routes, finance, rivals, progression.
- Both localized subtitles saved: Offline Fleet & Route Manager.
- Categories already correctly set to Games / Simulation / Strategy; existing general age rating shows 4+ with regional exceptions; trader status was present.
- Content Rights: the affirmative rights declaration for third-party content was selected and saved, reflecting the bundled public-domain Natural Earth map. Recheck persistence when Apple access resumes; navigation timed out after Save.

## Blocked by Apple browser connection

The signed-in browser stopped responding with CDP timeouts. A fresh-tab recovery failed too. No final success is claimed for these remaining actions:

- Set the **App Privacy policy URL** to the new privacy page in both locales. Descriptions and support/marketing fields already contain the new host; the separate App Privacy field still needs a save.
- Verify the existing privacy nutrition-label answers against the current build.
- Submit the [prepared featuring nomination](APP_STORE_FEATURING_NOMINATION.md).
- Verify the app is priced Free, all three Pro purchase records, regional requirements and the latest TestFlight build.

## Release gates

- Build: no build was attached to version 1.0 when checked. The new in-game support links require a new build.
- Verify the three actual Pro products, subscription prices/introductory offer and genuine paywall review screenshot. The marketing gallery is not an IAP review screenshot.
- Run the required CI/full-device and launch-safety workflows on the exact intended release commit; attach and test the processed TestFlight build.
- Complete applicable Apple account declarations and first-IAP submission. Apple approval is still required before pre-order publication.

See [release setup](RELEASE_SETUP.md) and the [copy/paste sheet](APP_STORE_CONNECT_FILL_IN.md). Do not treat a checked-in plan as an Apple action. The latest known successful TestFlight workflow is 34027843211 on older commit e3d15e69da14ae31a1e2f08afbad94fa9939d9ec; it is not evidence for this updated release.
