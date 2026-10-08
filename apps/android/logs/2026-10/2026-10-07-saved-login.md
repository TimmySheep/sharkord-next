# Android saved sign-in

- Added Android Keystore-backed AES-GCM storage for login credentials, including an optional
  server password. SharedPreferences contains only the encrypted payload; no credentials are
  written to logs.
- The connect screen now remembers the account by default after a successful login, attempts
  saved sign-in at app startup, offers a compact saved-account sign-in action, and lets the user
  forget the saved account. Turning off remember-login clears the saved payload. Server login
  and authorization are still performed normally.
- Added codec tests for all credential fields, Unicode and malformed trailing data. Added the
  new connect labels to all five Android locales.
- Verification passed: `:app:testDebugUnitTest`, `:app:lintDebug`, `:app:assembleDebug`,
  `bun run magic`, `bun run synci18n`, and `git diff --check`. No Android device was connected
  or operated.
