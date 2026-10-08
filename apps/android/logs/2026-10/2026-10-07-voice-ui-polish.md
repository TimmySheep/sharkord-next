# Android voice-channel interface polish

- Removed the channel-topic subtitle from channel detail, leaving the channel name as the page
  heading.
- Replaced the voice-room member-count heading and horizontal chips with wrapping square
  participant tiles. Participants remain visible before joining; the join button is retained.
- Standardized the microphone, speaker, camera, and screen-share controls as equal-width,
  labeled tonal buttons. Hang-up is the fifth control and remains highlighted in red. Camera
  switching remains available as a small secondary action on the camera control.
- Verification passed: `:app:testDebugUnitTest`, `:app:lintDebug`, `:app:assembleDebug`, and
  `git diff --check`. `bun run magic` completed with existing lint warnings and no errors.
- No Android device was operated; visual acceptance remains pending.
- Reworked the voice stage to fill the available page and choose its grid from the measured
  portrait or landscape proportions, following the Web voice grid's 1.5 target aspect ratio.
  Participant avatars scale with their tiles; webcam tracks share the matching participant tile,
  and screen-share tracks occupy their own tile. The microphone and camera controls were not
  changed.
- Added layout calculation tests for one participant, a portrait group, a wide stage, and an
  unmeasured stage. Unit tests, lint, and Debug build passed; `bun run magic` completed with the
  repository's existing lint warnings and no errors. No Android device was operated.
- Advanced the synchronized Android and iPhone release versions to 1.2 and build number 3.
