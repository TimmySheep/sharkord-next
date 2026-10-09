# iPhone-managed Apple Watch account

## Changes

- Added an Apple Watch account section to iPhone settings. It shows pairing and Watch app installation state, proposes the signed-in identity with a `-watch` suffix, accepts an optional invite code, and creates one separate Watch login.
- The server's existing `/login` registration rules remain authoritative. Registration still requires open registration or a valid invite; an existing account is not overwritten, and the suggested identity can be edited if it is already taken.
- A unique password is generated on iPhone and retained in Keychain. Credentials are sent through WatchConnectivity's application context and reliable user-info transfer, and stored in the Watch Keychain when received.
- The Watch's manual sign-in form remains available. Receiving a linked account only saves credentials; it does not leave the offline preview or automatically sign in.
- Added English, Simplified Chinese, German, Spanish, and French strings.

## Verification

- iPhone scheme built successfully for a generic iOS Simulator destination.
- Watch scheme built successfully for a generic watchOS Simulator destination.
- The Xcode project and five localization files passed `plutil -lint`; all five localization key sets match.
- No paired iPhone/Watch runtime transfer was exercised, so physical pairing and credential receipt still need on-device acceptance.
