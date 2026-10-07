# Android connect-screen theme contrast

- Set the remember-login label to `MaterialTheme.colorScheme.onSurface` so its foreground follows
  the active light or dark theme.
- Began the requested release sequence at Android `versionName` 1.1 and incremented `versionCode`
  to 2. The iPhone app version was synchronized separately.
- Verification passed: `:app:testDebugUnitTest`, `:app:lintDebug`, `:app:assembleDebug`,
  `bun run magic`, and `git diff --check`. `bun run magic` reported existing repository lint
  warnings and no errors. No Android device was operated.
