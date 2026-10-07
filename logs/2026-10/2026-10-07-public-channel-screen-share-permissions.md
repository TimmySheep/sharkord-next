# Public channel screen-share permission state

## Cause

The user reported that Android's screen-share control was grey. The Android UI checks the
`SHARE_SCREEN` channel permission before enabling the control. `channelUserCan` grants every
channel permission on public channels, but `getAllChannelUserPermissions` left unspecified
permissions false for those channels. The join payload therefore disagreed with the server's
authorization rule and caused the client to disable the control.

## Changes

- The Android UI treats public channels as permitted at the channel-permission layer. Private
  channels still use the server-provided per-channel permission state.
- `getAllChannelUserPermissions` now reports all channel permissions as true for public
  channels, matching `channelUserCan` and the existing DM membership behavior.
- No server-level authorization was relaxed. `voice.produce` continues to require the
  server-level `SHARE_SCREEN` permission.
- Added a regression test that checks a public voice channel reports `SHARE_SCREEN=true`.

## Verification

- Targeted server permission tests: 13 passed.
- Android unit tests: 4 passed; Debug assembly passed; lint reports 0 errors and 11 warnings.
- `bun run magic` passed.
- `bun run test` reports one failure in the unrelated plugin route connection-close test.
  Re-running that test file alone reproduces the same failure.
- The new APK is at
  `~/Downloads/cove-android-debug-2026-10-07-screen-share-button-fix.apk`. Device verification
  remains pending; no Android device or `adb` target is available here.
