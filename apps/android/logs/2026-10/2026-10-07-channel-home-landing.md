# Android channel-home landing

- Corrected login routing: the first text channel is no longer selected automatically, and login
  no longer immediately opens that channel's message history. The workspace starts on the
  Channels destination with the channel list visible; selecting a channel is explicit.
- This replaces the earlier, incorrect decision to auto-select the first text channel.
- Verification passed: `:app:testDebugUnitTest`, `:app:lintDebug`, and `:app:assembleDebug`;
  `bun run magic`; and `git diff --check`. No Android device was operated, so the final landing
  screen still needs real-device confirmation.
