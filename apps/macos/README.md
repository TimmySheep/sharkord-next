# Sharkord for macOS (native)

The native macOS client: Swift + SwiftUI, no Electron and no embedded web view. It talks to
the same server as the web client over the documented-in-code wire protocol (tRPC over
WebSocket plus the plain HTTP endpoints).

This is the first working slice, not the finished client. What is here is real and verified
against a running server; what is not is listed honestly below.

## Layout

```
apps/macos/
  Package.swift
  Sources/SharkordCore/          # transport + session (the future packages/apple-core)
    JSONValue.swift              # dynamic JSON for the tRPC envelope
    TRPCProtocol.swift           # request/response framing (the only place that knows it)
    TRPCWebSocketClient.swift    # WebSocket transport, batching, keepalive, subscriptions
    SharkordHTTPClient.swift     # GET /info, POST /login, POST /upload, /public
    Models.swift                 # decodable DTOs
    KeychainTokenStore.swift     # JWT in the login keychain
    SharkordSession.swift        # login -> handshake -> join -> state + live subscriptions
  Sources/SharkordMac/           # the SwiftUI app
  Tests/SharkordCoreTests/       # wire-format unit tests + a gated integration test
```

`SharkordCore` is deliberately free of UI and of AppKit. When `apps/apple-mobile` grows a
real session layer, this is the package to extract into `packages/apple-core` (the strategy
document's plan); nothing in the app imports AppKit beyond the entry point.

## Build and run

```bash
cd apps/macos
swift build
swift run SharkordMac
```

Then enter the server address (for example `localhost:4991`), an identity and a password.
Enter sends a message; Shift+Enter adds a line break.

## Test

```bash
swift test
```

The wire-format tests run offline. The integration test is gated so a normal run never
touches the network:

```bash
SHARKORD_IT_HOST=127.0.0.1:4992 swift test --filter loginJoinSendAndReceive
```

Point it at a throwaway server: it registers a user and sends a message.

## What works today (verified)

Verified with `swift test` (12 tests) against an isolated server instance, not by inspection:

- tRPC WebSocket framing: `connectionParams` first frame, `?connectionParams=1`, one
  envelope per request, batched-array decoding, `PING`/`PONG` keepalive.
- `POST /login` (registers a user when the server allows it), `GET /info`.
- `others.handshake` -> `others.joinServer`, and the join payload's categories, channels,
  users, roles, emojis and public settings.
- `messages.get` (cursor pagination), `messages.send` (with replies and attachment ids),
  `messages.edit`, `messages.delete`, `messages.toggleReaction`, `messages.signalTyping`.
- `channels.markAsRead` / read receipts, `dms.get` / `dms.open`.
- `POST /upload` for attachments.
- Live subscriptions: `messages.onNew`/`onUpdate`/`onDelete`/`onTyping`/
  `onThreadReplyCountUpdate`, `users.onJoin`/`onLeave`/`onUpdate`/`onCreate`/`onDelete`,
  `channels.*`, `categories.*`, `emojis.*`, `roles.*`, `others.onServerSettingsUpdate`,
  `dms.onConversationOpen`, `channels.onReadStateUpdate`/`onReadStateDelta`.
- Reconnect with the reference client's backoff `[1, 2, 4, 8, 8]s` and a re-join.
- Native window: sidebar of categories/channels/DMs, message list with reactions, context
  menu (reply/edit/delete/react), typing indicator, attachments, member roster with presence
  and unread badges.

## What is not here yet

- **Voice.** mediasoup is the next milestone (strategy document §3.2). The voice channel
  view is a placeholder.
- **Plugins.** Plugin UI in the web client runs React against `window.__SHARKORD_*`; native
  parity needs a WebView host. Out of scope for v1 per the strategy document.
- **Threads, search, pinning, channel/role/user management, server settings UI, desktop
  notifications, global PTT, i18n.** The transport and session already carry the pieces
  these need; the UI and the remaining routes are the work.
- **Rich text.** The composer sends escaped plain text as `<p>`/`<br>`; it does not linkify,
  mention or inline custom emoji the way the web editor does.
- **Notarised `.app` bundle.** `swift run` produces a plain executable; packaging and
  signing are a separate step.

The full, per-feature status and limitation list is in [`../README.md`](../README.md).

## Notes

- The server's WebSocket protocol is an implementation detail of `@trpc/client` v11, not a
  versioned public spec (strategy document risk #4). All of it lives in
  `TRPCProtocol.swift` and `TRPCWebSocketClient.swift`, and the unit tests pin the exact
  bytes, so an upstream change surfaces as a test failure in one place.
- `apps/macos` has no `package.json`, so Bun workspaces ignore it and `bun.lock` is
  untouched.
