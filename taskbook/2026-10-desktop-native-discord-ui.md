# Desktop native clients: Discord-style UI and upstream compatibility

## Goal

Continue the native desktop clients on `apps/windows` (C# + WinUI 3) and `apps/macos`
(Swift + SwiftUI). Both stay fully native — no Electron, no cross-platform UI framework.
The visual direction follows Discord's interface design, and protocol/behaviour compatibility
with upstream Sharkord is maximised: the clients must remain drop-in replacements for the
upstream web client against an unmodified server.

## Work areas

1. Windows build health first. The README states the current voice and TreeView changes were
   never rebuilt. Get `apps/windows` compiling clean again (`-p:Platform=x64`, zero errors and
   zero warnings) and make `dotnet test` pass before any UI work starts.
2. Discord-style design language, both platforms.
   - Dark theme as the default appearance, using Discord's palette as the reference:
     chat background ~#313338, channel sidebar ~#2B2D31, deep panels ~#1E1F22, accent
     ~#5865F2. Exact values may be tuned, but the overall tone should read as Discord-familiar.
   - Layout: collapsible category groups in the channel sidebar with `#`-prefixed channel
     names and speaker-prefixed voice channels; optional member list on the right; a bottom-left
     user panel (avatar, name, microphone/deafen/settings controls) where the platform model
     allows it.
   - Message list: grouped consecutive messages (avatar and author name only on the first row
     of a group), muted timestamps, hover action toolbar on each message (react; edit and more
     for own messages), unread and new-messages dividers.
   - Composer: rounded input surface, attachment and emoji buttons, typing indicator.
   - Interactions kept or added: Shift+Enter newline, ArrowUp edits own last message, Escape
     cancels reply/edit, Enter sends.
   - Keep the existing i18n mechanism; no hardcoded English strings in the UI layer (the
     Windows `L10nTests` scan must stay green).
3. Performance on Windows. The message list must stay virtualised; avoid full-list re-renders
   on single-message events; keep `Sharkord.Core` allocation-light on the hot path. Startup
   should not regress — WebView2 remains confined to the media worker.
4. Upstream compatibility audit and hardening.
   - tRPC envelope, `connectionParams` first frame, keepalive, reconnect backoff
     `[1, 2, 4, 8, 8]s`, `POST /login`, `POST /upload` size-must-match-`content-length`,
     `/public` file URLs, and message HTML rendering must stay behaviourally identical to the
     upstream web client. Do not invent new endpoints or diverge in error semantics.
   - Where a cheap conformance test can pin an existing wire behaviour, add it; otherwise
     document any deliberate divergence in the platform README.
   - No server changes. If a server change seems necessary, stop and document it in the
     progress section instead of making it.
5. macOS client. Apply the same design direction in SwiftUI (`DesignSystem.swift` and the
   views). Compilation and `swift test` are impossible on Windows — keep changes conservative
   and syntactically careful, and state in the progress section that macOS verification still
   has to run on a Mac.

## Constraints

- Follow `AGENTS.md` and `CONTRIBUTING.md`: no over-engineering, match existing patterns.
- Do not push to the remote, do not install global toolchains, do not touch the server app or
  the mobile clients except where a shared package change is unavoidable (document it).
- NuGet restore and existing project dependencies are fine.

## Acceptance boundary

- `dotnet build src/Sharkord.App/Sharkord.App.csproj -p:Platform=x64` succeeds with zero
  errors; warnings are listed in the report.
- `dotnet test tests/Sharkord.Core.Tests/Sharkord.Core.Tests.csproj` passes.
- macOS side: changes are code-complete but explicitly marked unverified pending a Mac build
  (`swift build && swift test`).
- Device-level visual acceptance is for the user.

## Progress

- Windows build health was restored before UI work: corrected plugin response handling,
  WinUI color references and TreeView selection, and made source checks accept CRLF checkouts.
  All three Windows projects now target .NET 10 for the installed SDK 10.0.202/runtime 10.0.6.
  No global toolchains were installed or pinned Windows App SDK packages changed. The initial
  x64 build had 0 warnings and 0 errors, and all 91 baseline tests passed.
- Windows now has the native dark workspace, collapsible categories, optional members,
  avatar/microphone/deafen/settings panel, grouped messages, hover/focus actions, unread/new
  dividers, attachments, emoji and typing. Enter/Shift+Enter, ArrowUp edit and Escape cancel
  use the existing keyboard settings. Per-channel drafts survive automatic reconnects;
  explicit login resets prior server state. All ten Windows locale tables were updated.
- Windows performance: retained ListView/ItemsStackPanel virtualization and stable row
  identities, skipped unchanged history via message revisions, coalesced session refreshes,
  and reused unchanged channel/member data. Core avoids full-list sorting for live inserts
  and intermediate JSON strings. WebView2 loads only for voice. A 5,000-row regression test
  confirms a deletion emits one collection removal. No startup/frame-rate benchmark is claimed.
- Compatibility: Windows healthy PONG replies refresh activity, join payloads restore unread
  counts, and message text preserves entities and block/hard-break boundaries. Both desktop
  uploaders encode filenames for the existing server decoder. Added raw-byte HTTP and real
  loopback WebSocket tests for framing, connectionParams, keepalive, errors and public URLs.
  Reconnect remains `[1, 2, 4, 8, 8]s`. Platform README files document rendering limitations.
- Latest Windows verification in `apps/windows` after the performance pass:
  `dotnet build src/Sharkord.App/Sharkord.App.csproj -p:Platform=x64` passed with 0 warnings
  and 0 errors; `dotnet test tests/Sharkord.Core.Tests/Sharkord.Core.Tests.csproj` passed
  all 141 tests. The two live-server test bodies remain gated without `SHARKORD_IT_HOST`.
  Independent Core, UI and performance reviews are complete; their Windows findings are fixed.
- macOS changes are code-complete: the same dark palette, native sidebar/user controls,
  localized hover actions including own-message More, stable lazy message rows, unread/new
  boundaries and scroll anchoring. Composer editing now fills the input, preserves unchanged
  HTML and supports channel/thread drafts. Media controls use the existing media controller.
  URL linkification and HTML attribute decoding preserve query fields. New Swift tests cover
  those URL cases, filename headers, grouping/unread boundaries and local draft storage.
  Swift compilation/tests are unverified: no Swift command ran on Windows. A Mac must run
  exactly `cd apps/macos && swift build && swift test`.
- `bun run magic` at the root and `bun run synci18n` in `packages/scripts` were attempted but
  cannot run because Bun is unavailable. Windows native localization checks pass. Static Mac
  checks parsed 90 locale tables, checked the ten native key sets/placeholders and resolved
  literal localization calls; copied web namespaces are unchanged. This is not a Swift build.
- Remaining acceptance: native visual/accessibility/input checks and real-server uploads,
  reconnect and voice/camera/screen sharing on both platforms. Changes remain in the two
  desktop apps and this taskbook; no server, web, mobile or shared-package changes or pushes.
