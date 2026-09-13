# Website visual redesign

The GitHub Pages site now uses a light pearl and sky-blue palette, frosted glass
navigation and controls, softly shaded clay forms, and cinematic aviation art.
It remains a static HTML/CSS/JavaScript site with no framework, tracking or
external font dependency.

The homepage includes a floating aircraft and native-gameplay hero, three
feature cards, keyboard-accessible gameplay tabs, a decorative interactive
flight with pause and speed controls, a six-image gallery with a native modal,
FAQ disclosures and a cinematic closing section. The release CTA accurately
says the game is coming to iPhone and iPad rather than offering an unavailable
download. Support, privacy, terms and press share the new navigation and footer.

Fifteen WebP assets were exported from existing project artwork, the original
native captures, and the approved store designs using Sharp. Together they are
approximately 1.1 MiB; below-fold images load lazily. The press download now
contains the current eighteen full-resolution iPhone/iPad PNG exports.

Validation completed locally:

- Browser layout checks at 320, 390, 768 and 1440 CSS pixels found no page-wide
  overflow or clipped copy in the checked content containers.
- Desktop and mobile composition, native gameplay views and mobile support
  content were visually reviewed.
- Gameplay tab clicks and arrow-key selection, gallery navigation, modal
  next/previous and Escape, FAQ expansion, pace controls and motion pause worked.
- No browser runtime errors were reported during the interaction checks.
- All five HTML pages passed local link, anchor, image-alt, shared-script and
  asset checks. JavaScript syntax and Git whitespace checks passed.
- CSS honors prefers-reduced-motion; a visible site-motion control pauses
  decorative animations. System reduced-motion preference takes priority.

Original native game captures and App Store screenshot exports are unchanged.

Published successfully in [Pages run 34785767568](https://github.com/Wrexist/Airline-Empire/actions/runs/34785767568).
The live browser initially reused a cached pre-redesign stylesheet; content-hash
query strings were added to CSS, JavaScript and updated press assets. The final
live rendering was visually verified, all 22 checked website files matched the
deployed sources, and all five HTML pages matched the final versioned release.
