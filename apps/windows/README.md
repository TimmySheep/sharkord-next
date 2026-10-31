# cove for Windows (native)

The native Windows client: C# + WinUI 3, no Electron. A bundled WebView2 is limited to the
shared mediasoup media worker; the rest of the interface remains native. It talks to the same
server as the web client over tRPC WebSocket and the plain HTTP endpoints.

**Build reality:** WinUI 3 / Windows App SDK is Windows-only and cannot be built on macOS.
`Sharkord.Core` is a plain `net10.0` library; `Sharkord.App` is the WinUI 3 shell and must be
built on Windows. The current x64 Debug build succeeds on Windows with 0 warnings and 0
errors using SDK 10.0.202. Device-level visual and media acceptance remain pending.

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
  tests/Sharkord.Core.Tests/     # wire-format, session, presentation + i18n tests
```

## Build

On Windows, with the .NET 10 SDK installed (the Windows App SDK itself comes from NuGet, so
no Visual Studio and no separate Windows SDK install are needed):

```powershell
cd apps/windows
dotnet build src/Sharkord.App/Sharkord.App.csproj -p:Platform=x64
dotnet test tests/Sharkord.Core.Tests/Sharkord.Core.Tests.csproj
```

All three Windows projects target .NET 10. The previous .NET 8 test host could not run on
the installed .NET 10 runtime. Retargeting keeps build and test commands usable without
installing another machine-wide SDK or requiring runtime roll-forward environment flags.
The Windows App SDK and Windows SDK BuildTools package versions remain pinned.

The app embeds the light `Assets/cove.ico` in `cove.exe`. The published app includes both
`cove.ico` and `cove-dark.ico` under `Assets/`; the WinUI window and taskbar icon follow the
current system theme. The executable's Explorer icon remains the light appearance.

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

## Desktop workspace

The native dark workspace uses Discord-like chat, sidebar and deep-panel surfaces with a
blurple accent. Collapsible categories retain their expansion state, text channels carry
`#` markers, and voice channels carry speaker markers. The bottom-left user panel keeps
avatar, name, microphone, deafen and settings controls together. The member panel is optional.

Messages group consecutive authors within a minute, with separate reply and unread boundaries.
Rows show avatars, muted timestamps, reaction chips, attachment links and actions on hover or
keyboard focus. Own editable messages can be edited, and own messages have a confirmed delete
action. Replies, unread/new-message dividers and loading older history use existing server routes.

The rounded composer supports attachments, a built-in emoji picker and a typing indicator.
Enter sends by default, Shift+Enter inserts a newline, ArrowUp in an empty composer edits the
last own editable message, and Escape cancels reply/edit. Existing configurable send shortcuts
remain available. Channel drafts survive channel changes and automatic reconnects; a new login
clears the previous session's local drafts and history. Upload count and size checks use the
server settings, and failed sends retain the draft.

Existing language, diagnostic export, account/server settings, notification, global shortcut
and voice surfaces remain native. Localized UI labels are embedded for all ten supported
languages and checked by the Windows test suite.

The message list uses the native virtualized `ListView`/`ItemsStackPanel`. Message revisions
skip unchanged history, changed rows retain existing identities, and a single deletion does
not move every surviving row. A 5,000-row regression test verifies one collection removal.
Queued session refreshes coalesce, while unchanged channel trees and member rosters are reused.
Core inserts new messages in order, snapshots history under its existing lock, and decodes
JSON without intermediate strings. The media WebView is created when the voice view is first
opened or voice is joined; text chat startup does not initialize WebView2. These are structural
improvements, not measured startup or frame-rate benchmarks.

## Verification and compatibility

The Windows build and offline tests are run with the commands above. Exact results for this
change are recorded in [the taskbook](../../taskbook/2026-10-desktop-native-discord-ui.md).
The suite includes message grouping/reconciliation, stable session snapshots, unread state,
locale parity, HTTP requests and real loopback WebSocket framing. Source-contract UI checks
verify wiring, not rendered appearance or native input behavior. The two live-server test
bodies remain gated without `SHARKORD_IT_HOST`; a passing offline run does not exercise them.

The protocol audit retains the tRPC `connectionParams` first frame, its query flag, one envelope
per request, batched/fragmented response decoding, `PING`/`PONG`, server error messages and the
`[1, 2, 4, 8, 8]` second reconnect schedule. PONG replies now keep an idle connection alive.
Login uses the existing JSON payload. Uploads use raw bytes with a matching `content-length`,
percent-encoded filenames and the existing token/type headers. Public-file URLs retain their
signed query fields when supplied by the server. No server routes or shared packages changed.

Known differences and remaining acceptance:

- **Message HTML:** Windows deliberately renders a plain-text fallback. It retains paragraph,
  hard-break and code-block line structure, decoded entities, mention/reference text and image
  alt text. Rich emphasis, inline media, custom emoji images and hyperlink destinations whose
  labels differ from their URL are not rendered like the web client. New text uses the web
  editor's paragraph/hard-break structure. Saving an unchanged edit preserves the original
  HTML; changing the text replaces rich markup with plain composer markup. macOS retains its
  richer native renderer. This is not full web-client rendering parity.
- **Emoji:** the Windows picker offers a small built-in Unicode set. Other reaction shortcodes
  remain visible as text; it is not the web client's full emoji catalog.
- **GUI and media:** native keyboard/focus behavior, scroll anchoring, screen readers, real
  uploads and voice/camera/screen capture still need device-level testing. No GUI or real
  server acceptance is claimed by a successful build or offline test run.
- **Feature coverage:** existing DM conversations are listed; Windows still does not surface
  the complete web-client search, pins, threads or plugin-provided React UI. The media WebView
  remains restricted to bundled worker assets. Authentication tokens remain in memory only.

## Notes

- The tRPC WebSocket envelope is an implementation detail of `@trpc/client` v11. It is
  isolated in `TrpcProtocol.cs` / `TrpcWebSocketClient.cs` and pinned by tests.
- The Windows App SDK and Windows SDK BuildTools versions in `Sharkord.App.csproj` are
  pinned and verified to build. Bump them deliberately, not automatically.
- `apps/windows` has no `package.json`, so Bun workspaces ignore it.
