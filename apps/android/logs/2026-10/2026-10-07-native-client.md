# Native Android client implementation

## Scope

Build the first native Android client flow for login, channels, direct messages, messages,
voice media, and screen sharing, using the existing server protocol and cove artwork.

## Toolchain and dependency inventory

- Reused Homebrew `openjdk@17` version `17.0.19`; no JDK installation was needed.
- Reused Android SDK `/opt/homebrew/share/android-commandlinetools`, platform API 36,
  and Build Tools `36.0.0`.
- Reused cached Gradle `8.13` and generated the project wrapper with
  `gradle wrapper --offline --gradle-version 8.13 --distribution-type bin`.
- Reused cached Android Gradle Plugin `8.13.2` and Kotlin plugins `2.2.21`. The initial
  Kotlin plugin version `2.2.20` was not cached, so the project now pins the available
  compatible patch release.
- Reused cached Compose BOM `2026.06.01`, which maps to Compose `1.11.4` and supports
  compile SDK 35+ with Android Gradle Plugin 8.6+. The published `2026.09.00` BOM maps to
  Compose `1.12.1`, which requires compile SDK 37 and Android Gradle Plugin 9.1.0, so it
  was incompatible with the available SDK and project plugin. The initially selected
  `2026.08.01` was not a published Maven version.
- Reused cached OkHttp `5.4.0`; the initial `4.12.0` was not cached.
- `com.mediasfu:mediasoup-client:1.0.8` was not present in `~/.gradle` or `~/.m2`. Its
  Maven Central POM and AAR endpoint were verified before resolution. Gradle downloaded
  the declared `1.0.8` AAR, POM, and Gradle module metadata through the existing Clash
  proxy while running `:app:compileDebugKotlin`; the downloaded AAR is now cached under
  `~/.gradle/caches/modules-2/files-2.1/com.mediasfu/mediasoup-client/1.0.8`. The first
  online build then exposed an incompatible Compose BOM selection; compile verification
  is pending with the compatible cached BOM.

## Changes

Pending final implementation summary.

## Verification

- Wrapper task: successful with cached Gradle `8.13` and offline dependency resolution.
- `:app:compileDebugKotlin --offline`: initially stopped before Kotlin compilation because
  the required MediaSFU AAR was absent from the local dependency cache.
- The first online `:app:compileDebugKotlin` resolved MediaSFU but failed AAR metadata
  checks because the selected Compose BOM required AGP 9.1.0 and API 37.
- Device or emulator verification: pending.

## Follow-up validation

- Fixed the Kotlin compile errors in server URL handling, generic JSON decoding, and
  experimental Compose Material APIs. Added protocol model tests for channel, joined
  message, and voice producer payloads.
- Added cleanup for connection failures and disconnect-triggered voice teardown, improved
  message-list scrolling and remote video track identity, and routed speaker selection
  through the Android communication-device API where available.
- Removed unused camera and external-storage permissions inherited from the mediasoup AAR.
  The packaged APK now contains only the app's network, microphone, notification, and
  foreground-service permissions, plus mediasoup's audio/network permissions.
- `:app:testDebugUnitTest`, `:app:assembleDebug`, and `:app:lintDebug` passed offline.
  All 3 protocol model tests passed. Lint reported 0 errors and 11 warnings, consisting of
  dependency update suggestions and the older-API locale config and backup attributes.
- Debug APK produced at `app/build/outputs/apk/debug/app-debug.apk` (71 MB). The current
  environment has no `adb`, so installation and device-level login, messaging, voice, and
  screen-share verification remain pending.
- Build outputs remain in `app/build` (about 274 MB); no cleanup was performed pending
  user approval.

## Launcher icon follow-up

- Kept the shared `apps/assets/cove-icon.png` unchanged. The Android launcher copy had an
  opaque dark outer keyline in the source pixels, so the Android-only bitmap was inset by
  2 pixels and resampled to the original 1013 × 1013 size. Its alpha-rounded rectangle
  silhouette and transparent corners are preserved.
- Rebuilt `:app:assembleDebug` offline and verified the packaged launcher bitmap checksum
  matches the updated Android resource. Device launcher appearance still needs on-device
  confirmation because no `adb` device is available here.

## Build cache cleanup and APK handoff

- After user approval, moved `app/build` (273 MB) and the project-local `.gradle` cache
  (4.3 MB) to `~/.Trash/2026-10-07-142909-cove-build/apps/android/`, preserving their
  relative paths. Xcode DerivedData was left untouched because it contains caches for
  unrelated projects.
- Copied the verified 71 MB debug APK to `~/Downloads/cove-android-debug-2026-10-07.apk`
  before moving build outputs. The source and delivered APK SHA-256 values match:
  `b8568b64756b707234f784282bf0d7b34ba5e2ab1cb4afab2c1a569d5af67963`.
