# Remove redundant microphone hint

## Changes

- Removed the inline “turn on speaker output before enabling your microphone” message from the
  Android voice room. The disabled microphone control remains the visible state cue, and the
  existing guard against enabling the microphone while speaker output is off is unchanged.
- Removed the now-unused hint string from all five Android locales.
- Advanced Android to version `1.11`, build `12`, and synchronized the iPhone and Live Activity
  version settings as required for a native client change.

## Verification

- Android unit tests, lint, and Debug build passed. Existing Gradle, manifest, and Android API
  deprecation warnings remain.
- No physical device was operated; visual confirmation remains with the user.
