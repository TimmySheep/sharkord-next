# iPhone and Apple Watch diagnostic logs and export

## Changes

- Added a shared local diagnostics logger to the iPhone and Watch targets. Each app writes to its
  own sandbox, keeps bounded rolling files outside device backups, records startup metadata and
  selected session, voice, credential-storage, and crash errors, and redacts common credential
  assignments, query parameters, and Bearer tokens.
- Added an iPhone diagnostics screen in Settings and a login-screen shortcut. It previews recent
  logs and shares a generated text export through the system share UI.
- Added a Watch diagnostics screen reachable from the app navigation. It previews logs and offers
  a system share action for an exported text file.
- Added localized UI strings in English, Simplified Chinese, German, Spanish, and French.
- Advanced iPhone and Live Activity to version `1.10`, build `11`; advanced Apple Watch to
  version `1.8`, build `9`.

## Verification

- The Watch Simulator build passed.
- The iOS Simulator build remains blocked by the existing non-exhaustive phase switch in
  `Sharkord/RootView.swift`, which omits `.awaitingServerPassword`. This file was not changed for
  the diagnostics feature.
- No iPhone or Apple Watch device was operated; visual and export acceptance remains pending.
