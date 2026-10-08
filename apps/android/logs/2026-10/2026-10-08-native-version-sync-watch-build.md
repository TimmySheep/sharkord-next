# Native version sync for Apple Watch build fix

## Changes

- Kept Android aligned with the iPhone at version `1.16`, build `17`, while repairing the shared Apple Watch build. Apple Watch is version `1.10`, build `11`.

## Verification

- Read back Android `versionName` and `versionCode` from `app/build.gradle.kts` and confirmed they match the iPhone target's `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- Android compilation was not run because the project's Gradle 8.13 wrapper distribution is not cached locally; no dependency was downloaded.
