# Native version sync for Apple Watch preview

## Changes

- Kept Android aligned with iPhone at version `1.17`, build `18`, while changing the Apple Watch launch experience. Apple Watch is version `1.11`, build `12`.

## Verification

- Read back Android `versionName` and `versionCode` from `app/build.gradle.kts` and confirmed they match the iPhone target's `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- Android application source was not changed for this feature, so no Android build was run.
