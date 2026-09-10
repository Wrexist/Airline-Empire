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
