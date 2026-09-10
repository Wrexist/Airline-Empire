# Original failures on 51b295b

Source: CI run [34522453247](https://github.com/Wrexist/Airline-Empire/actions/runs/34522453247),
native results exported by diagnostic run 34525098373. These are failure
evidence, not passing acceptance screenshots.

- `map-pause.png`: unaltered decoded video frame three seconds before the end
  of MapHome's 349-second XCTest screen recording. Pause remains visible at
  the left of the speed bar, with 1x selected and one airborne aircraft.
  A second inspected frame at video time 270 seconds has the same control
  placement. The log fails the frame-stability guard before a Pause tap.
  Individual AX queries consumed 5–26 seconds while the helper required two
  matching frame comparisons inside four seconds. `map-summary.json` is
  the original xcresult summary (iPhone Air, iOS 26.5).
- `fleet-selection.png`: original CI checkpoint, exported by CI at 360 px
  width. Routes remains selected after the helper reported opening Fleet.
- `calendar.png`: original CI checkpoint at 360 px. Date is 2030-01-26;
  the log reports 24 -> 25 acknowledged advance requests. The 20-second
  observation timed out across accessibility snapshot retries.

The original native artifacts also preserve the World-tab failure screenshot:
World was already visibly selected. The next candidate corrects observation
and selection handling; a fresh full test run must establish the outcome.

## Subsequent economy navigation failure on dff78b4

CI [34525956478](https://github.com/Wrexist/Airline-Empire/actions/runs/34525956478)
passed every job except economy, which passed four of five cases.
`economy-tab-selection.png` is the unaltered 360-pixel CI checkpoint
`KEY-NO-AIRLINE-SECTION-Routes` from job `103034830762`. Home remains selected
after the log records an Airline tap. One route and one aircraft are visible;
the route command completed, but navigation did not. The first-month test passed.
The new helper waits for the route sheet's disappearance and selected-tab state
before allowing the journey to continue. This screenshot documents the failure;
the new candidate still requires fresh native validation.

## Lease observation failure on 2a7a8e1

CI [34530096281](https://github.com/Wrexist/Airline-Empire/actions/runs/34530096281),
economy job `103048517562`: `lease-after-timeout.png` is the unaltered
`KEY-LEASE-ATTEMPT-1` checkpoint. It shows one leased Meridian MR-180 at
$740k/month on Fleet. The preceding eight-second market-disappearance wait
ran from t=59.01 to t=97.31 through slow accessibility queries. The helper
skipped the aircraft proof because that waiter returned false, even though
the market had closed. The correction reconciles the current sheet state
and retains the aircraft proof. The following New York case failed while
XCTest tried to terminate the previous app, before a journey assertion.
`economy-lifecycle.json` records the native diagnostic timeline: the host
received the termination request 52 seconds late, the app then exited on
SIGTERM, and XCTest's foreground-state wait still timed out. No spontaneous
app crash is established by this failure.
