# Apple Watch saved sign-in

- Added a Watch-only Keychain credential store using a device-only accessibility class. It
  stores the account and optional server password; the password is not written to UserDefaults
  or logs.
- The Watch connect screen now attempts saved sign-in at startup, offers a saved-account quick
  action, includes a remember-and-auto-sign-in toggle, and allows the saved account to be
  forgotten. Credentials are saved only after a successful server join, and normal server
  authentication remains in place.
- Kept the Watch's server-password challenge usable during automatic or manual sign-in and
  added all new labels to the five Apple mobile locales.
- Verification passed: `xcodebuild -project Sharkord.xcodeproj -scheme SharkordWatch
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build`,
  `bun run magic`, `bun run synci18n`, and `git diff --check`. No Watch or simulator was
  operated.
