# Android unified navigation refactor

## Changes

- Replaced the three-tab workspace with a server-branded navigation list and responsive channel
  detail layout. DM and server category headings share compact collapsible styling, with per-server
  persisted collapse state and stable list keys.
- Displayed up to three most-recent real DM conversations, unread counts, a full searchable DM list,
  and the existing create/open conversation flow. Server availability comes from
  `publicSettings.directMessagesEnabled`. New and updated DM messages refresh conversation order
  through the existing `dms.get` procedure. Saved DM restoration waits for that query to finish.
- Filtered navigation channels using the joined channel-permission map, kept service ordering, and
  retained unread and voice participant indicators.
- Added current-user, microphone, deafen, and Settings controls at the bottom, plus the connected or
  connecting voice bar with room navigation and leave action. Existing voice engine operations and
  deafen microphone-restore semantics remain the source of truth.
- Reused existing channel chat, message/file search, threads, attachments, profile settings, media
  controls, and microphone-on-join behavior. Avatar downloads are asynchronous and use a bounded
  in-memory bitmap cache.
- Android is `1.1` / build `23`. The iPhone app and Live Activity version metadata were synchronized
  to `1.1` / build `20` under the native-client version rule; Apple Watch settings were left alone.

## Compatibility and verification

- The local `@sharkord/server` package is version `0.0.25`. The Android client uses existing `dms.get`,
  `dms.open`, `voice.join`, and channel permission data. No server changes were made. The deployed
  server version was not checked.
- Android verification passed: 34 unit tests, `lintDebug`, and `assembleDebug`. Repository
  `bun run magic`, script `bun run synci18n`, `plutil -lint` on the Xcode project, and
  `git diff --check` passed. The build retains existing Android API deprecation and manifest merge
  warnings; repository lint retains existing warnings.
- APK: `~/Downloads/Cove-1.1-build23-debug.apk`, 71 MB, SHA-256
  `2b17a6d6f9483ca0134b368f6a2d873e2a9994ef688c1d63e12570ef6993c5e6`. Manifest version `1.1` /
  code `23` and APK signature were verified.
- A connected Android device was visible through ADB but was not operated or installed. No runtime
  screenshots or before/after performance measurements were collected. Manual device acceptance
  remains pending.

## Channel visibility correction

- Removed the second client-side `VIEW_CHANNEL` filter from the navigation list and saved-channel
  restoration. `joinServer` already returns the server-authorized channel list; checking a possibly
  incomplete permission map again could hide channels that were already returned to the user.
- Added a regression test for server-returned channels when the permission map is incomplete.
- Android unit tests passed: 35 tests, with no failures or skips. `lintDebug`, `assembleDebug`,
  `bun run magic`, Xcode project `plutil -lint`, and `git diff --check` passed. Existing warnings
  remain. No device was operated, so runtime confirmation is still pending.
- Advanced Android to `1.2` / build `24` and synchronized the iPhone app and Live Activity metadata
  to `1.2` / build `21`. Apple Watch was not changed and no iOS build was run.
- Delivered `~/Downloads/Cove-1.2-build24-debug.apk` (71 MB), SHA-256
  `02aa7fc4f05ab5aa4c91b7589f848796bed36c70d510bfef8e4133d4832820e5`. APK version metadata and
  v2 signature were verified. The previous `1.1` APK remains untouched.

## Server branding banner at navigation top

- Added the existing rounded server-branding card above the DM and channel sections on the unified
  navigation page. It loads the server's public logo, crops it as a wide banner, overlays the server
  name and address, and is omitted when no logo is configured. The same component remains available
  to the channel destination.
- The current server contract exposes `logo` from `/info`, but no independent server-banner field.
  No server API, schema, or migration was added; the visible banner uses the existing logo asset.
- Android unit tests passed: 35 tests, with no failures or skips. `lintDebug`, `assembleDebug`,
  `bun run magic`, Xcode project `plutil -lint`, and `git diff --check` passed. No device was
  operated, so visual acceptance remains pending.
- Advanced Android to `1.3` / build `25` and synchronized iPhone app and Live Activity metadata to
  `1.3` / build `22`. Apple Watch was not changed and no iOS build was run.
- Delivered `~/Downloads/Cove-1.3-build25-debug.apk` (71 MB), SHA-256
  `493630c6be7bd428e16a7ec7aa654978b451b56b38f2eab7293f9170ef2d2f1c`. APK version metadata and
  v2 signature were verified.

## System gesture safe-area spacing

- Applied Android navigation-bar insets to the persistent bottom bars in both compact and wide
  layouts. This keeps the user controls above the system gesture/navigation area while preserving
  the existing behavior that hides the bars when the keyboard is open.
- Android unit tests passed: 35 tests, with no failures or skips. `lintDebug`, `assembleDebug`,
  `bun run magic`, Xcode project `plutil -lint`, and `git diff --check` passed. No device was
  operated, so the screenshot-level spacing still needs physical-device confirmation.
- Advanced Android to `1.4` / build `26` and synchronized iPhone app and Live Activity metadata to
  `1.4` / build `23`. Apple Watch was not changed and no iOS build was run.
- Delivered `~/Downloads/Cove-1.4-build26-debug.apk` (71 MB), SHA-256
  `314063e0cd466c764995c7ce7ba37ce0cd0ebf030a85f266275050ac7a71b7ae`. APK version metadata and
  v2 signature were verified.
