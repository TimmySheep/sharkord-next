# Connect screen copy adjustment

## Changes

- Removed the introductory real-server feature claim from the iPhone login screen in all five supported locales.
- Removed the optional marker from the server-password label and moved the optional hint into the input placeholder in all five locales.
- Removed the settings language-support hint, disconnect explanation, and entire About This Version card.
- Moved Dynamic Island preview and diagnostic logs behind a Developer settings page; removed the diagnostic privacy hint.

## Verification

- `plutil -lint` passed for all five localized string files.
- iOS Simulator build for scheme `Sharkord` passed with code signing disabled.
- All five localized strings files passed `plutil -lint`; the removed settings hints and About keys have no remaining references.
- iOS Simulator build for scheme `Sharkord` passed with code signing disabled after the settings changes.
