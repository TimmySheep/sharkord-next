# Repair iOS outgoing media

## Changes

- Moved mediasoup producer creation off the main actor. The native call synchronously waits for the asynchronous `voice.produce` delegate response, and the app handles that response on the main actor; doing both on the main actor blocked microphone, camera, and screen producers.
- Use the same WebRTC peer connection factory for the mediasoup device and local tracks. Configure and activate the call audio session through `RTCAudioSession` while holding its configuration lock, and defer microphone permission and capture until the user enables the microphone.
- Keep microphone and camera controls disabled while their start operations are in flight. Preserve local and server state when microphone, speaker, camera, or screen producer setup fails or the call ends mid-operation.
- The AI implementation was not modified as part of this repair.
- Synchronized iPhone, Live Activity, and Broadcast Upload versions to `1.28` / build `47`; Android is synchronized to `1.28` / code `50`.

## Verification

- iOS Simulator and generic iOS device architecture builds passed with code signing disabled.
- Android `:app:testDebugUnitTest` and `:app:lintDebug` passed: 74 tests, zero failures, errors, or skips.
- `plutil -lint` passed for the Xcode project, app and broadcast extension property lists, and both App Group entitlements. `git diff --check` passed.

## Acceptance boundary

- No signed install or live call was performed on the paired iPhone. Microphone capture, camera capture, ReplayKit broadcast and viewing between devices still need physical-device acceptance. The iOS project has no unit-test target, and simulator builds cannot validate these hardware and system flows.

## GitHub and device sync

- Pushed commit `d1025ade880b5ca915c328b128a9339f47e66c03` to `origin/release/android-1.6` and confirmed the remote branch SHA.
- The paired iPhone remains on cove `1.24` / build `43`. Installation was blocked because the only valid local Apple Development identity does not match the available test provisioning profiles. No provisioning profiles were changed and no app was replaced.
