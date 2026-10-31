# iOS full-device screen sharing

## Changes

- Added a ReplayKit Broadcast Upload Extension so iPhone sharing can continue while Cove is in the background or another app is foregrounded.
- Added an App Group Unix socket bridge. The extension samples and JPEG-encodes video frames, and the app converts them to WebRTC pixel buffers for the existing mediasoup screen producer. Frames are not written to disk and no server media route was added.
- Added the iOS broadcast picker flow, permission checks, waiting and active states, and stop handling for user stop, extension disconnect, call leave, and producer setup failure.
- Kept remote screen and camera presentation on the existing consumer path, which labels each stream by its owner and stream kind and retains quality-layer controls.
- Added matching screen broadcast strings in English, Simplified Chinese, Spanish, French, and German.

## Verification

- `xcodebuild -project apps/apple-mobile/Sharkord.xcodeproj -scheme Sharkord -destination 'generic/platform=iOS Simulator' -derivedDataPath apps/apple-mobile/build/DerivedData CODE_SIGNING_ALLOWED=NO build` succeeded.
- Confirmed the built app embeds `SharkordBroadcastUpload.appex`; its extension point is `com.apple.broadcast-services-upload` and principal class is `SharkordBroadcastUpload.SampleHandler`.
- `plutil -lint` passed for the project, extension plist, and both App Group entitlement files.
- All five iOS localization files contain the same 232 keys; `git diff --check` passed.

## Acceptance boundary

- Full-device broadcast capture, app switching during broadcast, remote viewing between physical devices, App Group provisioning, and broadcast stop behavior still require a signed build and iPhone testing. The simulator build does not validate ReplayKit system behavior or a real WebRTC session.
