# cove for Android

Native Android client built with Kotlin, Jetpack Compose, and Material 3. The compact
layout uses the three top-level destinations Channels, Messages, and Settings. On wide
windows the app uses a navigation rail and shows channel or conversation lists alongside
their content.

The client speaks the same HTTP and tRPC WebSocket protocol as the Apple clients. The
implementation is being brought to parity with the iOS/iPadOS feature set, including
mediasoup voice and Android MediaProjection screen sharing.

## Build

```bash
./gradlew :app:assembleDebug
```

Use JDK 17 or newer and point `ANDROID_HOME` at an SDK with API 36 and Build Tools 36.
The Android SDK and JDK locations are intentionally not checked into this project.

The app uses the shared launcher artwork at `apps/assets/cove-icon.png`. Material 3
dynamic color follows the user's system appearance on supported Android versions; the
fallback color scheme is derived from Cove's blue and aqua brand colors.

## Implementation references

- [Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)
- [Build adaptive navigation](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation)
- [Window size classes](https://developer.android.com/develop/ui/compose/layouts/adaptive/window-size-classes)
- [Media projection](https://developer.android.com/media/grow/media-projection)
