# RevenueCat setup — 23 September 2026

## Live account configuration

- Project: [Airline Empire](https://app.revenuecat.com/projects/966148a9/overview), REST ID `proj966148a9`.
- App: `appafbfd2a8bc`, App Store bundle `com.airlineempire.game`, Apple app `6806410538`.
- Existing Apple in-app purchase and App Store Connect API keys reused; both show **Valid credentials**. No secret keys are embedded in source.
- Imported all three Apple-approved products: `com.airlineempire.game.pro.weekly`, `.yearly`, and `.lifetime`.
- All three grant `airline_empire_pro` (`entlca5c924a9e`).
- Current/default offering `default` (`ofrngc41f93b8e3`) maps `$rc_weekly`, `$rc_annual`, and `$rc_lifetime` to the matching App Store products. The onboarding Test Store products remain isolated to the Test Store app.
- RevenueCat applied Apple server notifications successfully. Both production and sandbox URLs were independently verified in App Store Connect. RevenueCat says they are configured correctly.
- **Track new purchases from server-to-server notifications** is enabled and saved. This permits reporting for the already-approved StoreKit-only build.
- Restore behavior: **Transfer to new App User ID**, appropriate to this app's anonymous customers. No custom player accounts, advertising integrations, or custom webhooks were added.

## Approved release and SDK integration

Apple version **1.1.0, build 13**, is **Pending Developer Release**. Its approval, attached build, release settings, and pre-order were not changed. It does not contain RevenueCat's SDK. Server reporting does not add SDK-dependent paywalls, experiments, or installation metrics to that binary.

The SDK integration is on `codex/revenuecat-launch-2026-09-23`, based on the current approved-release development branch `codex/ae049-aircraft-configuration`. It is intentionally not merged into `main`, whose app code differs substantially from that release branch.

- RevenueCat iOS SDK is pinned to **5.90.2**.
- Uses the App Store public SDK key and `.myApp` / `.storeKit2` configuration. Existing StoreKit verification, finishing, paywall prices, trial eligibility, offline access, refunds, expiry, and restore behavior remain authoritative in the app.
- Records verified transactions without blocking access; syncs existing purchases once after successful migration and after explicit restore. Failed syncs retry on a subsequent launch.
- Uses anonymous RevenueCat customer IDs, with no email, name, advertising identifier, or gameplay attributes.
- Local simulator StoreKit fixtures do not report to RevenueCat. Real-device TestFlight is required for end-to-end RevenueCat verification.
- The app's existing native paywall remains in use. A RevenueCat-hosted paywall is not required for this supported integration.

## Privacy

App Store Connect's published label now declares **Purchase History**, used for **App Functionality and Analytics**, **not linked to identity**, and **not used for tracking**. This follows [RevenueCat's Apple privacy guidance](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy).

The public [privacy policy](https://wrexist.github.io/Airline-Empire/privacy.html) now describes RevenueCat purchase processing. It was deployed from `main` in [run 35860859273](https://github.com/Wrexist/Airline-Empire/actions/runs/35860859273). The initial deployment from the SDK branch was rejected by the existing Pages branch restriction; the privacy-only change was published through the permitted `main` branch without changing that restriction.

Local app privacy text, privacy manifest, review notes, and the generated handoff instructions were updated for the next SDK build.

## Validation and remaining release gates

- Local release-source and App Store metadata validation passed.
- First macOS build caught a `VerificationResult` name collision with RevenueCat; fixed by qualifying `StoreKit.VerificationResult`.
- Corrected SDK purchase tests: [Launch safety run 35861049122](https://github.com/Wrexist/Airline-Empire/actions/runs/35861049122) — status must be checked before using this branch for a release.
- No real Apple purchase notification had arrived during configuration. A TestFlight purchase and restore must appear in RevenueCat's sandbox customer history to establish end-to-end delivery. Simulator success is not evidence of live RevenueCat ingestion.
- Shipping the SDK requires a new signed build, device verification, and Apple review. The approved binary can retain its approval and use the configured server reporting.
- Vendor number/financial report reconciliation and Small Business Program commission dates were not asserted without evidence; they are optional accounting configuration, not purchase validation credentials.

References: [app-completed purchases](https://www.revenuecat.com/docs/migrating-to-revenuecat/sdk-or-not/finishing-transactions), [Apple server notifications](https://www.revenuecat.com/docs/platform-resources/server-notifications/apple-server-notifications).
