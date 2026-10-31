# cove for Windows (native)

The native Windows client: C# + WinUI 3, no Electron. A bundled WebView2 is limited to the
shared mediasoup media worker; the rest of the interface remains native. It talks to the same
server as the web client over tRPC WebSocket and the plain HTTP endpoints.

**Build reality:** WinUI 3 / Windows App SDK is Windows-only and cannot be built on macOS.
`Sharkord.Core` is a plain `net10.0` library; `Sharkord.App` is the WinUI 3 shell and must be
built on Windows. The current x64 Debug build succeeds on Windows with 0 warnings and 0
errors using SDK 10.0.202. The app is unpackaged and carries its Windows App SDK runtime
beside the executable, so direct launch does not require installing that runtime machine-wide.
Device-level visual and media acceptance remain deferred. This machine is in active daily
use: do not launch the app, drive foreground UI or capture the desktop during agent work.

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

Integration tests are gated and make no network requests without a target and credentials:

```powershell
$env:SHARKORD_IT_HOST = 'https://voice.timhuang.net'
# defaults to the external file specified in the taskbook; never put credentials in git
$env:SHARKORD_IT_CREDS = 'C:\Users\YY\codex-task\server-creds.txt'
dotnet test tests/Sharkord.Core.Tests/Sharkord.Core.Tests.csproj --filter FullyQualifiedName~IntegrationTests --logger 'console;verbosity=detailed'
Remove-Item Env:SHARKORD_IT_HOST
Remove-Item Env:SHARKORD_IT_CREDS
```

The file is JSON with `host`, `identity`, `password`, `peerIdentity` and `peerPassword`.
Both accounts must belong to the tester. Tests require the configured host to match the
credentials origin, use only their mutual DM, and check ownership before deleting created
fixtures. The suite covers raw upload/download bytes and actual socket-disconnect resync.
It does not exercise a voice device or an administrator account. Plain `dotnet test` in this
directory also runs the offline solution tests; an unconfigured live body is a gated no-op.

## Desktop workspace

The native dark workspace uses Discord-like chat, sidebar and deep-panel surfaces with a
blurple accent. Collapsible categories retain their expansion state, text channels carry
`#` markers, and voice channels carry speaker markers. The bottom-left user panel keeps
avatar, name, microphone, deafen and settings controls together. The member panel is optional.

Messages group consecutive authors within a minute, with separate reply and unread boundaries.
Rows show avatars, muted timestamps, reaction chips, native attachment previews and actions on
hover or keyboard focus. Own editable messages and moderator actions follow the server's
permission rules. Delete actions require confirmation. Replies, unread/new-message dividers
and loading older history use existing server routes.

The rounded composer supports attachments, the full standard/custom emoji picker and a typing indicator.
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

## Phase two surfaces

The navigation menu exposes message/file search, pins, channel selection, new DMs and logout.
Threads retain separate drafts, typing and cursor pages. Search, reply and pin navigation use
the target message's actual channel and parent; newer navigation invalidates older requests.
Reconnection reloads the selected history and DM/read-state snapshots. Optional joined DM
snapshots support the deployed server while preserving the older repository protocol.

Native rich text covers emphasis, code, links, mentions, channel references, standard/custom
emoji and supported images. The formatting menu supplies safe composer syntax and reference
pickers. Unchanged rich edits keep their original HTML. Server metadata supplies link cards
and direct media previews. Image viewing supports zoom/pan and copy-link; audio/video use
native playback controls. Uploads share picker/drop/paste validation, progress, cancellation,
temporary-file removal and conversation-aware drafts. The catalog contains 1,940 entries from
Tiptap 3.22.2; its MIT license is included in build output.

Voice surfaces expose participant state, speaking indicators, reactions, per-user volumes,
receive-quality layers, stream pin/zoom/fullscreen/statistics, device selection and previews,
capture resolution/frame rate and noise settings. The media worker remains the only WebView
host. Device and permission behavior requires manual acceptance. Picture-in-picture is
offered only when the media engine reports support and may reject a native-triggered request.

Account restore is optional and unchecked by default. Passwords are stored only through
Windows Credential Manager when explicitly enabled; logout forgets that entry. Non-secret
preferences use a file because unpackaged apps cannot use package LocalSettings. A welcome
profile path uses the normal own-user editor. Native management forms use the same server
permissions and routes; normal-user live acceptance does not prove administrator behavior.

## Verification and compatibility

The Windows build and offline tests are run with the commands above. Exact results for this
change are recorded in [the phase-two taskbook](../../taskbook/2026-10-desktop-feature-parity-acceptance.md).
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

- GUI acceptance is **deferred** by the machine owner. Follow the taskbook's manual checklist
  when a human has the machine available. Build/source checks cannot establish focus, scrolling,
  accessibility, drop/paste, codecs, device selection or camera/screen capture behavior.
- The native editor implements a bounded formatting vocabulary, not every Tiptap feature.
  Spoilers use literal delimiters because the current server sanitizer has no spoiler node.
  YouTube links open externally; third-party iframe players and plugin React slots are outside
  the native UI/media-only WebView constraint. Plugin-provided UI is not hosted.
- Group DMs have no upstream endpoint. OIDC is disabled on the acceptance server; a native
  OIDC flow is still absent. The final taskbook table records ordinary remaining parity gaps
  separately from these constraints and from verification pending on macOS.

## Notes

- The tRPC WebSocket envelope is an implementation detail of `@trpc/client` v11. It is
  isolated in `TrpcProtocol.cs` / `TrpcWebSocketClient.cs` and pinned by tests.
- The Windows App SDK and Windows SDK BuildTools versions in `Sharkord.App.csproj` are
  pinned and verified to build. Bump them deliberately, not automatically.
- `apps/windows` has no `package.json`, so Bun workspaces ignore it.
