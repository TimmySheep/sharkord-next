# Voice call notification details and controls

## Changes

- Replaced the generic ongoing-call body with the active voice channel name, a centered-dot
  separator and localized participant count. The subtitle now reflects whether the microphone is
  on or off, and the notification refreshes when channel membership or voice state changes.
- Added notification actions for speaker toggle, microphone toggle and leaving the current voice
  channel. Actions route through the existing voice engine; enabling the microphone from the
  notification also turns speaker output on first when needed. Leaving voice does not disconnect
  the server session.
- Kept the notification ongoing for the full voice-channel session, including when speaker output
  and the microphone are both off. Added localized notification text and participant plurals for
  all five Android locales.
- Advanced Android to version `1.12`, build `13`, and synchronized the iPhone and Live Activity
  versions as required for a native client change.

## Verification

- Android unit tests, lint, and Debug build passed. The four new notification model/action tests
  passed. Existing Android API deprecation and manifest warnings remain.
- No physical device was operated; notification appearance and action behavior still need device
  verification.
