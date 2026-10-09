# Synchronize mobile version for iOS media repair

## Change and verification

- No Android media implementation changed. Synchronized Android to `1.28` / code `50` with iPhone `1.28` / build `47` for the paired native-client release.
- `./gradlew :app:testDebugUnitTest :app:lintDebug --console=plain` passed: 74 tests, zero failures, errors, or skips.
- No APK was assembled or installed.
