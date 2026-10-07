# Android voice, screen sharing, and adaptive channel layout

## Changes

- Screen sharing now waits for `VoiceCallService` to confirm that Android has entered the
  `mediaProjection` foreground-service state before WebRTC creates the `MediaProjection`.
  Startup errors and timeouts are surfaced, and failed starts close local and server-side
  screen producers.
- Voice calls keep a `mediaPlayback` foreground service while remote audio is enabled,
  including when the microphone is muted. The service switches its foreground-service
  types when microphone or screen sharing starts and stops when the call has no active media.
- Voice-channel messages remain visible beside the voice room on wide layouts. Compact
  layouts place the room panel above the message list; participant chips scroll horizontally.
  The UI continues to use Compose Material 3 and dynamic system colors rather than copying
  the iOS visual language.
- Moved the prior Android build output and project Gradle cache to
  `~/.Trash/2026-10-07-170720-cove-build/`. The verification build recreated
  `app/build` (273 MB) and `.gradle` (3.2 MB); these are currently retained.

## Verification

- `:app:testDebugUnitTest`: 4 tests passed.
- `:app:assembleDebug`: passed.
- `:app:lintDebug`: 0 errors, 11 warnings.
- The 70 MB APK at `~/Downloads/cove-android-debug-2026-10-07-voice-chat-share-fix.apk`
  matches the build output, SHA-256
  `08c1f8cb4c906f103a5c111b65aca4679b2576a050f6e02cec6faf23dae07ffe`.
- Device-level screen projection and two-device voice acceptance remain pending. No Android
  device or `adb` target is available in this environment.

## Follow-up: public-channel share button was disabled

- The user reported that the screen-share control was grey. The client correctly gates the
  control on its channel permission state, but the server permission summary reported
  `SHARE_SCREEN=false` for public channels even though server authorization allows every
  channel permission in a public channel. The Android UI now treats a public channel as
  channel-permitted, and the server summary has been corrected for all clients. Private
  channels remain permission-gated and the server-level permission check is unchanged.
- New APK: `~/Downloads/cove-android-debug-2026-10-07-screen-share-button-fix.apk`, SHA-256
  `44114d4f840af26437a609401542aef425b5a74ad680e5c2dcfd78ef96509af7`.
- Android tests, assemble, and lint pass. The targeted server permission file passes 13 tests.
  The full server suite has one unrelated failure in
  `src/http/__tests__/plugin-routes.test.ts` (connection-close rejection); that same test
  also fails when run alone.
- The permission state and grey-button fix are source/build verified, not yet confirmed on
  the user's device. Install this APK to verify the control becomes enabled; the server-side
  permission summary fix is also in the pushed branch.
