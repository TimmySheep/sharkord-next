# Sharkord Next — Native Client Strategy

> 中文版: [NATIVE_STRATEGY.zh-CN.md](NATIVE_STRATEGY.zh-CN.md)

Design document for the first native targets (iPhone + iPad, macOS, Windows) and for the shared
core that is supposed to keep them from re-inventing the same business logic three times.

| Field | Value |
| --- | --- |
| Repository | `TimmySheep/sharkord-next` (public community fork of `Sharkord/sharkord`) |
| Revision reviewed | `c611bb4` on branch `development` (2026-10-06) |
| Native projects in scope (proposed) | `apps/apple-mobile`, `apps/macos`, `apps/windows` |
| Status of those directories | **do not exist yet** — this document only describes them |
| Document date | 2026-10-06 |

**Evidence legend.** Every claim is tagged:
**[V]** = verified against this repository or a primary vendor source on the date above (file paths and
counts are reproducible). **[R]** = recommendation or judgement, not a fact about the system.

Figures below come from `wc -l`/`grep`/`bun install` probes on the checkout at `c611bb4`.

---

## 1. Evidence base: what actually exists today

### 1.1 Workspace inventory **[V]**

| Workspace | Stack | Tracked LOC | Role |
| --- | --- | --- | --- |
| `apps/client` | React 19 + Vite + Redux Toolkit + Tailwind 4 | 52,759 | Web client (the reference client) |
| `apps/server` | Bun + tRPC v11 + Drizzle/SQLite + mediasoup | 97,546 (excluding `__tests__`) | Server, SFU, HTTP |
| `packages/shared` | TypeScript types/enums/helpers | 2,438 non-test + 2,261 test | Cross-cutting TS |
| `packages/ui` | Presentational React components only | — | No app logic |
| `packages/plugin-sdk` | Plugin API surface (`src/actions.ts`, `client.ts`, `index.ts`) | — | Plugins |

Root `package.json` declares `workspaces: ["apps/*", "packages/*"]` **[V]**.

### 1.2 `packages/shared` file by file — the candidate core seed **[V]**

This is the honest answer to "how much of `packages/shared` can seed a cross-platform core": it can
seed a *specification*, not a *library*. See §1.4.

| File | LOC | Contents | Usable natively? |
| --- | --- | --- | --- |
| `src/types.ts` | 225 | `ChannelType`, `StreamKind`, `UserStatus`, `TMessageMetadata`, `TPublicServerSettings`, `TMessagesCursor` + `zMessagesCursor`, hex/invite/emoji regexes | Shape yes; `zMessagesCursor` is zod |
| `src/events.ts` | 61 | `ServerEvents` enum (39 members), `TNewMessage` | Yes — pure enum |
| `src/statics/permissions.ts` | 45 | `Permission` (24), `ChannelPermission` (6), `DEFAULT_ROLE_PERMISSIONS` | Yes — pure enum |
| `src/statics/storage.ts` | 47 | Quota/size constants, `StorageOverflowAction` | Yes — pure constants |
| `src/statics/index.ts` | 29 | `DisconnectCode` (1006/40000/40001/40002), limits, `DEFAULT_BITRATE`, `OWNER_ROLE_ID` | Yes — pure constants |
| `src/statics/locales.ts` | 18 | `SUPPORTED_LOCALES` (8), `zLocale` | Yes (zod for the validator) |
| `src/statics/upload.ts` | 6 | `UploadHeaders` (`x-file-name`, `x-file-type`, `x-token`) | Yes — needed for uploads |
| `src/statics/metrics.ts` | 13 | `TDiskMetrics`, `TPluginStorageUsage` | Yes — shapes |
| `src/voice.ts` | 58 | `TVoiceUserState`, `TVoiceMap`, `TTransportParams`, `TVoiceProducerInfo`, `TChannelState` | Shapes yes, but imports `mediasoup/types` |
| `src/tables.ts` | 157 | DB row types via drizzle `InferSelectModel`; **imports `apps/server/src/db/schema`** | No — server/DB coupled |
| `src/logs.ts` | 237 | `ActivityLogType` enum (large) | Enum yes; types depend on `tables.ts` |
| `src/helpers/*` | 522 | `message-sanitizer`, `strip-zalgo`, `linkify-html`, `extract-urls`, `command-parser`, `prepare-message-html`, `has-mention`, `sha256`, `trpc-errors`, … | Mostly pure JS/regex — portable as algorithm reference |
| `src/plugins/*` | ~880 | Plugin manifest/capabilities/hooks/contracts/commands/components | Contract types portable; `client-sdk.ts` / `components.ts` reference `window`/React |
| `src/trpc.ts` | 1 | `export type { AppRouter } from '../../../apps/server/src/routers'` | No — TS type re-export |

**Directly portable-as-specification ≈ 1,200 of 2,438 non-test lines (~49%)** **[R, method in table
above]**: all enums, constants, DTO shapes and regexes, plus the pure helpers. The remainder is
coupled to the web DOM, the server DB schema, or the tRPC/mediasoup TS types.

### 1.3 Protocol surface — the real size of the contract **[V]**

| Metric | Count |
| --- | --- |
| tRPC query/mutation procedures | **91** |
| tRPC WebSocket subscriptions | **43** |
| Procedures with a zod `.input()` schema | **76** |
| Non-tRPC HTTP endpoints | 13 |
| SQLite migrations at HEAD | 35 |

Procedures/subscriptions per router **[V]**: `voice` 14/10 · `plugins` 15/6 · `users` 12/5 ·
`messages` 11/5 · `channels` 9/6 · `others` 9/1 · `categories` 5/3 · `roles` 5/3 · `emojis` 4/3 ·
`invites` 3/0 · `dms` 2/1 · `files` 2/0.

Non-tRPC HTTP **[V]** (`apps/server/src/http/index.ts`): `GET /healthz`, `/info`, `/manifest.json`,
`/oidc/login`, `/oidc/callback`, prefix `/public/*`, `/plugin-components/*`, `/plugin-bundle/*`;
`POST /upload`, `/login`, `/oidc/exchange`, `/oidc/backchannel-logout`.

| Flow step | Contract **[V]** |
| --- | --- |
| Login | `POST /login` `{identity, password, invite?}` → `{success, token}` (JWT, 7-day expiry) — `http/login.ts` |
| WS connect | `connectionParams = {token}`; the socket is authenticated as a *user* but **not joined** — `lib/trpc.ts`, `utils/wss.ts` |
| Handshake | `others.handshake.query()` → `{handshakeHash, hasPassword}` — `routers/others/handshake.ts` |
| Join | `others.joinServer.query({handshakeHash, password?, locale?})` → the entire initial state (categories, channels, users, roles, emojis, `voiceMap`, `channelPermissions`, `readStates`, settings, plugin metadata, external streams) — `routers/others/join.ts` |
| Realtime | 43 subscriptions, each `pubsub.subscribeFor(userId, ServerEvents.X)`, e.g. `onMessageRoute` — `routers/messages/events.ts` |
| Reconnect | fixed backoff `[1000, 2000, 4000, 8000, 8000]` ms, then re-join; a reconnected socket starts unauthenticated — `features/server/actions.ts`, `lib/trpc.ts` |
| Upload | `POST /upload` with headers `x-token`, `x-file-name`, body = raw octet-stream → `TTempFile`; size must match `content-length` — `http/upload.ts` |

### 1.4 Two structural facts that decide the whole design

**Fact A — `packages/shared` is a compile-time TypeScript package, not a runtime-neutral core.**
It cannot be consumed by Swift or C#, and it is not self-contained **[V]**:

- `src/tables.ts` imports the **server's** Drizzle schema (`apps/server/src/db/schema`).
- `src/voice.ts` imports `mediasoup/types`.
- `src/trpc.ts` is a type-only import of the **server's** `AppRouter`.
- `src/types.ts` and two helpers depend on **zod**; `linkify-html.ts`/`extract-urls.ts` depend on **linkify-it**.

So `packages/shared` can only be a *source* for a core, never the core itself.

**Fact B — the voice stack is an SFU (client↔server), not peer-to-peer.**
This repo's client depends on `mediasoup-client` and drives `device.createSendTransport` /
`createRecvTransport`, `voice.produce`, `voice.consume`, `voice.setConsumerQuality` **[V]**
(`components/voice-provider/hooks/use-transports.ts`, `routers/voice/*`). mediasoup's *client-side*
library is a C++ library over Google libwebrtc (`versatica/libmediasoupclient`, API mirrors
`mediasoup-client`) **[V]**. There is **no official mediasoup client for Swift, C#, or Rust**;
Apple support comes from third-party wrappers (`VLprojects/mediasoup-client-swift`,
`ethand91/mediasoup-ios-client`) and Android from `haiyangwu/mediasoup-client-android` **[V]**.

This means the media engine — the single largest, most expensive piece of a Discord-like client —
**must be native and bound per platform on every route.** No shared-core choice removes that work.

---

## 2. Shared core: which route to take

### 2.1 The three routes, defined

| Route | Definition |
| --- | --- |
| **(a) Rust core + FFI** | One Rust crate owns models/logic; Swift consumed via `uniffi` (official Swift/Kotlin backend) and C# via a community generator (`uniffi-bindgen-cs`) or `csbindgen` **[V]**. |
| **(b) Per-platform, shared docs only** | Each app implements everything; only a written protocol + JSON Schema is shared. |
| **(c) TS/`shared` as single source + codegen** | `packages/shared` (plus zod schemas lifted out of server routers) remains the truth; a generator emits Swift/C# models and a versioned schema artifact. |

### 2.2 Impact table

| Dimension | (a) Rust core | (b) Docs only | (c) TS source + codegen |
| --- | --- | --- | --- |
| **Mobile background voice** | No effect — this is purely an `AVAudioSession` / `UIBackgroundModes` question **[V]**; a Rust crate cannot hold an audio session **[R]** | No effect | No effect |
| **Binary size** | +~1–3 MB Rust static lib **per platform** and extra FFI shims, on top of libwebrtc (~30–100 MB) **[R]** | Smallest code footprint, but 3× duplicated logic **[R]** | Negligible — generated models only **[R]** |
| **Startup time** | Negligible init cost, but adds a cross-language call boundary to every state update **[R]** | Fastest (no extra layer) | Fastest — codegen has zero runtime cost **[R]** |
| **Development speed** | Slowest: 3 languages + 3 build systems + FFI regeneration per change **[R]** | Fast per platform, but every protocol change is applied 3× by hand | Fast: change zod/TS once, regenerate **[R]** |
| **Community contribution threshold** | **Highest** — contributors must learn Rust + Swift + C# + `uniffi` | Lowest per file, but no single place to fix a bug | **Lowest** — the upstream team already writes TS; contributors keep working in TS **[V]** |
| **Logic reuse (the stated goal)** | **Best** — one implementation of state sync, reconnect, permissions, cache | Worst | Models only; runtime logic is still re-written per platform |
| **RTC / media reuse** | None — no Rust mediasoup client exists **[V]** | None | None |
| **Drift risk** | Low for logic; **high** for the boundary (TS truth vs Rust truth) | Highest | Medium — enforced by generation + a conformance suite |
| **Upstream mergeability** | Poor — a Rust tree in a Bun monorepo diverges from `upstream/development` | Good | **Best** — no new language; `packages/shared` stays the merge point |

### 2.3 Recommendation

> **Adopt route (c) now, with a defined graduation gate to route (a). Reject (b).**

**Core recommendation, one sentence:** *Let `packages/shared` become a schema-first, language-neutral
protocol contract and generate the Swift/C# models from it — share a real SwiftPM core across the three
Apple targets — and only extract the Rust "brain" once the protocol stops churning.*

Why (c) and not (a), given the project explicitly wants a shared core:

1. **Route (a) does not buy the thing it looks like it buys.** §1.4 Fact B: the media engine stays
   native on every route, and audio/capture/background modes are OS APIs Rust cannot reach. So a Rust
   core eliminates the *cheap* duplication (models, reducers, reconnect) while the *expensive*
   duplication (WebRTC + mediasoup + audio + capture) remains. That is the wrong trade for the first
   release. **[R]**
2. **Precedent in the repo forbids it right now.** `AGENTS.md` states the core principle is
   *"no over-engineering … add the smallest thing that works … don't introduce unneeded abstractions
   or dependencies"* **[V]**. Introducing Rust + `uniffi` + a Windows `.NET` toolchain into a Bun
   monorepo is the opposite of that, for a protocol that is still moving (35 migrations, 91
   procedures, version `0.0.25`) **[V]**. An FFI boundary frozen today is a boundary you will
   re-freeze every month. **[R]**
3. **Three of the four targets are one language.** iPhone and iPad are a single project, macOS is a
   second, both Swift — so a shared **SwiftPM** core covers three targets natively with no FFI at all.
   Only Windows (C#) diverges. Route (c) therefore means **two** implementations, not four, and the
   Swift half is a genuine shared library rather than a generated model dump. **[R]**

Why reject (b): it has no enforcement mechanism. With 76 zod schemas inline in server routers and
no machine-checked contract, three hand-written clients will silently diverge from the server the
first time an input shape changes. **[R]**

Why not (a) *yet*: it is the correct destination, not the correct first step. Route (c) produces
exactly the artefact a future Rust core needs anyway — a formal, versioned, machine-checkable protocol
description — so choosing (c) now does not throw the Rust work away; it defines the Rust crate's
interface before you commit to maintaining it. **[R]**

**Graduation gate to (a)** — extract the Rust core only when all of these hold **[R]**:
1. Protocol churn drops (e.g. a release with no changes to router procedure signatures).
2. A conformance test suite exists that both the TS and any native client can run against.
3. Windows reaches parity with macOS on voice (i.e. the C# client is real, not a stub).
4. There is demonstrated proof of drift bugs caused by duplicated runtime logic.

### 2.4 Rust core module split — target design (for when the gate is met) **[R]**

**Into the core crate** (platform-agnostic, no OS APIs, no sockets it does not own):

| Module | Responsibility |
| --- | --- |
| `protocol::models` | Every DTO from `shared/src/types.ts`, `tables.ts` (shape only), `events.ts`, `voice.rs`, serialised with serde |
| `protocol::enums` | `ServerEvents`, `Permission`, `ChannelPermission`, `ChannelType`, `StreamKind`, `DisconnectCode`, `UploadHeaders` — mirrored 1:1 |
| `protocol::validate` | Port of the zod rules (`MESSAGE_MAX_LENGTH`, cursor shapes, locale enum) |
| `transport::ws` | WS framing + the tRPC-style request/subscription envelope (§2.5 risk) |
| `auth` | Token lifecycle: store handle → connect params → `handshake` → `joinServer` → re-join on reconnect |
| `state` | The store: normalised channels/users/messages/roles/voice, and the reducers from `features/server/slice.ts` |
| `state::sync` | Subscription application (the 43 events), dedupe/merge ordering, detached-window logic |
| `presence`, `reconnect` | Backoff state machine `[1,2,4,8,8]s` + re-join |
| `perm` | Permission evaluation for UX only — never a security boundary |
| `rtc::signaling` | Orchestration *only*: create transport, connect, produce, consume, set consumer quality |
| `media::metadata` | Stream kinds, quality layers, external-stream metadata, ICE state as data |
| `cache` | Indexed offline cache of channels/messages |

**Must stay in the native layer** (the core must expose these as abstract interfaces it never calls):

| Native concern | Why it cannot live in the core |
| --- | --- |
| Audio capture / playback / routing, device selection, echo cancellation | `AVAudioSession` (Apple), WASAPI (Windows) — OS-owned, permission-gated **[V]** |
| The WebRTC media engine + `mediasoup-client` semantics | C++ `libmediasoupclient` over libwebrtc; no Rust binding exists **[V]** |
| Codec selection / hardware encode-decode | VideoToolbox (Apple), Media Foundation / DXVA (Windows) **[R]** |
| Screen capture | ScreenCaptureKit / ReplayKit (Apple), Windows.Graphics.Capture (Windows) **[R]** |
| Incoming-call UI + wake | PushKit / CallKit / LiveCommunicationKit, APNs **[V]** |
| Global push-to-talk | `CGEventTap` / accessibility permission (macOS), `RegisterHotKey` + low-level hook (Windows) **[R]** |
| Token at rest | Keychain (Apple), DPAPI (Windows) **[R]** |
| Tray, notifications, app lifecycle / background modes, UI | Platform-owned **[R]** |

**The boundary, stated plainly:** the Rust core can never acquire a platform-protected audio or
capture handle. Its media responsibility is limited to *signalling and state*; the media itself is
handed to the native engine. Any design that expects the core to own `AVAudioSession` or WASAPI is
unsound and should be rejected at review. **[R]**

### 2.5 Risks and premises that do not hold

| # | Premise / risk | Verdict |
| --- | --- | --- |
| 1 | "Share P2P signalling / ICE for a peer mesh" | **False premise.** The system is an SFU; there is no P2P mesh and no peer-to-peer ICE to share. Native clients talk to the server's mediasoup router only. **[V]** |
| 2 | "`packages/shared` can be the core as-is" | **False.** It imports the server schema, mediasoup types, zod, and linkify-it; it is TS-only. **[V]** |
| 3 | "A Rust core removes RTC duplication" | **False.** No Rust mediasoup client; the C++/native engine work is per-platform regardless. **[V]** |
| 4 | tRPC WebSocket wire format | **Real risk.** tRPC v11's WS framing is an implementation detail, not a versioned public spec. Any non-TS client (Rust or C#) must mirror it and can break on an upstream bump. Mitigation: add a small documented/versioned protocol endpoint, or a conformance harness that fails CI on drift. **[R]** |
| 5 | Client-side permissions | **Real risk if misused.** The server is authoritative (`ctx.needsPermission` / `ctx.needsChannelPermission` on every route) **[V]**. Native permission code may only hide UI, never gate actions. |
| 6 | Auth token handling | JWT is delivered by `POST /login` and sent as a WS connection param **[V]**. Native must store it in Keychain/DPAPI and treat it as a credential. |
| 7 | Signed file URLs | `/public/*` enforces `accessToken` + `expires` when `storageSignedUrlsEnabled` **[V]** (`http/public.ts`, `files-crypto.ts`). Native image/file loaders must pass the query params. |
| 8 | Plugin UI | Plugin client halves are React running inside the web client against `window.__SHARKORD_STORE__` / `window.__SHARKORD_REACT__` **[V]** (`plugins/client-sdk.ts`, `plugins/components.ts`). Native cannot host plugin UI without an embedded web view. **This is a scope hole the native plan must declare explicitly.** |
| 9 | iOS background audio | Apple: a recording session cannot be started from the background; `voip` wakes for incoming calls while `audio` keeps an *already active* session alive, and any incoming call pre-empts a plain `playAndRecord` session **[V]**. Native must design around a user-initiated, foreground-started call. |
| 10 | Startup/state assumptions | `joinServer` returns the whole world in one response **[V]**; a missed subscription during the gap between WS drop and re-join is silently lost unless the client re-joins and re-fetches. |

---

## 3. The three native projects

### 3.0 Decisions shared by all three

| Decision | Choice | Basis |
| --- | --- | --- |
| Repo locations | `apps/apple-mobile`, `apps/macos`, `apps/windows`; shared Swift in `packages/apple-core`; generated protocol models in `packages/protocol` | Matches existing `apps/*` + `packages/*` layout **[V]** |
| Will `bun install` choke on them? | **No.** A directory under `apps/*` **without** a `package.json` is ignored by Bun workspaces — verified with a `bun install` probe on Bun 1.3.14 **[V]**. Do **not** add a `package.json` unless you want it in the workspace graph. | Probed |
| Feature/version gating | Read `/info` (`TServerInfo.version`) and the `X-Sharkord-Version` response header, compare with `semver` | **[V]** `http/info.ts`, `http/index.ts` |
| Protocol source | Lift the 76 inline zod schemas out of `apps/server/src/routers/*` into a generator input; emit Swift/C# models + a schema file | **[V]** + (c) |
| Transport readiness | Implement `others.handshake` → `others.joinServer` before anything else: it is the single gate to all state | **[V]** |
| CI | `macos-latest` runner for Apple; `windows-latest` for WinUI (the Windows app **cannot** be built on the Mac) | **[V]** |

### 3.1 `apps/apple-mobile` — iPhone + iPad (Swift + SwiftUI)

**How to create it.** One Xcode application target (`Sharkord`) with an iOS/iPadOS deployment
target, plus local SwiftPM packages. Do not put logic in the app target; the app is a shell that
vendors `packages/apple-core` (shared with `apps/macos`) and `packages/protocol`.

```
apps/apple-mobile/
  Sharkord.xcodeproj                 # thin: app target + Info.plist + entitlements
  Sharkord/
    SharkordApp.swift                # @main, scene setup
    AppDelegate.swift                # APNs / PushKit registration, background modes
    Info.plist                       # UIBackgroundModes: audio, voip; mic usage string
    Sharkord.entitlements            # push, aps-environment, app groups
packages/apple-core/                 # SwiftPM package — shared by apple-mobile AND macos
  Sources/SharkordCore/
    Networking/   TRPCClient.swift, WebSocketTransport.swift, ReconnectPolicy.swift, HTTPClient.swift
    State/        Store.swift, ServerStore.swift, MessageCache.swift, ChannelStore.swift
    Session/      AuthSession.swift, KeychainStore.swift, Handshake.swift
    RTC/          MediasoupDevice.swift, Transports.swift, ProduceConsume.swift
    Models/       (generated — never hand-edited)
  Tests/SharkordCoreTests/           # conformance tests against the schema artifact
```

**Layer split.**

| Layer | Contents (Apple) |
| --- | --- |
| Networking | WS + tRPC envelope, `handshake`/`joinServer`, reconnect `[1,2,4,8,8]s`, `POST /login`, `POST /upload`, `/public` file URLs |
| State | Reducers mirroring `features/server/slice.ts`; message cache with the detached-window rule |
| RTC | `libmediasoupclient` via a Swift wrapper (e.g. `mediasoup-client-swift`); producer/consumer transports |
| UI | SwiftUI; `NavigationSplitView` for iPad, tab/stack for iPhone |
| Platform | `AVAudioSession`, CallKit, PushKit/APNs, ScreenCaptureKit/ReplayKit, VideoToolbox |

**Phase-1 order (Login → Server → Channel → Text).** Voice is Phase 2 on mobile.

| Step | Work | Server call |
| --- | --- | --- |
| 1 | Server URL entry + reachability | `GET /info` |
| 2 | Login screen (identity + password) | `POST /login` → store JWT in Keychain |
| 3 | Connect + handshake | WS + `others.handshake` |
| 4 | Server password / join | `others.joinServer` |
| 5 | Render tree: categories → channels | from the join payload |
| 6 | Open a text channel, load history | `messages.getMessages` (cursor) |
| 7 | Send a message | `messages.sendMessage` |
| 8 | Live updates | subscribe `onMessage`, `onMessageUpdate`, `onMessageDelete`, `onMessageTyping` |
| 9 | Reconnect + re-join | mirror `reconnectToServer` |
| 10 | Attachments | `POST /upload` then `sendMessage.files` |

**Required system capabilities and APIs.**

| Capability | API | Phase |
| --- | --- | --- |
| Audio session / routing | `AVAudioSession` (`playAndRecord`, `voiceChat`) | 2 |
| Call UI + wake | CallKit / LiveCommunicationKit + PushKit + APNs | 2 |
| Background audio | `UIBackgroundModes: audio` (+ `voip` for push wake) | 2 |
| Screen share | ReplayKit (in-app broadcast on iOS) | 3 |
| Video encode/decode | VideoToolbox (via WebRTC) | 2 |
| Credentials | Keychain Services | 1 |
| Background refresh | BGTaskScheduler | 3 |

**Key risks.**

- **Background voice is the #1 mobile risk [V/R].** Apple: an audio session cannot *start* recording
  from the background; `audio` keeps an *active* session alive; `voip` is for incoming-call wake; any
  incoming call pre-empts a plain `playAndRecord` session. So the app must be foregrounded to start a
  call, and a sustained call needs an active session plus correct handling of interruptions. Design
  for "user starts the call in the foreground, it survives backgrounding" — not "always-on".
- No PushKit/CallKit on the Simulator → the full wake path must be tested on a device.
- `uid`-style App Store review pressure exists if you claim `voip` without a real incoming-call flow.
- iPad multitasking: no single "mobile" layout assumption; use size classes.

### 3.2 `apps/macos` — Swift + SwiftUI/AppKit

**How to create it.** A separate Xcode app target that **vendors the same `packages/apple-core`** —
this is the payoff of route (c): macOS and iOS/iPadOS share one Swift core with no FFI. AppKit is
used only where SwiftUI falls short (menu bar item, global event taps, screen-share pickers).

```
apps/macos/
  Sharkord.xcodeproj
  Sharkord/
    SharkordApp.swift                # @main
    AppKitBridge/   GlobalPTT.swift, StatusItem.swift, ScreenPicker.swift
    Info.plist + Sharkord.entitlements  # audio input; sandbox; accessibility (TCC)
# packages/apple-core is the SAME package — do not fork it
```

**Layer split.** Identical to §3.1 — `apple-core` supplies Networking, State and RTC orchestration.
The macOS delta is the UI layer (SwiftUI window + `NSStatusItem` menu-bar presence) and the platform
layer (Core Audio devices, ScreenCaptureKit, VideoToolbox, `CGEventTap` for PTT).

**Phase-1 order** — same ten steps as §3.1, then **voice in Phase 1** (macOS is the native voice
flagship): join voice → producer/consumer transports → mic → screen share.

**Required system capabilities and APIs.**

| Capability | API | Phase |
| --- | --- | --- |
| Audio capture/playback | Core Audio / `AVAudioEngine`; HAL device selection | 1 |
| Screen capture | ScreenCaptureKit (needs Screen Recording TCC permission) | 1 |
| Video codecs | VideoToolbox | 1 |
| Menu bar / tray | `NSStatusItem` | 1 |
| Global push-to-talk | `CGEventTap` / `NSEvent.addGlobalMonitorForEvents` — **requires the Accessibility TCC permission** | 2 |
| Notifications | `UNUserNotificationCenter` | 1 |
| Credentials | Keychain | 1 |

**Key risks.**

- **Global PTT needs Accessibility permission.** A global key monitor silently does nothing until the
  user grants Accessibility/Input Monitoring; the app must detect the failure and explain it.
- **Windows server**: the whole session must survive a reconnect (state layer is shared, so this is
  tested once and benefits both Apple targets).
- Sandbox: Screen Recording + Accessibility are separate TCC grants; both must be provisioned.
- Screen share must exclude own audio capture to avoid echo.

### 3.3 `apps/windows` — C# + WinUI 3

**How to create it.** `dotnet new` a WinUI 3 app inside a solution, then add class libraries. Note two
hard facts: **WinUI 3 / Windows App SDK are Windows-only and cannot be built on macOS** **[V]**, and
**the .NET SDK is not installed on the current Mac** **[V]**. So this project is developed on a
Windows machine or a VM, and CI runs on `windows-latest`.

```
apps/windows/
  Sharkord.sln
  Sharkord.App/            # WinUI 3 app (packaged): Views/, Tray/, Platform/
                           #   Platform/ = WASAPI.cs, ScreenCapture.cs, Hotkeys.cs, Dpapi.cs
  Sharkord.Core/           # WS, tRPC envelope, state, reducers
  Sharkord.Rtc/            # P/Invoke into libmediasoupclient (Phase 2)
  Sharkord.Core.Tests/
# packages/protocol/ emits the C# models consumed by Sharkord.Core
```

**Layer split.**

| Layer | Contents (Windows) |
| --- | --- |
| Networking | `ClientWebSocket` + tRPC envelope; `HttpClient` for `/login`, `/upload`, `/public` |
| State | Reducers + caches; **hand-port of the same rules** (this is where route (c) still duplicates logic) |
| RTC | `P/Invoke` into `libmediasoupclient` compiled with MSVC, wired to a native libwebrtc build |
| UI | WinUI 3 (Fluent); `TaskbarIcon`/`NotifyIcon` for tray |
| Platform | WASAPI, Windows.Graphics.Capture, Media Foundation, `RegisterHotKey` / low-level keyboard hook, DPAPI |

**Phase-1 order** — the same ten steps as §3.1, **text-only**; voice is Wave 2 (see risks).

**Required system capabilities and APIs.**

| Capability | API | Phase |
| --- | --- | --- |
| Audio capture/playback | WASAPI (shared/exclusive, device enumeration) | 2 |
| Screen capture | Windows.Graphics.Capture (`GraphicsCaptureItem`) | 2 |
| Codecs | Media Foundation (H.264, Opus) | 2 |
| System tray | `NotifyIcon` via WinUI/Shell integration | 1 |
| Global PTT | `RegisterHotKey` (per-window) + `WH_KEYBOARD_LL` hook for global | 2 |
| Gestures | `PointerPressed`/`LongPress` on touch devices | 2 |
| Credentials | Windows DPAPI (`ProtectedData`) | 1 |

**Key risks.**

- **Voice is the top Windows risk.** There is no mediasoup client for C# **[V]**; you must either
  P/Invoke `libmediasoupclient` (C++, MSVC build, libwebrtc dependency, large native binary) or
  reimplement the mediasoup protocol over a C# WebRTC stack (very expensive). **Recommendation:
  ship Windows text-first and gate voice on a separate milestone.** **[R]**
- **No cross-build from macOS** — CI/CD must run on Windows; local development needs a Windows VM. **[V]**
- `RegisterHotKey` is per-window and can be stolen by other apps; a truly global PTT needs a
  low-level keyboard hook, which system antivirus may flag.
- Packaged vs unpackaged deployment changes file paths and elevation behaviour.
- Whatever state logic is written here duplicates `apple-core` — the exact cost route (c) accepts.

### 3.4 Cross-platform risk ranking

| Rank | Risk | Route affected | Mitigation |
| --- | --- | --- | --- |
| 1 | **Voice engine does not exist for C# → Windows may ship text-only for a long time** | All | Gate Windows voice on its own milestone; P/Invoke `libmediasoupclient` and prototype early **[V]** |
| 2 | **iOS background-voice constraints** (cannot start a session in background; interruptions pre-empt) **[V]** | Apple | Start calls in the foreground; use CallKit when answerable; test on device |
| 3 | **tRPC WS wire format is not a public spec** | (b)/(c) native | Versioned protocol endpoint or conformance harness in CI **[R]** |
| 4 | **Plugin UI cannot exist natively without a web view** **[V]** | All | Declare plugins web-only in v1; plan a WebView host later |
| 5 | macOS global PTT needs Accessibility TCC | macOS | Detect denial, surface a guided fix |
| 6 | Windows build only on Windows **[V]** | Windows | CI on `windows-latest`; local VM |
| 7 | Protocol drift as upstream moves (`0.0.25`, 35 migrations) **[V]** | All | Generate models; assert against `/info` version; keep `packages/shared` as the merge point |

### 3.5 Suggested first milestones

| Milestone | Deliverable | Blocks |
| --- | --- | --- |
| M0 | `packages/protocol` generator emitting Swift + C# models from the lifted zod schemas, with a conformance test | Everything |
| M1 | `packages/apple-core` networking + state + session; iOS Login→Channel→Text live | Apple targets |
| M2 | macOS app reusing `apple-core`; adds voice | macOS |
| M3 | Windows app (WinUI 3) reusing generated models; Login→Channel→Text | Windows |
| M4 | Windows voice spike: `libmediasoupclient` P/Invoke feasibility report | Windows voice |

### 3.6 Open questions to settle before M0

1. Does the project accept a documented, versioned protocol endpoint on the server (the clean fix for
   risk #3), or is mirroring tRPC v11 internals acceptable? **[R]**
2. Are plugins explicitly out of scope for native v1 (risk #4)? **[R]**
3. Is the `packages/apple-core` SwiftPM package the shared core for *both* Apple targets, or does
   macOS get its own? Recommendation: one package, split only if Voice pushes conflicting needs. **[R]**
4. Which mediasoup Apple wrapper becomes the supported one (`VLprojects/mediasoup-client-swift` vs
   `MediaSFU/mediasfu-mediasoup-client-apple`)? Both are third-party; neither is official. **[V]**
