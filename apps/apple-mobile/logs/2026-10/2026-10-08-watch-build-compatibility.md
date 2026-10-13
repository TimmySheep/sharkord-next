# Apple Watch build compatibility

## Changes

- Replaced the shared diagnostic logger's unsupported watchOS `homeDirectoryForCurrentUser` fallback with `FileManager.temporaryDirectory`. The app-support search path remains first, preserving each platform's sandboxed Application Support directory when available.
- Excluded `x86_64` from the Watch Simulator architectures because the local `SharkordCore` package output is arm64-only; physical Watch builds are unaffected.
- Advanced iPhone and Live Activity to version `1.16`, build `17`, Android to `1.16`, build `17`, and Apple Watch to `1.10`, build `11`.

## Verification

- `plutil -lint` accepted the Xcode project.
- Xcode resolved the Watch Simulator architecture to `arm64` with `x86_64` excluded.
- `SharkordWatch` built successfully for the Apple Watch Ultra 4 simulator and generic watchOS device destination, without a command-line architecture override.
- The iPhone `Sharkord` scheme built successfully for a generic iOS Simulator destination.
- Swift package tests passed: 33 `SharkordCore` tests and 51 `SharkordMac` tests, with no failures. Existing skipped integration tests and an unrelated `Composer.swift` warning remain.
- Android compilation was not run because the project's Gradle 8.13 wrapper distribution is not cached locally; no dependency was downloaded.
