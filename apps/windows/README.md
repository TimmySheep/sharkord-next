# cove for Windows (native)

The native Windows client: C# + WinUI 3, no Electron. A bundled WebView2 is limited to the
shared mediasoup media worker; the rest of the interface remains native. It talks to the same
server as the web client over tRPC WebSocket and the plain HTTP endpoints.

**Build reality:** WinUI 3 / Windows App SDK is Windows-only and cannot be built on macOS.
`Sharkord.Core` is a plain `net8.0` library and is compiled and tested on macOS; `Sharkord.App`
is the WinUI 3 shell and must be built on Windows. A previous Cove x64 Release build and
self-contained publish succeeded on Windows 11 with 0 warnings and 0 errors. The current voice
and TreeView changes have not been rebuilt, and the app has not been launched or visually reviewed.

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
    I18n/L10n.cs                 # locale lookup, embedded tables, {{placeholder}} interpolation
    I18n/locales/<lang>/         # windows.json + connect.json, 10 languages
  src/Sharkord.App/              # WinUI 3 shell, WebView2 media worker and cove.ico (Windows-only)
  tests/Sharkord.Core.Tests/     # wire-format + i18n unit tests, a gated integration test
```

## Build

On Windows, with the .NET 8 SDK installed (the Windows App SDK itself comes from NuGet, so
no Visual Studio and no separate Windows SDK install are needed):

```powershell
cd apps/windows
dotnet build src/Sharkord.App/Sharkord.App.csproj -p:Platform=x64
dotnet test tests/Sharkord.Core.Tests/Sharkord.Core.Tests.csproj
```

The app embeds `Assets/cove.ico` in `cove.exe` and publishes the file under `Assets/` beside
the executable for the WinUI title bar and taskbar icon.

`-p:Platform=x64` is required, not optional. `Sharkord.App.csproj` declares
`Platforms=x64;ARM64`, so the default `AnyCPU` is not in that list and the build fails with
an unset `OutputPath`. Pass `-p:Platform=ARM64` on an ARM machine.

Copying the sources over with `tar` from macOS pulls in `._*` AppleDouble sidecars, which the
SDK-style `**/*.cs` glob then tries to compile. Set `COPYFILE_DISABLE=1` on the sending side.
Windows `tar.exe` also wants `C:/Users/...`, not `/c/Users/...`.

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

`Sharkord.Core` builds clean and its tests pass with `dotnet test` on macOS (53 tests, two of
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
- Localisation: 10 languages (`en`, `de`, `es`, `fr`, `it`, `cs`, `ru`, `zh`, `zh-Hant`,
  `pt-BR`) with the same key layout the macOS client uses. The `windows` namespace holds ten
  WinUI-only labels, including the language picker, system-default option and reaction action;
  `identityLabel`, `passwordLabel` and `connectBtn` are
  read from the shared `connect` namespace instead of being copied. The tables are embedded
  in `Sharkord.Core.dll`. The picker stays available in the connect and chat views, offers
  system language plus all ten locales, and persists explicit choices in
  `%LOCALAPPDATA%\Sharkord\language`. `L10nTests` scans the window source so a hardcoded
  english label or a renamed key fails the suite instead of surfacing as raw text at runtime.

`cove` is a WinUI 3 shell (connect form, grouped channel tree, message list, composer,
reactions, voice controls and language picker) wired to `SharkordSession`. The source before
the current voice and TreeView changes compiled and published on Windows 11 x64 in Release
configuration with 0 warnings and 0 errors. It renders reaction chips, toggles existing
reactions and offers six common reactions; other reaction shortcodes remain visible as
`:shortcode:` text. The app has not been launched or visually reviewed, and the shell only
exposes a slice of what `SharkordSession` supports.

## What is not here yet

- **The current WinUI 3 source has not been rebuilt, launched or visually reviewed.** The
  earlier Release build predates the voice media and grouped TreeView changes, and compilation
  alone would not verify runtime interactions.
  `Microsoft.WindowsAppSDK` is pinned at `1.6.240923002` and
  `Microsoft.Windows.SDK.BuildTools` at `10.0.26100.1742`; both restore and build as
  declared, so they are not placeholders needing replacement.
- **Voice runtime acceptance.** The WinUI voice controls, C# signaling bridge and bundled
  WebView2 mediasoup worker are present in source, including audio, webcam and screen sharing.
  This version still needs a Windows build, permission check and real media test.
- **Plugins.** The WebView2 surface is restricted to bundled media assets and does not load
  server-provided plugin UI.
- **The WinUI views do not yet surface** edit/delete, reply, typing, attachments or DMs,
  even though the session layer supports them.
- **The admin and settings surface is macOS-only for now.** Categories/channels management,
  roles, emojis, invites, user administration, server settings, pins, threads, search and
  the voice control plane are implemented in `SharkordCore` (Swift) and not in
  `Sharkord.Core` (C#). Porting them is mechanical: the routes and payload shapes are
  recorded in the macOS `SharkordSession+*.swift` files and in `docs/` .
- **Token persistence** is not implemented on the Windows side (no DPAPI yet); Core only
  carries the token in memory.

The full, per-feature status and limitation list is in [`../README.md`](../README.md).

## Notes

- The tRPC WebSocket envelope is an implementation detail of `@trpc/client` v11. It is
  isolated in `TrpcProtocol.cs` / `TrpcWebSocketClient.cs` and pinned by tests.
- The Windows App SDK and Windows SDK BuildTools versions in `Sharkord.App.csproj` are
  pinned and verified to build. Bump them deliberately, not automatically.
- `apps/windows` has no `package.json`, so Bun workspaces ignore it.
