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
