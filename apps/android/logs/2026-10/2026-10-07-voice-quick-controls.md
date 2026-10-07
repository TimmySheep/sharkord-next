# Android persistent voice quick controls

- Added a fixed control strip below the top app bar while connected to voice and browsing another
  destination. It shows the active voice room and provides microphone, speaker-output, and leave
  controls. The existing full controls remain on the active voice-room screen to avoid duplicates.
- The microphone action follows the existing runtime permission flow; all actions use the existing
  voice engine. Added localized accessibility descriptions in English, Simplified Chinese, German,
  Spanish, and French.
- Android unit tests, lint, and Debug build passed. `bun run magic` completed with existing
  repository lint warnings and no errors; `git diff --check` passed. No physical device was
  operated, so visual acceptance remains pending.
- Synchronized Android and iPhone versions to 1.6 and build number 7; Apple Watch remains unchanged.
- Published the Android app source on branch `release/android-1.6`, commit `0b27768`, and created
  the public prerelease `native-android-v1.6`. The `app-debug.apk` asset uploaded successfully
  at 73,719,418 bytes; GitHub reports the same SHA-256 as the locally verified APK:
  `2de3ffccf44188c8d2f4e33b6b7a2a67579f0cc1abb4f6ff02a9f5e5777e3678`.
- Release: https://github.com/TimmySheep/sharkord-next/releases/tag/native-android-v1.6. The APK is
  debug-signed and the release notes warn that it is not a production or Play Store build.
