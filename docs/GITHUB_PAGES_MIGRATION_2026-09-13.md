# Public website migration

The public site is now [wrexist.github.io/Airline-Empire](https://wrexist.github.io/Airline-Empire/).
Support, privacy, terms and press retain their existing relative HTML paths.
All five pages returned HTTP 200 and the public marketing page was checked in Chrome.

[Pages deployment](https://github.com/Wrexist/Airline-Empire/actions/runs/34784615931)
succeeded after configuring the newly created github-pages environment to allow
the prepared codex/store-cinematic-2026-09-13 branch alongside main.

[App Store Connect update](https://github.com/Wrexist/Airline-Empire/actions/runs/34784698029)
saved supportUrl, marketingUrl and privacyPolicyUrl for en-US and en-GB on
listing version 1.0. The old privacy URL was replaced within the current remote
descriptions, preserving the rest of the copy. Every changed field was read
back and verified; [report](validation/website-2026-09-13/apple-urls.json).
Screenshots, build selection, review notes, copyright and release settings
were not modified by the URL update.

The repository's website, store metadata, outreach drafts and paywall URL
constants now use GitHub Pages. The source constant change takes effect in
the next app build; existing TestFlight binaries keep their embedded links.
The previous host was not taken down. No app review submission or release
was performed by this migration.
