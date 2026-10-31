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

- (to be filled in by the implementing agent)
