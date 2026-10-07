# Sharkord for macOS (native)

The native macOS client: Swift + SwiftUI, no Electron and no embedded web view. It talks to
the same server as the web client over the documented-in-code wire protocol (tRPC over
WebSocket plus the plain HTTP endpoints).

It covers the web client's text surface end to end. What is not here is listed honestly
below, and the full per-feature table lives in [`../README.md`](../README.md).

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
    MessageHTML.swift            # the web client's message HTML, parsed and generated
    KeychainTokenStore.swift     # JWT in the login keychain
    SharkordSession.swift        # login -> handshake -> join -> state + live subscriptions
    SharkordSession+*.swift      # one file per route domain, mirroring apps/server/src/routers
  Sources/SharkordMac/           # the SwiftUI app
    L10n.swift                   # 8-language lookup over the web client's locale files
    ConnectView.swift            # server address, identity, password
    MainWindow.swift             # sidebar + channel + thread + members + sheets
    SidebarView.swift            # server menu, category/channel tree, DMs, user controls
    MessageListView.swift        # grouped message rows, load older, jump back
    MessageRendering.swift       # FlowLayout, rich span rendering, files, reactions
    Composer.swift               # NSTextView editor, attachments, reply/edit, emoji
    ThreadSidebarView.swift      # thread and pinned panels
    SearchView.swift             # debounced search over messages and files
    MemberListView.swift         # roster and user profile card
    VoiceChannelView.swift       # voice control plane (no media, see below)
    SettingsView.swift           # user settings
    ServerSettingsViews.swift    # general, storage, users, roles, emojis, invites,
                                 # plugins, updates
    EmojiPicker.swift
    DesignSystem.swift
  Resources/locales/             # 8 languages x 8 web namespaces, byte-identical copies of
                                 # apps/client/src/i18n/locales, plus a native-only `macos`
                                 # namespace for the strings the web client has no key for
  Tests/SharkordCoreTests/       # wire format, message HTML, gated end-to-end suites
  Tests/SharkordMacTests/        # L10n lookup, fallback, plurals, locale parity
```

`SharkordCore` is deliberately free of UI and of AppKit. When `apps/apple-mobile` grows a
real session layer, this is the package to extract into `packages/apple-core` (the strategy
document's plan).

## Build and run

```bash
cd apps/macos
swift build
swift run SharkordMac
```

Then enter the server address (for example `localhost:4991`), an identity and a password.
Enter sends a message; Shift+Enter adds a line break; Escape clears the reply or edit
banner; ArrowUp edits your own last message. Drop, paste or pick files to attach them.

## Test

```bash
swift test
```

Everything above runs offline. The end-to-end suites are gated so a normal run never
touches the network:

```bash
SHARKORD_IT_HOST=127.0.0.1:4992 swift test
```

Point it at a throwaway server. Those tests register a user, send messages, create and
delete categories, channels, roles, emojis and invites, and change server settings.

## What works today (verified)

Verified with `swift test` (43 tests) against an isolated server instance, not by
inspection. 6 of those are end-to-end against a real server; the rest pin the wire format,
the message HTML vocabulary and the locale lookup.

- tRPC WebSocket framing: `connectionParams` first frame, `?connectionParams=1`, one
  envelope per request, batched-array decoding, `PING`/`PONG` keepalive, `reconnect`.
- `POST /login` (registers a user when the server allows it), `GET /info`, `POST /upload`.
- `others.handshake` -> `others.joinServer`, and the join payload's categories, channels,
  users, roles, emojis and public settings.
- Messages: `messages.get` (cursor pagination and `targetMessageId` jump windows),
  `messages.send` (replies, threads, attachment ids), `messages.edit`, `messages.delete`,
  `messages.toggleReaction`, `messages.togglePin`, `messages.getPinned`,
  `messages.getThread`, `messages.search`, `messages.signalTyping`.
- Read state: `channels.markAsRead`, unread badges, "return to present" on `hasNewer`.
- Direct messages: `dms.get` / `dms.open` and the conversation list.
- Category and channel tree: create, rename, delete and reorder categories and channels,
  plus per-channel permission overrides for roles and users.
- Roles: create, edit name/colour/permissions, per-role storage quota, set default, delete.
- Custom emoji: upload, rename, delete; `:name:` resolves in the composer and renders as an
  inline image, with long names winning over short ones.
- Invites: create with use limits and expiry, copy the link, delete.
- User administration: list, detail (roles, storage, recent logins), kick, ban, unban,
  delete account, assign roles.
- User settings: profile name/colour/bio, avatar and banner upload, password change,
  notification preferences, language.
- Server settings: general (identity, branding, feature toggles) and storage (quotas, size
  limits, signed URLs, image optimisation) with the live disk and per-plugin usage read
  models.
- Plugins: list, enable/disable, remove, read logs, capability list and settings
  definitions. Server updates: version check and trigger.
- Rich text parity with the web client: the composer converts `@Name`, `#Channel`,
  `:emoji:` and bare URLs into the same semantic HTML the web editor produces, and the
  renderer draws bold, italic, underline, code, code blocks, links, mentions, channel
  references, custom emoji and inline images. `MessageHTMLTests` pins the vocabulary.
- Live subscriptions: `messages.onNew`/`onUpdate`/`onDelete`/`onTyping`/
  `onThreadReplyCountUpdate`, `users.onJoin`/`onLeave`/`onUpdate`/`onCreate`/`onDelete`,
  `channels.*`, `categories.*`, `emojis.*`, `roles.*`, `others.onServerSettingsUpdate`,
  `dms.onConversationOpen`, `channels.onReadStateUpdate`/`onReadStateDelta`, `voice.*`,
  `invites.*`, `plugins.*`.
- Reconnect with the reference client's backoff `[1, 2, 4, 8, 8]s` and a re-join.
- Voice control plane: join, leave, mute, deafen, webcam and screen-share flags, reactions
  and moving members between channels. See the caveat below.
- i18n: all 8 languages and 8 namespaces from the web client, byte-identical, with
  `{{placeholder}}` interpolation and `_one`/`_other` plurals. Strings the web client has
  no key for live in a native-only `macos` namespace, translated in all 8 languages. No
  user-facing string in the UI is hardcoded English.

## What is not here yet

- **Voice media.** The control plane is complete and interoperable with the web client, but
  there is no WebRTC transport: nothing is heard or seen. Swift has no mediasoup client,
  so this needs a native WebRTC library or a hand-rolled transport over the mediasoup
  signalling. It is the single largest remaining gap and the voice view says so.
- **Plugin UI.** Plugin UI in the web client runs React against `window.__SHARKORD_*`;
  native parity would need a WebView host, which is out of scope for v1. The plugin
  settings editor is read-only and there is no capability permission editor or command
  console, though `SharkordCore` already has the routes for all three.
- **Welcome and server-password dialogs.** Approximated by the connection page and the
  profile settings, not the web client's modal flow with its countdown.
- **Desktop notifications, unread aggregation, menu bar presence, global PTT.** Unread
  badges live in the sidebar only.
- **Theme and accessibility.** The fixed dark palette pins the app's color scheme to dark so system semantic text colors stay readable when macOS is in light mode; no VoiceOver pass.
- **A signed `.app` bundle.** `swift run` produces a plain executable. No `Info.plist`, no
  notarisation, no Sparkle updates.
- **Per-screen visual review.** Compiled, unit-tested and exercised end-to-end over the
  protocol, but not walked through by hand. An automated screenshot pass was attempted and
  stopped on a `cua-driver` permission denial rather than worked around.

## Notes

- The server's WebSocket protocol is an implementation detail of `@trpc/client` v11, not a
  versioned public spec (strategy document risk #4). All of it lives in
  `TRPCProtocol.swift` and `TRPCWebSocketClient.swift`, and the unit tests pin the exact
  bytes, so an upstream change surfaces as a test failure in one place.
- The message HTML vocabulary is a re-implementation of the web client's
  `prepare-message-html`, `linkify-html` and `message-sanitizer`. Upstream changes will not
  flow through automatically; `MessageHTMLTests` is what turns a silent drift red.
- `Resources/locales` holds a byte-identical copy of `apps/client/src/i18n/locales`, kept
  outside `Sources/` so the web namespaces can be re-copied wholesale; the native-only
  `macos.json` sits alongside them and survives a refresh. `LocaleParityTests` walks
  `Sources/SharkordMac` for `L10n.t` call sites and fails on any key no locale defines, and
  holds `macos` to an identical key set and real translations in all 8 languages.
- `apps/macos` has no `package.json`, so Bun workspaces ignore it and `bun.lock` is
  untouched.
