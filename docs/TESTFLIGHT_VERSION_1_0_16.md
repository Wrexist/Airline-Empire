# TestFlight version correction - 11 September 2026

The owner requested a version above 1.0.15. The replacement marketing
version is **1.0.16**; the archive workflow assigns the next build number
from Apple's existing build inventory.

## Why the previous attempt stopped

Run `34578192830` used main commit
`6f506ce3a2e39154f0500ec124a82e9e56ac4f3b`, the documentation handoff.
That exact commit had no successful Launch safety run, so the release
evidence gate correctly stopped before archive/upload. This was not a
version, signing or gameplay failure. The gate was not disabled.

## Corrected dispatch

Run [34579597613](https://github.com/Wrexist/Airline-Empire/actions/runs/34579597613)
uses the workflow on main but explicitly checks out validated candidate
`18253b31333f4e7c0e9a8b9b4410cda2ea45b80d` for preflight, tests and archive:

```powershell
gh workflow run ios-testflight.yml --ref main -f version=1.0.16 -f upload=true -f candidate_sha=18253b31333f4e7c0e9a8b9b4410cda2ea45b80d
```

This command records the dispatch already performed. Do not run it again
while the current upload is active or merely to inspect its status.

## Verified result

- All four jobs passed on attempt 1. The isolated simulation test passed in
  37.099 seconds and the remaining 522 tests passed in 858.934 seconds.
- Apple upload succeeded at 08:52:11 UTC; processing returned **VALID** at
  08:54:00 UTC on 11 September 2026.
- Build **1.0.16 (6)**, Apple ID `717e0a4e-6403-4261-92a5-757536e4ab54`,
  is assigned to the existing one-owner **Tester** internal group. Its
  build-specific test notes are saved.
- App Store listing version **1.0** now selects this build. It is back in
  the same five-item draft with Weekly, Yearly, Lifetime and the Pro group;
  Apple shows Ready for Review and enables Submit for Review. Not submitted.
- Local IPA inspection matches the runner report. IPA SHA-256:
  `332820d13bd3ef6c0c67793661fe05683be8b0574c739fe419fa9f6846d49f5d`.
  Executable and dSYM UUIDs both equal
  `8C6045C1-59F4-399A-965A-617D42294367`.
- Durable binaries/symbols are in
  `C:/Users/IsacC/Airline-Empire-release-artifacts/candidate-18253b3/build-1.0.16-6`.
  [Binary/account receipt](validation/release-2026-09-11/binary-1.0.16-6.json),
  [IPA inspection](validation/release-2026-09-11/bundle-inspection-1.0.16-6.json)
  and [workflow receipt](validation/release-2026-09-11/testflight-34579597613.json).

**Install 1.0.16 (6) from TestFlight. Export important saves first and update
in place.** Physical acceptance is still required using the
[owner guide](RELEASE_OWNER_STEPS.md). The 173-region/16 October pre-order
configuration is unchanged.
