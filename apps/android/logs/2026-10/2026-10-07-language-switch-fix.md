# Android in-app language switching fix

- The language picker called `AppCompatDelegate.setApplicationLocales`, but its Compose host
  extended `ComponentActivity`. Android's per-app language guidance requires `AppCompatActivity`
  for this AppCompatDelegate approach with Compose; without it, locale changes do not reach the
  activity correctly.
- Changed `MainActivity` to `AppCompatActivity`, changed the app theme to an AppCompat DayNight
  theme, and enabled AppCompat locale storage for Android 12 and earlier.
- Advanced Android to version `1.8`, build `9`; the iPhone app version was synchronized as
  required by the project versioning rule.
- Android unit tests, lint, and Debug build passed. The built APK reports version `1.8` / `9`,
  and its merged manifest includes `AppLocalesMetadataHolderService` with `autoStoreLocales=true`.
  Existing Gradle deprecation and manifest warnings remain. No device was operated, so device-level
  language switching still needs user confirmation.
- The fix is local and has not been pushed to GitHub.
