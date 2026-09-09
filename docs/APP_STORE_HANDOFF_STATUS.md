# App Store handoff — checked 2026-09-09

The marketing images and English listing copy are prepared. This is not a
confirmation that the App Store Connect account or submission is complete.

## Ready

- Six designs in three sizes: 18 unique RGB PNGs, mirrored for en-US/en-GB.
- All exports decode and match their native-source hashes and dimensions.
- Name, subtitle, promotional text, description, keywords, review notes,
  TestFlight copy, and Pro purchase display names/descriptions.
- [Copy/paste sheet](APP_STORE_CONNECT_FILL_IN.md), generated from the repository.
- Subscription options and Apple Standard EULA/privacy references in listing copy.
- 48 release-tooling tests passing; all listing character limits pass.

## Still required before submission

1. **Public pages:** the configured privacy and support URLs both returned
   HTTP 404 on 2026-09-09. Publish the prepared `site/` pages or supply working
   public URLs, then update and verify all listing and in-app links together.
   Do not submit the currently broken URLs.
2. **Account-holder details:** legal copyright/seller name, App Review first
   and last name, email, and phone. These remain explicit `REPLACE_ME` values.
   Do not infer the legal entity from the GitHub username or another business.
3. **In-app purchases:** create/verify the three configured products and
   weekly introductory offer in App Store Connect. Supply a genuine paywall
   screenshot for IAP review. The marketing gallery is not that screenshot.
4. **Account/build declarations:** attach and device-test the intended build;
   complete age rating, privacy, content rights, and applicable account
   agreements. These have not been checked in the signed-in Apple account.

The privacy declaration must reflect the submitted build. The age-rating
answers are recommendations based on the current single-player app, not a
promise of a particular regional rating. Apple calculates the result from
the answers: [official definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/).

No Apple upload or submission was performed in preparing this handoff.
