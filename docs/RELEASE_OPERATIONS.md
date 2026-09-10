# Launch monitoring and a save-safe hotfix

Release owner: Isac Molin. The current release identity and evidence belong in
[RELEASE_CONTINUATION_STATUS.md](RELEASE_CONTINUATION_STATUS.md).

## Before submitting

Record the accepted Git SHA, marketing version/build, App Store build ID,
archive/upload run and Apple processing result. Keep the downloaded IPA,
dSYMs, native test results and device acceptance notes together. GitHub's
current IPA artifact expires after 14 days, before the planned 16 October
launch; download it to durable release storage. dSYMs have 90-day retention.
Do not rely on the shorter IPA retention as the only binary copy.

Inspect the actual exported IPA before App Review: its bundle ID must be
`com.airlineempire.game`; version/build must match the record; iPhone/iPad
device families and orientations must be present; the packaged privacy
manifest must retain the declared UserDefaults reason and no tracking/data
collection; no StoreKit test configuration belongs in the shipping app.
Retain the resulting inspection report with the binary hash.

Signing preflight on 10 September reached the Developer portal, found the
registered bundle and one usable App Store profile. Its certificate-count
warning also appeared with the same three live certificates in the successful
6 September upload. Assess signing from the actual archive/export result;
that inventory warning alone is not proof that automatic signing is unavailable.
Apple also supports [cloud-managed distribution certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/).

## On pre-order publication and download launch

1. Verify the public listing on an iPhone and iPad in an included region.
   Record whether the action is **Pre-Order** or **Get**, and the displayed date.
2. Verify China mainland and Vietnam remain unavailable. Automatic territory
   expansion is off; do not add either country without the required license.
3. Verify the support, privacy and terms destinations still load anonymously.
4. After downloads begin, repeat a free first flight and each available Pro
   product's price/restore check against the accepted production build.
5. Review App Store Connect's available crash, rating and purchase indicators
   and the existing support inbox daily during the first week. A quiet inbox
   is not evidence that every player journey works.

## Triage

Record device, OS, app version/build, exact taps, expected/actual behavior,
reproduction frequency and a sanitized crash stack or screenshot. Request a
campaign export only when needed to reproduce a save/gameplay problem; it can
contain player-created airline names. Keep that file out of public issues.

The read-only **App Store metadata** workflow, mode **plan**, also exports
sanitized submitted TestFlight crash diagnostics through Apple's API. It
does not fetch every production crash; use Xcode Organizer/App Store Connect
for the distribution's available production diagnostics. Never label an old
stack as a new regression without checking its build.

## If a critical defect appears

1. Classify the defect: crash, lost/wrong campaign, payment without access,
   blocked core task, or lesser issue. Preserve the affected build and evidence.
2. Reproduce from an exported backup or test campaign. Tell affected players
   to preserve their saves; deleting/reinstalling the game is not a generic fix.
3. Patch the smallest responsible path and add a meaningful regression case.
   Preserve schema compatibility and paid-ownership verification.
4. Test upgrade from the affected distributed build with an existing save,
   plus the changed journey, Launch safety and the required release gate.
5. Upload a fresh build number, verify processing, install and accept it,
   then submit the hotfix with precise review notes.
6. If a store-availability change is necessary, treat it as a separate,
   deliberate release-owner decision. Removing availability does not repair
   copies already installed. The recovery path is normally a compatible update.

After the fix ships, verify the reported reproduction is resolved on the new
build and continue monitoring. Preserve older diagnostic evidence and the
original failure alongside the successful regression result.
