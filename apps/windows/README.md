# Sharkord for Windows (native)

The native Windows client: C# + WinUI 3, no Electron and no embedded web view. It talks to
the same server as the web client over the same wire protocol the macOS client uses: tRPC
over WebSocket plus the plain HTTP endpoints.

**Build reality:** WinUI 3 / Windows App SDK is Windows-only and cannot be built on macOS.
`Sharkord.Core` is a plain `net8.0` library and is compiled and tested on macOS; `Sharkord.App`
is the WinUI 3 shell and must be built on Windows.

## Layout

```
apps/windows/
  Sharkord.sln
  src/Sharkord.Core/             # transport + session (cross-platform, verified)
    JsonExtensions.cs
    TrpcProtocol.cs              # request/response framing
    TrpcWebSocketClient.cs       # ClientWebSocket transport, keepalive, subscriptions
    SharkordHttpClient.cs        # GET /info, POST /login, POST /upload, /public
    Models.cs
    MessageHtml.cs
    SharkordSession.cs           # login -> handshake -> join -> state + live subscriptions
  src/Sharkord.App/              # WinUI 3 shell (Windows-only, not built here)
  tests/Sharkord.Core.Tests/     # wire-format unit tests + a gated integration test
```

## Build

On Windows (with the .NET 8 SDK and the Windows App SDK):

```powershell
cd apps/windows
dotnet build Sharkord.sln
dotnet run --project src/Sharkord.App
```

On macOS or Linux only the core is buildable, which is what CI does for the shared logic:

```bash
cd apps/windows
dotnet build src/Sharkord.Core/Sharkord.Core.csproj
dotnet test tests/Sharkord.Core.Tests/Sharkord.Core.Tests.csproj
```

The integration test is gated so it is a no-op without a target:

```bash
SHARKORD_IT_HOST=127.0.0.1:4992 dotnet test --filter LoginJoinSendAndReceive
```

## What works today (verified)

`Sharkord.Core` builds clean and its tests pass with `dotnet test` on macOS (12 tests, two of
them end to end against a real server):

- tRPC WebSocket framing: `connectionParams` first frame, `?connectionParams=1`, one
  envelope per request, `PING`/`PONG` keepalive.
- `POST /login`, `GET /info`.
- `others.handshake` -> `others.joinServer` and the join payload (categories, channels,
  users, roles, emojis, settings).
- `messages.get` (cursor pagination), `messages.send` (replies + attachments), `messages.edit`,
  `messages.delete`, `messages.toggleReaction`, `messages.signalTyping`,
  `channels.markAsRead`, `dms.get` / `dms.open`, `POST /upload`.
- Live subscriptions for messages, users, channels, categories, emojis, roles, server
  settings, read states and DM conversation opens.
- Reconnect with the `[1, 2, 4, 8, 8]s` backoff.

`Sharkord.App` is a conventional WinUI 3 shell (connect form, channel list, message list,
composer) wired to `SharkordSession`. **It has not been compiled or run**, because it needs
Windows.

## What is not here yet

- **The WinUI 3 app is unbuilt and unverified.** Windows App SDK is Windows-only; the
  package version in `Sharkord.App.csproj` is a placeholder and must be pinned on Windows.
- **Voice.** No C# mediasoup client exists; this is strategy document risk #1 and is gated
  on a separate `libmediasoupclient` P/Invoke spike.
- **Plugins.** Needs a WebView2 host.
- **The WinUI views do not yet surface** reactions, edit/delete, reply, typing, attachments
  or DMs, even though the session layer supports them.
- **Token persistence** is not implemented on the Windows side (no DPAPI yet); Core only
  carries the token in memory.

The full, per-feature status and limitation list is in [`../README.md`](../README.md).

## Notes

- The tRPC WebSocket envelope is an implementation detail of `@trpc/client` v11. It is
  isolated in `TrpcProtocol.cs` / `TrpcWebSocketClient.cs` and pinned by tests.
- The Windows App SDK version in `Sharkord.App.csproj` is a placeholder; pin it to whatever
  the Windows machine has.
- `apps/windows` has no `package.json`, so Bun workspaces ignore it.
