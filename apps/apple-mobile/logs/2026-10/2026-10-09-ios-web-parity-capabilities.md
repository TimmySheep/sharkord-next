# iOS web parity capabilities

## Changes

- Render message HTML through the shared `MessageHTML` parser, including styled text, links, mentions, channel references, emoji images, and media.
- Add permission-filtered server management for channel and category CRUD, general and storage settings, basic member moderation, roles, custom emoji, invites, plugin marketplace/install/update, and server updates.
- Add local notification preferences and message sound effects. Notifications are created only while the app receives live message events; APNs delivery is not configured.
- Preserve the workspace and navigation while the existing session reconnects, show a reconnect banner, and provide a manual retry after retries are exhausted.
- Update the iOS README with implemented capabilities and remaining web parity gaps.

## Verification

- iOS simulator build passed with `xcodebuild -project apps/apple-mobile/Sharkord.xcodeproj -scheme Sharkord -destination 'generic/platform=iOS Simulator' -derivedDataPath apps/apple-mobile/build/DerivedData CODE_SIGNING_ALLOWED=NO build`.
- `plutil -lint` passed for all five `Localizable.strings` files.
- Locale key check found 371 English keys with no duplicates and matching keys in Simplified Chinese, Spanish, French, and German.
- `git diff --check -- apps/apple-mobile` passed.
- No real-device notification, account-based admin action, or audio/media acceptance was performed.

## Remaining boundaries

- The native client does not render plugin-provided React screens or expose plugin settings, logs, commands, and capability controls.
- Member detail and role assignment, and channel permission overrides, remain unavailable in the native management UI.
- New message notifications are not guaranteed while iOS suspends or terminates the app because APNs support is not configured.
- Simulator compilation does not validate ReplayKit, voice, camera, or remote media on a signed device.

## Follow-up verification

- Added localized labels for role permissions in all five languages.
- Re-ran the iOS simulator build, `plutil -lint`, locale key comparison, and `git diff --check`; all passed.
- Final locale check found 395 English keys with matching translations and no duplicates.
- Repeated the full validation after the reconnect-state guard change; the build and all static checks passed again.
