# Cove Desktop — Progress Log

> Living progress document for the native desktop clients (Windows + macOS).
> Maintained by Hermes (Timmy's assistant). Every work session appends here;
> pushed to GitHub so all machines (Timmy's NUC, MacBook Air/Pro, the friend's
> Windows PC) share one source of truth. Append-only: never rewrite history.

## 2026-10-31 — Phase 1+2 (friend's PC, Codex gpt-6-astra → gpt-6.1-sol) — DONE

- Phase 1 (25 commits): Windows build health restored (.NET 10), Discord-style
  dark workspace on both platforms, wire-compat fixes, message perf work.
  Windows x64 build 0 warnings / 0 errors, 141 tests green.
- Phase 2 (40 commits): web-parity push — Windows messaging/navigation, rich
  text, emoji catalog, attachments w/ progress, voice controls, account
  restore/admin; macOS messaging/upload/recovery fixes. 206 local + 7 media +
  2 real-server (voice.timhuang.net, test account 测试) tests green.
- macOS verified on MacBook Pro: `swift build` OK (16s), `swift test` 68/68.
- GUI acceptance DEFERRED (friend's PC is in active use; no CUA there).
  Manual checklist lives in taskbook/2026-10-desktop-feature-parity-acceptance.md.
- Merged to `development` as bd872163. All pushed to GitHub.
- Leftovers: macOS editor/device/admin surfaces + detailed Windows device
  options still short of full parity (see parity table in the taskbook).

## 2026-10-31 — Phase 3 (Timmy's own machines, OpenCode mimo-v2.6-flash) — IN PROGRESS

- Goal: continue the remaining parity work (macOS editor/device/admin surfaces,
  Windows device options) on Timmy's MacBook Pro (macOS side, OpenCode already
  installed & verified with mimo-v2.6-flash) and Windows gaming PC (Windows
  side), driven by OpenCode, model pinned to xiaomi-token-plan / mimo-v2.6-flash.
- Constraints carried over: no foreground CUA on the FRIEND's PC (unchanged);
  on Timmy's own machines GUI runs are allowed only with Timmy watching.
- Status: Air ready (opencode 1.18.31); Windows PC waking via WOL.
- This session: repo cloned on both machines, tasks dispatched, results TBD.

<!-- Hermes appends below as work lands. -->

## 2026-10-31 — Phase 3 macOS parity (OpenCode mimo-v2.6-flash, branch `feat/macos-parity`) — DONE

Closed the three macOS gaps the parity table flagged: EDITOR suggestion menus,
ADMIN branding/invite/moderation detail, and DEVICE device selection + capture
preferences. Work is in `apps/macos` only, except one unavoidable worker change
(documented below). Four local commits on `feat/macos-parity`, **not pushed**.

- **EDITOR** (`78221d3e`, `9d383c9f`): `MessageHTML.fromComposerText`/`toComposerText`
  give the composer markdown-style rich text with a full id round trip
  (`@[label](user:id)`, `#[label](channel:id)`, `:custom:`, unicode glyph), and
  `ComposerSuggestion.swift` adds the @/#/: suggestion menu (prefix-first +
  shorter-first ranking, Up/Down/Enter/Tab accept, Escape dismiss). Composer send
  and edit paths rewired. 24 MessageHTML + 6 suggestion tests.
- **ADMIN** (`29b9a411`, `5d7ab3cc`): server logo upload, invite role picker +
  custom code + per-row role/expiry/active-expired status, and a rewritten user
  detail sheet with ban reason/bannedAt, OIDC marker, per-role remove/assign and
  kick/ban/unban. One new `macos` locale key (`uploadServerLogo`) across all 10
  languages.
- **DEVICE** (`09c313f3`): new `DevicesSettingsView` with input/output/webcam
  pickers, echo-cancellation and auto-gain toggles, and a microphone test with a
  live level meter. `VoiceDeviceSettings` (SharkordCore) persists selections in
  UserDefaults; the controller pushes them into the worker and reopens the
  affected capture so a change takes effect without a rejoin. A saved id whose
  device is unplugged falls back to the platform default. 7 new core tests.
- Verification: `cd apps/macos && swift build` OK, `swift test` green —
  XCTest 67+2, Swift Testing 81 (150 total, 0 failures), up from 68 at baseline.
  Headless only; no GUI/CUA/screenshots, so runtime device behaviour is
  source-reviewed, not device-accepted (matches the deferred GUI acceptance).
- **Outstanding:** the voice worker JS bundle is a git-tracked build artifact and
  is still stale, so the DEVICE pickers will be empty at runtime until it is
  regenerated. That needs `bun install` (workspace deps are not installed here)
  then `bun run build-desktop-voice`, which rebuilds the macOS **and** Windows
  bundles (known cross-app side effect). Not done: it needs Timmy's approval to
  install dependencies, and the rebuild was left out to avoid an unapproved
  Windows-side change.
- Remaining DEVICE gaps (unchanged, still PARTIAL): webcam resolution/framerate,
  screen codec/bitrate/cursor, noise gate + threshold, simulcast. All reuse
  existing `settings`-ns keys when picked up later; no new locale keys were
  needed for this round.
