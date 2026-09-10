# Source capture review

Reviewed all ten iPhone and ten iPad source images from successful Store
screenshots run [34530096286](https://github.com/Wrexist/Airline-Empire/actions/runs/34530096286)
at candidate `2a7a8e1`. Candidate `18253b3` has identical shipping app/Core source.
`store-capture-review.json` records the original attachment names, verified
SHA-256 checksums and dimensions. These are native captures, not retouched images.

Network, Fleet, Market, route detail, Routes, Finance, Competitors, World,
Progression and Home briefing all show the intended screen. Phone tab and iPad
sidebar selection agree with their destination. Lists and financial columns
remain readable at these capture sizes. Market and briefing use scrollable
sheets on iPad; content below their first viewport needs scrolling.

## Non-blocking wording follow-up

Fleet shows **11 flying** in its summary but **Flying 12** in the filter.
The fixture has 13 aircraft: one idle and one in maintenance. The filter's
`.assigned` predicate tests only `assignedRoute != nil`, so an assigned
maintenance aircraft remains included. The summary describes aircraft flying
a route today. This is a label/definition inconsistency, not evidence of a
missing aircraft or changed assignment.

Suggested follow-up: name the filter **Assigned**, or deliberately align its
predicate and summary semantics. Verify with active assigned, idle and
assigned-in-maintenance aircraft. This cosmetic follow-up is not included in
the frozen binary candidate; it does not block the current release.

## Limits

This review covers default dark appearance at the two source capture sizes.
It does not certify physical touch targets, VoiceOver order, large text,
compact iPad resizing, light appearance, frame rate or audio behavior. Those
remain in the physical acceptance checklist. The source images supplement
the existing App Store exports and do not replace full journey assertions.
