# Android message-action cleanup

- Removed the per-message thread-start/reply-count chip from the chat timeline. The existing
  action sheet opened from the three-dot menu now provides the same thread action; existing reply
  counts are retained in its label. Reaction chips remain inline.
- Verification passed: `:app:testDebugUnitTest`, `:app:lintDebug`, `:app:assembleDebug`, and
  `git diff --check`. `bun run magic` completed with existing lint warnings and no errors.
- No Android device was operated.
- Follow-up: attachment-only messages no longer show the empty-message placeholder in the action
  sheet. Emoji reactions now appear before a circular, icon-only reply button; the thread action
  remains in the sheet.
- Follow-up verification passed: Android unit tests, lint, Debug build, `bun run magic`, and
  `git diff --check`. No Android device was operated.
- Screenshot follow-up: emoji-only messages no longer repeat their content above the quick-reaction
  strip; the strip scrolls horizontally. Replaced the separate reply and thread rows with one reply
  dropdown that preserves both actions.
- Added tests for emoji-only detection, including joined emoji and keycaps. Android unit tests, lint,
  and Debug build passed. `bun run magic` completed with existing repository lint warnings and no
  errors; `git diff --check` passed. No Android device was operated.
- Synchronized Android and iPhone versions to 1.3 and build number 4; Apple Watch remains unchanged.
