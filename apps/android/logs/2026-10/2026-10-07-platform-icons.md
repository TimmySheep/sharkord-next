# Android launcher icon appearance variants

- Replaced the launcher icon with the supplied light artwork and added the supplied dark
  artwork under `mipmap-night-nodpi`. Android resolves the night resource in dark system
  appearance and falls back to the light `mipmap-nodpi` icon otherwise.
- Advanced Android to version `1.7`, build `8`.
- Verified the APK packages both `nodpi` and `night-nodpi` launcher resources and reports
  version `1.7` / `8`. Android unit tests, lint, and Debug build passed. Existing Gradle
  deprecation and manifest warnings remain.
- The change remains local and has not been pushed to GitHub.
