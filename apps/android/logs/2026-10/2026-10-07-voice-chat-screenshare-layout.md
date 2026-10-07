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

## Follow-up: connect appearance and owner channel permissions

- The connect screen now paints its full root with the active Material color scheme, fixing
  the white window background in dark mode. Removed the unused connect subtitle from every
  Android locale.
- The permission payload now mirrors the server owner's existing bypass for private
  non-DM channels. This fixes a false local "no permission" result for screen sharing without
  changing authorization rules. Added a regression test for the owner's private-channel
  `SHARE_SCREEN` state.
- Verification: 4 Android unit tests passed, Debug APK assembled, lint has 0 errors and
  11 warnings. Targeted server permission tests passed (14), and server type and format checks
  passed. Device-level appearance and screen-share acceptance remain pending.

## Follow-up: attachments, search, threads, and camera controls

- Android now uploads and attaches picked files, previews images, opens other attachments,
  searches messages and files, navigates to results, and loads/sends thread replies.
- Added local camera capture, front/back switching, local preview, and remote simulcast quality
  selection when the producer advertises quality layers. Camera and screen sharing both check
  the server-level and channel-level permissions. Foreground-service types are kept in sync
  when microphone, camera, and MediaProjection capture start or stop.
- Verification: 5 Android unit tests passed; `:app:lintDebug` and `:app:assembleDebug` passed.
  Lint reports 11 warnings and no errors. The targeted server voice and channel-permission
  tests passed (52 tests); server type, lint, and format checks passed. Device capture and
  two-client media acceptance remain pending; no Android device target was used.

## Verification update

- Serialized camera start/stop with call teardown and producer creation, reset local camera
  state on leave, and distinguish a denied Android camera permission from server/channel
  authorization.
- Re-ran `:app:testDebugUnitTest`, `:app:lintDebug`, and `:app:assembleDebug` successfully.
  Lint reports 12 warnings and no errors.

## Follow-up: simplify the connect header

- Removed the Cove launcher mark from the Android connect screen and explicitly set the
  heading to the theme's `onBackground` color so it remains legible in dark appearance.
- The Android unit tests, lint, and Debug build passed. The iOS globe language control was
  left unchanged as requested; its Simulator build passed.

## Follow-up: channel chat and voice controls

- Kept login on the first available non-DM text channel. Enlarged the selected channel title
  while retaining the top-right search action.
- Replaced the stacked voice-plus-chat view with Voice and Chat pages that can be changed by
  swiping or selecting the page tabs. Joined-call controls now stay above the app navigation:
  microphone and speaker are icon-only, camera and screen share have short labels, and hang-up
  is a dedicated red button.
- Removed the client-side screen-share permission snapshot gate that could leave the control
  disabled despite the account's effective permission. The server still checks both global
  and channel authorization when it creates the screen producer, and the existing failure path
  stops capture if authorization is rejected.
- Added Compose IME insets to the channel screen so the composer moves above the keyboard.
  Reworded the thread entry as “Start a thread” and its sheet as “Replies” to explain that it is
  a reply group attached to a message.
- Verification: 5 Android unit tests passed; `:app:lintDebug` and `:app:assembleDebug` passed.
  `bun run magic` passed with existing TypeScript lint warnings and no errors, and
  `bun run synci18n` reported all translations up to date. No Android device was attached, so
  screen sharing and keyboard placement still need real-device acceptance. The build output
  remains in the project; no APK was copied elsewhere.

## Artifact delivery follow-up

- At the user's request, copied the Debug APK to
  `~/Downloads/cove-android-debug-2026-10-07-channel-voice-ui.apk`.
- Verified the delivered file is 74,029,264 bytes and has SHA-256
  `c0a478f4c2017202d929109319140ecaaac422ae8ddbf4db159fa36f2959164f`, matching the project
  build output. No device was installed or operated.

## Follow-up: center the connect form

- Vertically centered the complete connect block within the safe visible area. The scroll
  container keeps the form usable on short screens, with advanced options, errors, or the IME
  reducing the available height.
- Verification: 5 Android unit tests passed; `:app:lintDebug` and `:app:assembleDebug` passed.
  `bun run magic` passed with existing TypeScript lint warnings and no errors. No Android device
  was attached for visual confirmation.
- At the user's request for updated Android builds in Downloads, saved a new APK without
  replacing the previous one at `~/Downloads/cove-android-debug-2026-10-07-connect-centered.apk`.
  Verified 74,029,264 bytes and SHA-256
  `fa437edc0897f20bb54ad727f89cc86abadc0156a5b59f5fec04262bc30dd30e` against the project
  build output.
