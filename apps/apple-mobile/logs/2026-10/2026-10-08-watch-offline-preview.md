# Apple Watch offline preview

## Changes

- Made the Watch app open a clearly labelled offline preview instead of the sign-in screen when no server session is active.
- Added sample voice channels, participants, and messages. Preview controls do not start a real radio session or send server requests.
- Kept server sign-in available from the preview and dismiss the sign-in screen after a successful connection.
- Stopped automatically connecting with saved credentials at launch so the preview remains the initial screen.
- Localized preview labels and sample content in English, Simplified Chinese, German, Spanish, and French.
- Advanced Android and iPhone to version `1.17`, build `18`; advanced Apple Watch to version `1.11`, build `12`.

## Verification

- The Watch Simulator build passed for the Apple Watch Ultra 4 destination with the project architecture settings.
- The iPhone app built successfully for a generic iOS Simulator destination.
- The Xcode project and all five `Localizable.strings` files passed `plutil -lint`.
- No simulator was launched and no physical Apple Watch was operated; runtime visual acceptance remains pending.
