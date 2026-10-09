# Live Activity microphone control

## Changes

- Added a microphone state control at the right edge of the expanded Dynamic Island and lock-screen Live Activity, leaving existing content and compact/minimal presentations unchanged.
- The control opens the Cove app through its registered URL scheme. The app navigates to the active voice channel, toggles the existing VoiceEngine microphone path, and refreshes Live Activity state. Deafen and microphone-permission protections remain in effect.
- Added localized VoiceOver labels in English, Simplified Chinese, German, Spanish, and French.

## Verification

- The iOS Simulator scheme, including the Live Activity extension, built successfully.
- Confirmed the app bundle registers the `cove` URL scheme and the Live Activity extension contains all five localized string tables.
- All five localization key sets match, plist/project validation passed, and `git diff --check` passed.
- No active voice session was available for an end-to-end tap-to-toggle test; the deep-link and microphone action are build-verified but still need runtime acceptance during a real call.
