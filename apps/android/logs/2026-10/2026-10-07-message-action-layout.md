# Android message action hierarchy

- Replaced the prominent full-width reply control and separate pin row with three equal-width
  bottom actions: reply, thread/replies, and pin/unpin. Each uses the same tonal button style and
  centered icon-over-label layout; the quick-reaction row remains above them.
- Kept message-owner edit and delete actions separate and above the shared bottom action row.
- Advanced Android to version `1.9`, build `10`; synchronized iPhone and Live Activity versions
  to `1.9`, build `10`. Apple Watch remains at `1.7`, build `8`.
- Android unit tests, lint, and Debug build passed. No simulator or physical device was operated,
  so visual acceptance remains pending. The change is local and has not been pushed to GitHub.
