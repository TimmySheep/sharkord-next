# Android settings language and about section

- Removed the fixed “System default” subtitle from the language selector so the selected locale
  appears only once and is correct for every selection.
- Moved About into the scrollable settings content and added a card showing the app name and
  `BuildConfig.VERSION_NAME`. The disconnect action remains anchored below the scroll area.
- Added localized app-version text in English, Simplified Chinese, German, Spanish, and French.
  `bun run synci18n` reported all translations up to date.
- Android unit tests, lint, and Debug build passed. `bun run magic` completed with existing
  repository lint warnings and no errors; `git diff --check` passed. No Android device was operated.
- Synchronized Android and iPhone versions to 1.4 and build number 5; Apple Watch remains unchanged.
