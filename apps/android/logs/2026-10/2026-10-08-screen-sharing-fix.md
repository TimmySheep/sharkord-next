# Android screen-sharing producer fix

- Compared Cove's Android mediasoup flow with the reference client at
  `https://github.com/Vigno04/sharkord-android`. Producer-ID decoding now accepts both a raw tRPC
  string and the `{ "value": "..." }` representation used when a client normalizes scalar results.
- Replaced the pending producer-kind workaround with explicit `audio`, `video`, and `screen` producer
  app data. Producer and consumer transports now connect to the server only once per transport.
- Explicitly initialized WebRTC and configured its default video encoder and decoder factories.
  Local screen and remote video tracks are enabled before publishing them to the UI.
- Added Android tests for both producer-ID response shapes, null IDs, and screen-kind app data.
  Verification passed: 40 unit tests, `lintDebug`, `assembleDebug`, `bun run magic`, Xcode project
  `plutil -lint`, and `git diff --check`. Existing lint warnings remain.
- Advanced Android to `1.8` / build `30` and synchronized iPhone app and Live Activity metadata to
  `1.8` / build `27`. Apple Watch settings were not changed by this task; no iOS build was run.
- Delivered `~/Downloads/Cove-1.8-build30-screen-share-debug.apk` (71 MB), SHA-256
  `58b5f155818da1977db66fe5d99ef3b8927d305f0aa8b7ba7b7b21643c8b46d6`. The APK reports package
  `com.timmysheep.cove`, version `1.8`, code `30`, and passes v2 signature verification.
- Physical-device screen-share acceptance remains pending.

## GitHub publication

- Pushed source commit `98fd4e7` to `release/android-1.6` and published pre-release tag
  `native-android-v1.8`: https://github.com/TimmySheep/sharkord-next/releases/tag/native-android-v1.8
- Uploaded `Cove-1.8-build30-screen-share-debug.apk`. GitHub reports the same SHA-256 as the local
  artifact: `58b5f155818da1977db66fe5d99ef3b8927d305f0aa8b7ba7b7b21643c8b46d6`.
