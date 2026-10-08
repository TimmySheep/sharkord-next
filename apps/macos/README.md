# cove for macOS (native)

The native macOS client: Swift + SwiftUI, no Electron. A bundled WKWebView is used only for
the shared mediasoup media worker; the rest of the interface remains native. It talks to the
same server as the web client over tRPC WebSocket and the plain HTTP endpoints.

It covers the web client's text surface end to end. What is not here is listed honestly
below, and the full per-feature table lives in [`../README.md`](../README.md).

## Layout

```
apps/macos/
  Package.swift
  Resources/Cove.icon/           # light and dark macOS app icon appearances
  Resources/cove.icns            # light appearance fallback and SwiftPM launch icon
  Resources/cove-icon.png        # transparent logo shown on the connection screen
  Sources/SharkordCore/          # transport + session (the future packages/apple-core)
    JSONValue.swift              # dynamic JSON for the tRPC envelope
    TRPCProtocol.swift           # request/response framing (the only place that knows it)
    TRPCWebSocketClient.swift    # WebSocket transport, batching, keepalive, subscriptions
    SharkordHTTPClient.swift     # GET /info, POST /login, POST /upload, /public
    Models.swift                 # decodable DTOs
    MessageHTML.swift            # the web client's message HTML, parsed and generated
    KeychainTokenStore.swift      # JWT in the login keychain
    KeychainLoginCredentialsStore.swift # optional login credentials in Keychain
    SharkordSession.swift        # login -> handshake -> join -> state + live subscriptions
    SharkordSession+*.swift      # one file per route domain, mirroring apps/server/src/routers
  Sources/SharkordMac/           # the SwiftUI app
    L10n.swift                   # 10-language lookup over the web client's locale files
    ConnectView.swift            # server address, identity, password
    MainWindow.swift             # sidebar + channel + thread + members + sheets
    SidebarView.swift            # server menu, category/channel tree, DMs, user controls
    MessageListView.swift        # grouped message rows, load older, jump back
    MessageRendering.swift       # FlowLayout, rich span rendering, files, reactions
    Composer.swift               # NSTextView editor, attachments, reply/edit, emoji
    ThreadSidebarView.swift      # thread and pinned panels
    SearchView.swift             # debounced search over messages and files
    MemberListView.swift         # roster and user profile card
    VoiceChannelView.swift       # native voice controls and the media surface
    VoiceMediaController.swift   # WKWebView media worker and allowlisted tRPC bridge
    SettingsView.swift           # user settings
    ServerSettingsViews.swift    # general, storage, users, roles, emojis, invites,
                                 # plugins, updates
    EmojiPicker.swift
    DesignSystem.swift
  Resources/locales/             # 10 languages x 8 web namespaces, byte-identical copies of
                                 # apps/client/src/i18n/locales, plus a native-only `macos`
                                 # namespace for the strings the web client has no key for
  Resources/voice-media/         # bundled mediasoup-client worker and its local media view
  Resources/AppInfo.plist        # app metadata and macOS microphone, camera, screen capture reasons
  Resources/*.lproj/InfoPlist.strings # localized system privacy prompts
  package-app.sh                 # assemble and ad-hoc sign a cove.app bundle
  Tests/SharkordCoreTests/       # wire format, message HTML, gated end-to-end suites
  Tests/SharkordMacTests/        # L10n lookup, fallback, plurals, locale parity
```

`SharkordCore` is deliberately free of UI and of AppKit. When `apps/apple-mobile` grows a
real session layer, this is the package to extract into `packages/apple-core` (the strategy
document's plan).

## Build and run

The packaged Dock and Finder icon uses the light or dark appearance from `Cove.icon` on
supported macOS versions, with `cove.icns` as the compatibility fallback. `swift run` launches
the development executable with the light icon; `package-app.sh` compiles the icon resources
and assembles the named `cove.app` bundle with the privacy metadata needed for microphone,
camera and screen capture.

```bash
cd apps/macos
swift build
swift run SharkordMac
```

Use a bundled app to exercise media capture and macOS privacy prompts. The packager includes
localized microphone, camera and screen-recording usage descriptions, then ad-hoc signs the
bundle. It refuses to overwrite an existing output path.

```bash
sh package-app.sh release .build/cove.app
open .build/cove.app
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

The current offline `swift test` run passes 68 tests (29 Swift Testing and 39 XCTest).
Earlier isolated-server runs also passed six protocol-level end-to-end tests; neither result
validates camera, microphone or screen capture in the embedded media view.

- tRPC WebSocket framing: `connectionParams` first frame, `?connectionParams=1`, one
  envelope per request, batched-array decoding, `PING`/`PONG` keepalive, `reconnect`.
- `POST /login` (registers a user when the server allows it), `GET /info`, `POST /upload`.
- `others.handshake` -> `others.joinServer`, and the join payload's categories, channels,
  users, roles, emojis and public settings.
- Messages: `messages.get` (cursor pagination and `targetMessageId` jump windows),
  `messages.send` (replies, threads, attachment ids), `messages.edit`,
  `messages.delete` with a confirmation dialog,
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
  desktop notification preferences, appearance, push-to-talk and language.
- The connection screen and main workspace use appearance-adaptive colours. Automatic login
  is enabled by default and saves the server, identity, account password and optional server
  password in macOS Keychain after joining; disabling it removes the saved credential item.
  Keychain runtime read/write and the light-mode screen still need GUI acceptance.
- Server settings: general (identity, branding, feature toggles) and storage (quotas, size
  limits, signed URLs, image optimisation) with the live disk and per-plugin usage read
  models.
- Plugins: browse, search, install and update marketplace plugins; list, enable/disable,
  remove, edit settings, configure role-based capability access, execute plugin commands
  and read logs. Server updates: version check and trigger.
- Rich text parity with the web client: the composer converts `@Name`, `#Channel`,
  `:emoji:` and bare URLs into the same semantic HTML the web editor produces, and the
  renderer draws bold, italic, underline, code, code blocks, links, mentions, channel
  references, custom emoji and inline images. Inline images and image attachments open in a
  native viewer with zoom, pan and copy-link controls. Audio/video attachments and supported
  audio/video metadata links use native AVPlayer controls. `MessageHTMLTests` pins the vocabulary.
- Live subscriptions: `messages.onNew`/`onUpdate`/`onDelete`/`onTyping`/
  `onThreadReplyCountUpdate`, `users.onJoin`/`onLeave`/`onUpdate`/`onCreate`/`onDelete`,
  `channels.*`, `categories.*`, `emojis.*`, `roles.*`, `others.onServerSettingsUpdate`,
  `dms.onConversationOpen`, `channels.onReadStateUpdate`/`onReadStateDelta`, `voice.*`,
  `invites.*`, `plugins.*`.
- Reconnect with the reference client's backoff `[1, 2, 4, 8, 8]s` and a re-join.
- Voice control and media paths: join, leave, mute, deafen, audio, webcam and screen capture
  through the bundled mediasoup worker; reactions and moderator moves use the server routes.
  Remote voice and screen-share audio have separate per-user volume controls, persisted locally.
  Runtime media permissions and remote playback still need platform testing.
- i18n: all 10 languages and 8 web namespaces, with
  `{{placeholder}}` interpolation and `_one`/`_other` plurals. Strings the web client has
  no key for live in a native-only `macos` namespace, translated in all 10 languages. No
  user-facing string in the UI is hardcoded English.

## What is not here yet

- **Voice media runtime acceptance.** Audio, webcam and screen-share transport code uses the
  bundled `mediasoup-client` worker in a restricted WKWebView. The browser capture permission,
  device selection, ICE connectivity and remote playback have not been exercised end to end.
  Screen sharing starts from a localized button inside the media surface because the browser
   requires a real page interaction before presenting its source picker.
- **Message media runtime acceptance.** Audio/video attachments and metadata links are routed
  to AVPlayer, but playback against real server files and external media URLs has not been
  exercised. AVPlayer codec support can differ from a browser's.
- **Plugin client UI.** Plugin UI in the web client runs React against `window.__SHARKORD_*`;
  it needs a broader WebView host than the restricted media surface. Native marketplace and
  server-side management are available, but rendering plugin-provided React components is not.
- **Desktop notification and hotkey runtime acceptance.** Notification policy has unit tests,
  and native notifications, unread dock/menu-bar badges and F13 push-to-talk are implemented.
  Their interaction with real notification preferences and Input Monitoring permission still
  needs a GUI pass. Push-to-talk requires the user to grant Input Monitoring in System Settings.
- **Accessibility and visual review.** The app supports system, light and dark appearance and
  has labels for voice controls, but has not had a full VoiceOver or keyboard-navigation pass.
  The connection screen's light-mode fix and automatic-login Keychain read/write still need
  GUI acceptance.
- **Formal distribution and updates.** The preview `.app` and DMG use the `cove` name and
  icon, but are ad-hoc signed and not notarized. There is no Developer ID signing, automated
  packaging pipeline or Sparkle update support.
- **Per-screen visual review.** Compiled and unit-tested, but the new dialogs, menu-bar
  controls and settings surfaces have not been walked through by hand. An automated screenshot
  pass was previously stopped on a `cua-driver` permission denial rather than worked around.

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
  holds `macos` to an identical key set and real translations in all 10 languages.
- `apps/macos` has no `package.json`, so Bun workspaces ignore it and `bun.lock` is
  untouched.
