# Android home direct-message section visibility

- Hide the direct-message section from the home navigation when there are no valid conversations.
  Keep it visible once at least one conversation is available; other channel sections remain intact.
- Added unit coverage for zero and nonzero conversation counts.
- `./gradlew testDebugUnitTest lintDebug assembleDebug` passed. No device was operated.
