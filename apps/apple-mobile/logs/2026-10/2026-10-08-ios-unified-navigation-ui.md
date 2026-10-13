# iOS unified navigation and status UI

## Scope

- Implemented the iOS portion of `UI_recreate/taskbook 任务书.rtf`, preserving the existing
  Sharkord session, messaging, search, voice, profile, settings, Live Activity, and Watch flows.

## Changes

- Replaced the Channels / Direct Messages / Settings tab layout with one navigation stack. The
  server name and message-search action remain in the navigation header; channels, DMs, and
  settings are routes in the same stack.
- Unified recent DMs and server-returned channel categories in a compact list. DMs and categories
  use collapsible headers whose state is stored locally; the list shows at most three recent DMs,
  unread indicators, category-ordered text and voice channels, voice participant counts, and an
  uncategorized group when needed. Added local filtering for channels and DMs.
- Added a fixed user status bar with the current account avatar/name and real microphone, deafen,
  and settings actions. Added a conditional voice status/leave bar above it, driven by the current
  voice lifecycle and channel.
- Restored system-following light/dark appearance and added the new navigation/status strings in
  all five supported locales.

## Verification

- iOS Simulator build passed for scheme `Sharkord` using the existing local Xcode package cache.
- `git diff --check` passed.
- `plutil -lint` passed for all five localization files; all five have the same 227 localization
  keys.
- Physical-device layout, live server data, and voice controls remain pending device acceptance.

## Cleanup

- The simulator build output remains in `/private/var/folders/p1/3pqx3j392m381v0g293m9rgc0000gn/T/opencode/apple-requirements-build` and was not removed.
