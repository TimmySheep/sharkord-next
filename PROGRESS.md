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
