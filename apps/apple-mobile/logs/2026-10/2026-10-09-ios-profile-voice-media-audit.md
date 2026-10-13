# iOS profile and real-time media audit

## Audit result

- Profile editing was already wired to the existing server APIs for the account name, bio, profile color, avatar, and banner. The avatar picker now previews the selected image before saving.
- Existing call flows support voice join/leave, microphone mute, deafen, remote audio, camera on/off and switching, and remote screen/camera video. iOS full-device screen capture is provided by the ReplayKit Broadcast Upload Extension added in the companion screen-sharing work.
- Found that the iPhone app declared camera permission text but not microphone permission text. Added localized camera and microphone usage descriptions in all five supported languages.
- Made voice joins idempotent while joining/connecting and release partially initialized mediasoup resources plus attempt a server leave when setup fails.
- Changed generic user avatars from initials-only placeholders to load the real server avatar with initials as the fallback, including message authors, members, direct-message member selection, and voice participants.
- Updated the iOS README and mobile parity taskbook to reflect the current navigation, profile, and full-device screen-share implementation.

## Verification

- iOS Simulator build succeeded with `xcodebuild -project apps/apple-mobile/Sharkord.xcodeproj -scheme Sharkord -destination 'generic/platform=iOS Simulator' -derivedDataPath apps/apple-mobile/build/DerivedData CODE_SIGNING_ALLOWED=NO build`.
- Confirmed the built app contains the microphone and camera usage descriptions and all five localized `InfoPlist.strings` resources.
- `plutil -lint` passed for the Xcode project, app and extension plists, entitlements, and localized privacy strings; `git diff --check` passed.
- The Xcode project has no iOS unit-test target. No live account profile mutation or physical-device audio/video session was run.

## Remaining acceptance

- Use a signed iPhone build to grant microphone/camera permissions, update the profile name and avatar with a test account, join and leave a real voice room, verify both directions of audio, toggle/switch the camera, and share/receive screens between devices.
- Full-device broadcast additionally depends on the App Group being enabled for the signing team. Simulator compilation does not validate that provisioning or ReplayKit runtime behavior.
