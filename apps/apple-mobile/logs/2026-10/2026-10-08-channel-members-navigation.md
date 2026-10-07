# Channel and direct-message navigation adjustment

## Changes

- Removed the server member list from the channels screen so it only contains channel categories and channels.
- Updated the channel search placeholder in all five supported locales to indicate it searches channels only.
- Confirmed the Direct Messages tab already has a top-right plus button that opens the new-message member picker.

## Verification

- `plutil -lint` passed for all five localized string files.
- iOS Simulator build for scheme `Sharkord` passed with code signing disabled.
- Confirmed `MembersSection` is no longer used by the channels screen; the existing Direct Messages plus button opens the new-message member picker.
