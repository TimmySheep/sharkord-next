# Apple mobile voice, screen sharing, and adaptive channel layout

## Changes

- On iPhone, voice-channel chat can be opened from the voice room. On regular-width layouts,
  the voice room and its same-channel message composer are shown side by side.
- Hardened ReplayKit app-capture startup and shutdown: capture errors stop the producer,
  clear server voice state, and do not leave a stale local sharing state. A capture failure
  during producer startup is deferred until setup completes, avoiding a stop/start race.
- Added `UIBackgroundModes` with the `audio` mode so an active voice session can continue
  audio while the app is backgrounded. The built simulator app's `Info.plist` was checked
  and contains the expected array value.
- The current iOS implementation uses `RPScreenRecorder.startCapture`, which captures Cove's
  app content only. Sharing the entire device while switching to other apps needs a ReplayKit
  Broadcast Upload Extension; the project has no such target, so full-device iOS sharing is
  not implemented. Updated the voice-room hint and README to state this limitation.
- The Apple project had no logs directory; added this log index and event record.

## Verification

- `xcodebuild -quiet -project Sharkord.xcodeproj -scheme Sharkord -destination
  'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`: passed.
- `Sharkord/Info.plist` passes `plutil -lint`; the built app's `UIBackgroundModes` is an
  array containing `audio`.
- Simulator compilation is not an end-to-end voice or ReplayKit test. Real-device audio and
  broadcast behavior still require acceptance testing.

## Follow-up: attachments, search, threads, and camera controls

- Added file picking and upload, image preview and other-file opening, message/file search,
  navigation to results, paged thread replies, and sending replies in a thread.
- Added camera permission disclosure, local camera publishing and preview, front/back camera
  switching, and a receive-quality menu for available simulcast layers. Camera and screen
  sharing now gate on both the server-level and channel-level permissions.
- Verification: the iOS Simulator scheme builds successfully; `Sharkord/Info.plist` passes
  `plutil -lint`, and the built app contains `NSCameraUsageDescription`. No physical device
  was used. Full-device sharing after leaving Cove remains unsupported until a ReplayKit
  Broadcast Upload Extension is added; current ReplayKit capture is limited to Cove.

## Verification update

- Prevented overlapping camera-start requests and separated missing server/channel permission
  from denied iOS camera access in the localized error state.
- Re-ran the iOS Simulator build successfully. Camera capture and camera switching still
  require physical-device acceptance.
