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

### 2026-10-31 Windows device options (gaming PC, OpenCode mimo-v2.6-flash)

What changed (branch `feat/windows-parity`, apps/windows only, 6 commits):

- Voice worker: DTLN noise-suppression mode wired through the bundled
  `dtln-processor.js` worklet (16 kHz mono capture, single AudioContext,
  readiness handshake with timeout and processor-error reporting); optional
  noise gate via the web `noise-gate-processor.js` worklet (hold 100 ms,
  live threshold updates, clamp -70..0 dB, default off at -48 dB); screen
  share now honors the cursor mode and bitrate options (default "always",
  6000 kbps with Google codec bitrate hints); own-video preview mirroring
  (`scaleX(-1)`).
- Media bridge: `setNoiseGate` API, `level` meter API (RMS to dB, -70..0 dB
  window mapped to 0..100%), screen codec resolution by mimeType with router
  fallback, and the matching option defaults.
- Device dialog: DTLN entry in the noise-mode box, noise-gate toggle with a
  threshold slider, screen codec/cursor combo boxes, screen bitrate slider
  capped by the server's WebRtcMaxBitrate, mirror toggle, and a live level
  meter that only runs while the dialog owns the media webview.
- i18n: one new key, `noiseGateThresholdLabel`, translated in all 10 media
  locale tables; every other label reuses the shared `settings`/`media` keys.
- Deferred: `restrictOwnAudio`/`suppressLocalAudioPlayback` (experimental
  Chromium-only display-capture constraints), documented in the taskbook.

Verification (headless, no GUI launched):

- `dotnet build src/Sharkord.App/Sharkord.App.csproj -p:Platform=x64`:
  succeeded, 0 warnings, 0 errors (SDK 10.0.403, installed user-local to
  `~/.dotnet` because no .NET 10 SDK was present on this machine).
- `dotnet test tests/Sharkord.Core.Tests/Sharkord.Core.Tests.csproj`:
  217 passed, 0 failed (was 206; +10 locale theory cases, +1 source-contract
  test asserting the dialog/worker wiring and worklet asset presence).
- `node --test apps/windows/tests/media-controls.test.cjs`: 12 passed, 0
  failed (was 7; new cases cover setNoiseGate/mirror on options, screen
  codec resolution and bitrate hints, the level meter lifecycle and video
  preview mirroring).
- `node --check` on both media scripts: exit 0.

Remaining gaps: macOS side of phase 3 untouched in this session; GUI/device
acceptance still deferred per the phase-2 rule; the deferred experimental
display-capture constraints above.

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

## 2026-10-31 — Phase 3 merge + bundle/TS divergence repair — DONE

Both phase-3 branches merged into `development` and pushed (macOS merge
`490eeab0`, Windows merge `42405c3d`). One taskbook parity-table row conflicted
(both sides rewrote the same DEVICE row) and one voice-worker.js conflict; both
resolved by merging the two descriptions and rebuilding from source.

**Incident worth remembering:** the git-tracked voice-worker bundles had
accumulated DIRECT hand-edits across phases 1-3 (every dev machine lacked bun,
so agents edited the built JS instead of the TypeScript source). The first
rebuild from source therefore silently dropped every bundle-only feature: the
`window.coveMediaOptions` option channel (Windows C# injects it), external-stream
consumption, qualityLayers passthrough, the phase-3 noise gate / DTLN / screen
cursor+bitrate / mirroring work, and more. Detected by grepping the old vs new
bundles for feature markers before calling it done.

Repair (`90307711`): every bundle-only feature was ported back into
`apps/client/scripts/voice-worker.ts` with platform-safe fallbacks — the
Windows-only globals (`coveMediaOptions`, `videoProduceOptions`) are read
optionally so macOS behaviour is unchanged — then both bundles were rebuilt
from the single source of truth. Verified: `tsc --noEmit` clean, `node --test
media-controls` 12/12, feature-marker grep confirms all APIs present in both
bundles. Runtime device acceptance is still pending (GUI deferred).

**Phase 3 final state:** macOS 6 commits (150 swift tests), Windows 6 commits
(217 dotnet + 12 node tests), one TS port + rebuild. GUI/device acceptance
remains deferred; the manual checklist in the taskbook is the acceptance path.
