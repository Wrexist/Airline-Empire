# TestFlight 1.0.19 (8)

13 September 2026: **processed by Apple and available in the existing Tester
group**. Build-specific testing instructions are saved. Update the existing
TestFlight installation before App Store submission. No submission was made
and the existing App Store draft's build selection was not changed.

- [Successful release run](https://github.com/Wrexist/Airline-Empire/actions/runs/34726940610)
- [Merged release fix, PR #33](https://github.com/Wrexist/Airline-Empire/pull/33)
- [TestFlight build](https://appstoreconnect.apple.com/teams/47a0adf3-7006-447c-8543-48214a1a243d/apps/6806410538/testflight/ios/879a0cf9-8197-4d50-81af-f34c89231f46)
- Binary source: `0bf86aee2a86a60f8a0b1bf553dfb45cf9136af5`.
- Merged revision: `3938a78c041acd6887c5f2fed57acc151bb3ac58`.

TestFlight now runs full CI and Launch safety on its immutable candidate
before archiving. It no longer requires the owner to dispatch full CI and
Launch safety separately in the right order. Every validation and archive
checkout uses the same candidate SHA, and failures continue to block upload.

527 Core tests passed in both Debug and Release, alongside the warnings-as-
errors Release build, 13 Launch safety cases and the Release entitlement
isolation check. Full CI ran all five iPhone shards, iPad and performance:
28 UI/performance executions passed, zero failed, and one existing test of
directly tapping a moving aircraft marker skipped. The accessible Follow a
flight journey passed separately. Physical direct selection remains part of
device acceptance.

The downloaded IPA independently passed inspection, and the app/dSYM UUIDs
match. All PR checks passed before merge. A follow-up change only improves
the UI test's observation of an already-paused clock; shipping source,
resources and project configuration are identical to the uploaded candidate.

IPA, dSYMs, detailed report and validation receipts:
`C:/Users/IsacC/Airline-Empire-release-artifacts/candidate-0bf86ae/`.

On the physical device, verify existing saves after updating, the new free
player's first flight, briefing/Settings/Pause, direct map selection,
purchase/restore and offline relaunch before submission.
