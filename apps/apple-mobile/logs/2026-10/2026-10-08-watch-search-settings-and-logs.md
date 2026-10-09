# Apple Watch search, settings, and log collection

## Changes

- Replaced the top-right diagnostics shortcut with a search toggle. Search input now appears in the previous channel-search position and clears when closed.
- Increased the Channels heading size and constrained it to one line with adaptive scaling. Removed the Preview badge and offline-preview disclaimer.
- Added Watch settings for language selection, server connectivity checks, and Watch-only diagnostics/export.
- Added one-tap iPhone log collection and export. It always includes iPhone logs and requests Watch logs using WatchConnectivity; the request uses reliable user-info transfer when the Watch app is not immediately reachable, with a bounded wait and a phone-only fallback status.
- Added the new interface strings to English, Simplified Chinese, German, Spanish, and French.

## Verification

- iPhone and Apple Watch simulator builds passed.
- The Xcode project and all five localization files passed `plutil -lint`; localization key sets match.
- No simulator screenshots or paired-device runtime transfer were performed. Visual fit and Watch-to-iPhone log collection still need runtime acceptance.

## Profile settings and production-facing screens

- Added iPhone Settings controls matching the Web profile editor: display name, profile color, bio, avatar and banner upload/removal. These use the existing server profile, upload, avatar, and banner endpoints; upload and mutation failures are surfaced in the UI.
- Added profile strings in English, Simplified Chinese, German, Spanish, and French.
- Removed the sample Dynamic Island preview control from Developer Settings. When the Watch is not connected, its root now opens the real sign-in view instead of sample channel and message data.
- Updated Watch room layout to show the member count without a large channel title, use active-audio indicators, and keep the larger hold-to-talk control pinned outside the scrolling content.

## Verification update

- iOS Simulator and watchOS Simulator builds passed after the complete profile editor changes.
- All five localization files passed `plutil -lint`, and `git diff --check` passed.
- No authenticated profile edit or avatar upload was performed against a real account, since that would change account data. Paired-device transfer and visual screenshot checks remain outstanding.

## Remove sample-facing UI

- Removed sample Watch channels/messages and the simulated Watch radio transport from the app-facing path; disconnected Watch state now resolves to the real sign-in screen.
- Removed test/sample activity labels and sample-data localization entries from all five languages. Image-load failure text is now generic and does not refer to a preview.
- Rebuilt iOS and watchOS Simulator schemes successfully. Confirmed all five localization key sets match, all `.strings` files pass `plutil -lint`, and `git diff --check` passes.
- Ran `apps/server/src/routers/__tests__/users.test.ts`: 86 passed, 0 failed, including persisted profile updates and avatar/banner upload, replacement, and removal against an isolated seeded database. This validates the server paths, not a live account end-to-end run through the iOS picker.
