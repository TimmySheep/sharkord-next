# RTC Architecture

> 中文版: [RTC_ARCHITECTURE.zh-CN.md](RTC_ARCHITECTURE.zh-CN.md)

How media actually flows in Sharkord Next — server, client, signaling, deployment — with a
file:line map for every claim, followed by a concrete analysis of what a P2P ("direct") media
path would require.

Audience: developers about to build P2P 1v1 media and additional clients. Base commit
`c611bb4` (branch `development`). Server SFU is **mediasoup 3.19.19** (`apps/server/package.json:57`),
client media layer is **mediasoup-client ^3.18.0** (`apps/client/package.json:47`).

Legend: **[v]** verified in this tree. `unknown` marks something not provable from the code here.
Paths are relative to the repo root.

---

## 0. The 30-second model

- One `VoiceRuntime` per voice channel, one mediasoup `Router` per runtime (`apps/server/src/runtimes/voice.ts:501-513`).
- Every participant gets **two** WebRTC transports: a send transport and a recv transport
  (`apps/server/src/runtimes/voice.ts:534-600`).
- The server **routes** RTP. It never mixes. A producer from A is copied to a separate consumer
  for each other member B, C, … (`apps/server/src/routers/voice/consume.ts:48-52`).
- Control plane (auth, signaling, events) is tRPC over **WebSocket**, sharing the HTTP port
  (`apps/server/src/utils/wss.ts:257`, `apps/server/src/utils/create-servers.ts:4-8`).
- Media plane is **WebRTC over UDP** (TCP fallback) on `webRtc.port`, default `40000`
  (`apps/server/src/config.ts:124-128`).

---

## 1. mediasoup server initialization

Entry point is `loadMediasoup()` in `apps/server/src/utils/mediasoup.ts:16-76`, awaited during
boot after HTTP/WS but before voice runtimes:

- `apps/server/src/index.ts:24-29` — `loadDb` → `pluginManager.init` → `createServers` →
  `loadMediasoup` → `initVoiceRuntimes`.
- `apps/server/src/index.ts:26-27` — HTTP/WS come up first; the mediasoup worker is created after.

### Worker

- `apps/server/src/utils/mediasoup.ts:17` — `const port = +config.webRtc.port`.
- `:19-23` — `workerConfig` sets `logLevel: 'debug'`, `disableLiburing: true`, and
  `workerBin: MEDIASOUP_BINARY_PATH`.
- `:33-34` — `patchSpawnForMediasoup(); mediaSoupWorker = await mediasoup.createWorker(workerConfig)`.
  The patch (`apps/server/src/utils/bun-mediasoup-workaround.ts:1-18`) replaces
  `child_process.spawn` with `Bun.spawn()` **only** for the mediasoup worker, because Bun on
  Windows breaks the two extra stdio pipes (fd 3/4) mediasoup uses for FlatBuffers IPC.
- `:41-45` — on `'died'` the process logs and `process.exit(0)` after 2s.
- Binary path is resolved in `apps/server/src/helpers/paths.ts:41`.

### WebRtcServer: production vs dev

This is the single most important fork for deployment:

- **Production** (`IS_PRODUCTION`, `:49-63`):
  - `:50` — `const announcedAddress = config.webRtc.announcedAddress || SERVER_PUBLIC_IP`.
  - `:52-57` — `createWebRtcServer({ listenInfos: [{udp, ip:'0.0.0.0', announcedAddress, port},
    {tcp, ip:'0.0.0.0', announcedAddress, port}] })`.
  - `:59` — `webRtcServerListenInfo = { ip: '0.0.0.0', announcedAddress }`.
- **Dev / non-production** (`:64-75`):
  - `:66-69` — `listenInfos` are `{udp, ip:'127.0.0.1', port}` and `{tcp, ip:'127.0.0.1', port}`.
  - `:72` — `webRtcServerListenInfo = { ip: '127.0.0.1' }` (no `announcedAddress`).
  - `:74` — log line: `WebRtcServer created on 127.0.0.1:${port} (dev mode)`. This is the log
    observed on the dev box; it confirms dev binds loopback-only.

`IS_PRODUCTION` is `process.env.SHARKORD_ENV === 'production'` (`apps/server/src/utils/env.ts:15-17`),
injected at build time. So the branch you get depends on how the build/container sets `SHARKORD_ENV`
(`unknown` from this tree alone which value a given deployment uses).

### announcedAddress origin and priority

Priority, highest first:

1. Explicit `webRtc.announcedAddress` from `config.ini` (`apps/server/src/config.ts:64-68`,
   default `''` at `:126`).
2. Auto-detected public IP.

- `apps/server/src/config.ts:291-293` — `SERVER_PUBLIC_IP` is `undefined` when
  `config.webRtc.announcedAddress` is set, so the third-party lookup is skipped entirely.
- `apps/server/src/helpers/network.ts:58-78` — `getPublicIp()` tries `ipv4.icanhazip.com` →
  `ipify` → `ifconfig.me`, each with a 3s timeout (`:15-18`). On total failure it warns and voice
  breaks (`:72-75`).
- `apps/server/src/config.ts:287` — `SERVER_PRIVATE_IP` from `getPrivateIp()`
  (`apps/server/src/helpers/network.ts:4-12`, first non-internal IPv4).
- Env override: `SHARKORD_WEBRTC_ANNOUNCED_ADDRESS` (`apps/server/src/config.ts:278`).
- Startup prints the effective public address (`apps/server/src/utils/print-debug.ts:13-15`).

The `announcedAddress` is consumed only by `createWebRtcServer` — it becomes the IP in every ICE
candidate the server hands out. `VoiceRuntime.getListenInfo()` re-exposes it
(`apps/server/src/runtimes/voice.ts:1082-1087`).

---

## 2. Voice channel lifecycle

All voice procedures are registered in `apps/server/src/routers/voice/index.ts:29-54`. Each route
delegates to the `VoiceRuntime` in `apps/server/src/runtimes/voice.ts`.

| Step | tRPC route | Server handler | Runtime method |
|---|---|---|---|
| join | `voice.join` | `apps/server/src/routers/voice/join.ts:24-118` | `addUser` (`voice.ts:402-420`) |
| create send transport | `voice.createProducerTransport` | `routers/voice/create-producer-transport.ts:5-15` | `createProducerTransport` (`voice.ts:575-600`) |
| create recv transport | `voice.createConsumerTransport` | `routers/voice/create-consumer-transport.ts:5-15` | `createConsumerTransport` (`voice.ts:534-561`) |
| connect send | `voice.connectProducerTransport` | `connect-producer-transport.ts:6-23` | `transport.connect` |
| connect recv | `voice.connectConsumerTransport` | `connect-consumer-transport.ts:6-23` | `transport.connect` |
| publish | `voice.produce` | `produce.ts:55-88` | `addProducer` (`voice.ts:632`) |
| subscribe | `voice.consume` | `consume.ts:20-81` | `addConsumer` (`voice.ts:748`) |
| list peers | `voice.getProducers` | `get-producers.ts:4-8` | `getRemoteIds` (`voice.ts:1050-1068`) |
| stop one track | `voice.closeProducer` | `close-producer.ts:8-55` | `removeProducer` (`voice.ts:686-721`) |
| leave | `voice.leave` | `leave.ts:11-53` | `removeUser` → `cleanupUserResources` (`voice.ts:422-465`) |

**join**: checks `Permission.JOIN_VOICE_CHANNELS` and channel `JOIN` permission
(`join.ts:39,44`), rejects non-voice and DM channels (`:63-71`), rejects double-join
(`:73-80`), then `runtime.addUser` (`:98`) and returns `router.rtpCapabilities` (`:113-117`).

**Transports**: both transports share one factory, `createTransport` (`voice.ts:507-533`), which
calls `router.createWebRtcTransport({ webRtcServer, enableUdp: true, enableTcp: true,
preferUdp: true, preferTcp: false, initialAvailableOutgoingBitrate: Math.min(10_000_000, maxBitrate) })`
and then clamps both directions to `config.webRtc.maxBitrate` (`:202-203`). Returned params are
`{id, iceParameters, iceCandidates, dtlsParameters}` (`:205-210`).

**connect**: the client receives a `connect` event from mediasoup-client and round-trips
`dtlsParameters` to the matching server route (`apps/client/src/components/voice-provider/hooks/use-transports.ts:92-110`
for send, `:207-225` for recv). The server calls `transport.connect` (`connect-producer-transport.ts:22`).

**produce**: server verifies per-kind permission (`produce.ts:16-33`: audio→`SPEAK`,
video→`WEBCAM`+`ENABLE_WEBCAM`, screen→`SHARE_SCREEN`), then `producerTransport.produce`
(`produce.ts:73-77`) and `runtime.addProducer` (`:79`), then publishes `VOICE_NEW_PRODUCER`
channel-wide (`:81-85`).

**consume**: `runtime.getProducer(kind, remoteId)` (`consume.ts:23`), `router.canConsume` guard
(`:38-46`), then `consumerTransport.consume({producerId, rtpCapabilities, paused:false})` (`:48-52`)
and `runtime.addConsumer` (`:54`). A `producerclose` listener publishes `VOICE_PRODUCER_CLOSED`
(`:56-68`).

**closeProducer / leave**: closing a track closes the producer and notifies the channel
(`close-producer.ts:44-54`). Leaving removes the user and tears down both transports, all four
producer kinds, the user's consumers, and every other user's consumers *of that user*
(`voice.ts:433-465`). An ungraceful WebSocket close also calls `removeUser`
(`apps/server/src/utils/wss.ts:223-232`).

---

## 3. One stream from A to B

1. **Capture (A)** — `getUserMedia`/`getDisplayMedia` in the client
   (`apps/client/src/components/voice-provider/index.tsx:519-520` for mic, `:710-711` webcam,
   `:905-907` screen).
2. **Produce (A)** — `producerTransport.current.produce({track, codecOptions, appData})`
   (`index.tsx:628-638` audio; `:759-761` video; `:1057-1068` screen audio). mediasoup-client
   fires its `produce` event, which calls the server route
   (`use-transports.ts:136-186` → `trpc.voice.produce.mutate`, `:153-158`).
3. **Router (server)** — the producer is stored on the runtime (`voice.ts:632-684`). Nothing is
   transcoded or mixed: mediasoup forwards RTP.
4. **Notify (server → channel)** — `VOICE_NEW_PRODUCER` is published only to that channel
   (`produce.ts:81-85`; subscription is channel-scoped, `events.ts:65-76`).
5. **Consume (B)** — B receives the event, calls `consume(remoteId, kind, deviceRtpCapabilities)`
   (`apps/client/src/components/voice-provider/hooks/use-voice-events.ts:63-104`), which calls
   `trpc.voice.consume.mutate` and then `consumerTransport.consume(...)`
   (`use-transports.ts:302-338`), attaches the track to a new `MediaStream` (`:410-420`) and hands
   it to the remote-streams hook.
6. **Existing producers** — on join, B doesn't wait for events; `consumeExistingProducers` calls
   `voice.getProducers` and consumes every remote id (`use-transports.ts:438-491`).

**Why routed, not mixed [v]**: the server keeps per-user producer maps and a consumer map keyed
`${remoteId}-${kind}` (`voice.ts:144-151`, `:213-219`, `:748-749`). There is no mixer, no
transcoder, no server-side compositor anywhere in `runtimes/voice.ts`. Each consumer is a distinct
server→receiver RTP stream.

**Bandwidth model**: egress is roughly `sum(producer bitrate) × (receivers − 1)`. With N people
all sending audio (Opus ≈ 128 kbps cap, `voice.ts:93`) and each receiving N−1 streams, the server
uploads `≈ (N−1)² × 128 kbps` for voice alone. Video/screen multiplies this hard. `webRtc.maxBitrate`
(`config.ts:67`, default `30_000_000`, `:127`) is the per-transport clamp on top (`voice.ts:199-203`),
not a global scheduler. This quadratic egress is exactly the pressure that motivates both simulcast
(§4) and P2P (§7).

---

## 4. Codec and parameter surface

### Router codecs (`apps/server/src/runtimes/voice.ts:33-97`)

- Opus (`:82-95`): `clockRate: 48000`, `channels: 2`, params `useinbandfec=1`, `usedtx=1`,
  `stereo=1`, `sprop-stereo=1`, `maxplaybackrate=48000`, `maxaveragebitrate=128000`.
- Video: `VP9` profile-id 0 (`:35-43`), `VP8` (`:44-51`), `H264` 42e01f and 640032 (`:52-73`),
  `AV1` (`:74-81`). All carry `x-google-start-bitrate: 2000` (kbps); the router sets **no**
  `x-google-max-bitrate`.

### Opus settings on the client (producer `codecOptions`)

- Microphone (`index.tsx:630-636`): `opusStereo: false`, `opusFec: true`, `opusDtx: false`,
  `opusMaxPlaybackRate: 48000`, `opusMaxAverageBitrate: 128000`.
- Screen-share audio (`index.tsx:1060-1065`): `opusStereo: true`, `opusFec: true`, `opusDtx: false`,
  same rate/cap.

Note the stereo asymmetry: the router advertises stereo, but the mic producer disables it. DTX is
advertised at the router and disabled at the producer, so the effective mic setting is **DTX off**.

### Screen share

- Capture constraints (`index.tsx:878-899`): resolution/framerate/cursor from
  `devices.screenResolution/screenFramerate/screenCursor`; audio `channelCount: 2`, `sampleRate: 48000`.
- Defaults (`apps/client/src/components/devices-provider/index.tsx:44-48`): `simulcastEnabled: true`,
  `screenResolution: '720p'`, `screenFramerate: 30`, `screenCodec: AUTO`, `screenBitrate: 6000`.
- `DEFAULT_BITRATE = 6000` kbps (`packages/shared/src/statics/index.ts:29`); used as the fallback if
  no per-device bitrate (`index.tsx:947`).
- Codec options (`index.tsx:960-972`): `videoGoogleStartBitrate: min(2000, max)`,
  `videoGoogleMaxBitrate: max`, `videoGoogleMinBitrate: min(200, max)`.

### Simulcast

Gated by **both** a server setting and a client setting: `simulcastEnabled = server.webRtcSimulcastEnabled
&& devices.simulcastEnabled` (`index.tsx:210-211`). The server default is **off**
(`apps/server/src/db/seed.ts:70`; schema default `false`, `apps/server/src/db/schema.ts:83-88`),
even though the client default is on. The setting is surfaced publicly along with
`webRtcMaxBitrate` (`apps/server/src/db/queries/server.ts:52-53`).

When on, only **VP8** is used (`getSimulcastCodec`, `helpers.ts:207-212`), with three layers:

- Webcam encodings (`helpers.ts:122-149`, constants `statics.ts:1-28`): low (≤150 kbps, 24 fps,
  ×4 downscale), mid (≤500 kbps, 30 fps, ×2), high (source scale, caller max). Webcam max is
  `SIMULCAST_WEBCAM_MAX_BITRATE = 900_000` (`statics.ts:2`).
- Screen encodings (`helpers.ts:151-178`): low (≤1.5 Mbps, 30 fps, ×4), mid (≤4 Mbps, 60 fps, ×2),
  high (source, caller max) — screen needs far more bitrate or the browser downscales the layers.
- Layer labels `Low/Medium/High` are attached as `qualityLayers` appData (`helpers.ts:180-190`) and
  validated against the encoding count server-side (`voice.ts:221-290`).

Non-simulcast screen share honours `devices.screenCodec` (`index.tsx:929-945`). Webcam/screen
produce falls back to a non-simulcast producer if the simulcast produce throws
(`index.tsx:762-773`, `:997-1009`).

Consumers can pick a spatial layer; `voice.setConsumerQuality` is served by
`set-consumer-quality.ts` and applies stored quality after consume (`use-transports.ts:393-408`).

---

## 5. Signaling channel

The control plane is tRPC, and the client uses **only** a WebSocket link:

- `apps/client/src/lib/trpc.ts:45` — `protocol = https ? 'wss' : 'ws'`.
- `:47-48` — `createWSClient({ url: \`${protocol}://${host}\` })`; `:100-102` `wsLink`.
- Connection params carry the session token (`:88-92`).

On the server:

- `apps/server/src/utils/create-servers.ts:4-8` — `createHttpServer()` then `createWsServer(httpServer)`.
- `apps/server/src/http/index.ts:104-106` — one `http.createServer`; `:244` `server.listen(port)`.
- `apps/server/src/utils/wss.ts:257` — `new WebSocketServer({ server })` attaches the WS server to
  the **same** HTTP server/port. `applyWSSHandler` mounts the tRPC router (`:283-292`) with keepalive.
- Default port `4991` (`apps/server/src/config.ts:101`).

Voice events ride this one socket as tRPC subscriptions:

- `apps/server/src/routers/voice/events.ts:63-89` — `onNewProducer` / `onProducerClosed` are
  **channel-scoped** (`subscribeForChannel`); `:12-42` broadcast events (`onJoin`, `onLeave`,
  `onUpdateState`, `onReaction`, `onMoved`) are global/user-scoped.
- `apps/server/src/utils/pubsub.ts:137-322` — in-process `EventEmitter` pub/sub with
  global / per-user / per-channel fan-out.
- Client subscriptions: `apps/client/src/components/voice-provider/hooks/use-voice-events.ts:63-189`.

**Boundary**: HTTP + WS are both TCP on `config.server.port`. Media is WebRTC on `webRtc.port`
(UDP preferred, TCP fallback enabled). So even when the client's WebSocket is healthy, media can
fail independently — this is the crux of §6 and §8.

---

## 6. Live deployment topology and ICE constraints

Target topology for a self-hosted instance behind FRP (`unknown`: no FRP config exists in this
repo; this describes the shape the code assumes):

```
                    +-------------------------------+
 browser  ----TCP--> | FRP TCP tunnel -> :4991       |  HTTP + WS (tRPC) + static assets
   A      ----UDP--> | FRP UDP tunnel -> :40000      |  WebRTC media (RTP/RTCP/DTLS)
                    +-------------------------------+
```

Constraints the code imposes:

1. **Media port must match the tunnel's public UDP port.** mediasoup advertises ICE candidates
   using the `WebRtcServer` `listenInfo.port`, which is exactly `config.webRtc.port`
   (`apps/server/src/utils/mediasoup.ts:17,54-55`). There is no separate "announced port" field in
   this config. So if FRP maps public UDP `P` to internal `40000` and `P != 40000`, candidates will
   advertise `40000` and the client will send media to the wrong public port. **The UDP tunnel must
   expose the same port number (`40000`) it forwards to.**
2. **`announcedAddress` must be reachable by the peers.** In production, if
   `webRtc.announcedAddress` is empty, the server auto-detects its own public IP
   (`network.ts:58-78`). Behind FRP that detection often returns the FRP host's IP or a private/
   CGNAT address, not the endpoint clients reach. Set `webRtc.announcedAddress` explicitly to the
   publicly reachable IP/host of the UDP tunnel.
3. **No STUN/TURN anywhere.** No STUN/TURN server is configured or referenced in the repo
   (grep for `stun:`/`turn:`/`iceServers` returns nothing). ICE relies entirely on the server's
   own `{announcedAddress, port}` udp+tcp candidates (`mediasoup.ts:52-57`). mediasoup operates as
   an ICE-lite endpoint on that single address; there is no fallback relay if a peer's NAT blocks it.
4. **TCP fallback also lives on `webRtc.port`.** `enableTcp: true` (`voice.ts:196`) means the same
   port must be reachable over TCP too if you want the fallback, or a client with UDP blocked will
   fail.

Debugging aids already in the client: transport stats expose the succeeded `candidate-pair` and RTT
(`apps/client/src/components/voice-provider/hooks/use-transport-stats.ts:115-120`, `:75-80`), and
there is a voice-debug buffer plus `window.sharkordDebug`
(`apps/client/src/helpers/voice-debug.ts`).

---

## 7. P2P entry-point analysis

**Does mediasoup do P2P?** No. mediasoup is SFU-only; there is no client-to-client media mode, and
`mediasoup-client` speaks only the mediasoup transport protocol (send/recv transports bound to a
server `WebRtcTransport`). The one `createDirectTransport()` in the codebase
(`apps/server/src/plugins/actions/consume-voice-producer.ts:33`) is a **server-local, non-WebRTC**
pipe for plugins to read RTP — it is not a peer path. Therefore a 1v1 direct media mode must be a
**new WebRTC path built on `RTCPeerConnection`**, added alongside the SFU path, not a configuration
of the existing one.

Concretely, to land "1v1 direct media", these are the touch points:

### 7.1 Server signaling (new)

- Add a new route module under `apps/server/src/routers/voice/` (pattern:
  `create-producer-transport.ts:5-15`) and register it in `apps/server/src/routers/voice/index.ts:29-54`.
  Required verbs: session open/close, SDP offer/answer relay, ICE candidate relay.
- Add event kinds to `ServerEvents` and to the pub/sub `Events` map
  (`apps/server/src/utils/pubsub.ts:65-111`); the existing per-user fan-out
  (`publishFor`/`subscribeFor`, `pubsub.ts:161-181`, `:205-252`) is the right primitive for relaying
  to the specific peer.
- Reuse the existing session gate `getCurrentVoiceRuntime` (`apps/server/src/helpers/get-current-voice-runtime.ts:6-22`)
  only if direct calls are modeled as channel members. For DM/friend calls, note voice DMs are
  currently skipped at runtime creation (`apps/server/src/runtimes/index.ts:17`) — that is the
  natural place to introduce a non-channel room.

### 7.2 Permissions

- `join.ts:39,44` and `produce.ts:16-33` already gate join and per-kind publish. The new signal
  routes must re-check the same permissions and additionally assert **both peers are authorized in
  the same room** — otherwise the relay becomes an SSRF/harassment vector. `KIND_PERMISSIONS`
  (`produce.ts:16-33`) is the table to mirror.

### 7.3 Server media layer / abstraction

- Today a runtime *owns* transports unconditionally (`voice.ts:140-151`, `createTransport`
  `:507-533`). A direct call must not create a `WebRtcTransport` at all; the server only relays
  SDP/ICE. Introduce a small **`MediaSession` abstraction** on the runtime:
  - `ServerTransport` (existing mediasoup path) vs `DirectTransport`-style **relay** (no mediasoup
    transport; server forwards opaque SDP/ICE between two peers).
  - Please **do not** name it `DirectTransport` to avoid colliding with mediasoup's own
    `router.createDirectTransport()` semantics (`consume-voice-producer.ts:33`) — call the new one
    `PeerRelaySession` or similar.
- Mode selection belongs on the runtime/channel (sfu vs direct vs auto), surfaced to clients.

### 7.4 Client media layer (new)

- `use-transports.ts` is entirely mediasoup-client (`Device`, `createSendTransport`,
  `createRecvTransport`, `consume`, `produce` — `use-transports.ts:77-436`). Direct mode needs a
  parallel manager using `RTCPeerConnection`: add tracks, create offer, gather ICE, apply the
  remote answer, hole-punch, and then reuse the existing `addRemoteUserStream`
  (`use-transports.ts:410-421`) so the UI layer is untouched.
- The init sequence (`index.tsx:1158-1225`) must branch: SFU mode runs `Device.load` →
  transports → `consumeExistingProducers` → `startMicStream`; direct mode runs peer-connection
  setup instead. The `ConnectionStatus` enum (`index.tsx:104-109`) already fits.

### 7.5 ICE negotiation

- SFU mode gets ICE from the server (`createTransport`, `voice.ts:205-210`). Direct mode gets ICE
  from the browser's `RTCPeerConnection` and must **relay it through the signaling routes above**.
- Provide STUN/TURN config for direct mode — none exists today (§6.3). Without a TURN relay, a
  large fraction of NAT pairs will fail to hole-punch; that is the main risk of shipping P2P first.

### 7.6 Recommended first cut

Scope P2P to **1v1, audio-first, DM/private calls**, leaving the SFU path untouched for channels.
The `runtimes/index.ts:17` DM skip and the per-user pub/sub are already shaped for it, and audio
needs no simulcast/layer machinery (§4). Video/screen can follow once ICE success rates are known.

---

## 8. Current known issue — FRP UDP relay instance

**Observed [v, report]:** On a real self-hosted instance reached through an FRP UDP relay, the
server-side `voice.join → produce` chain completes with no error, yet the client shows
**"Failed to initialize voice connection"**.

Where that string comes from [v]:

- `apps/client/src/i18n/locales/en/common.json:51` — `"failedInitVoiceConnection": "Failed to initialize voice connection"`.
- `apps/client/src/hooks/use-select-channel.ts:45-51` — it is toasted **only** after
  `init(...)` rejects, and it immediately calls `leaveVoice({ reason: 'init_failed' })`.

What that implies [v]: the failure is strictly inside `init()` (`index.tsx:1158-1225`), which
rethrows any caught error at `:1212`. The steps that can actually throw are `device.load`
(`:1178`), something inside `consumeExistingProducers` (`:1198`), or `startMicStream` (`:1199`).
Critically, **transport creation swallows its own errors**: `createProducerTransport` and
`createConsumerTransport` log and continue (`use-transports.ts:187-189`, `:259-261`), so a failed
transport does not by itself reject `init` — it leaves the ref `undefined`, after which
`startMicStream` throws `'Producer transport is not available'` (`index.tsx:624-626`) and
`consume()` silently skips (`use-transports.ts:270-276`).

### Already ruled out [v]

- Server boot/worker: dev log shows `WebRtcServer created on 127.0.0.1:40000 (dev mode)`
  (`mediasoup.ts:74`), so the worker and WebRtcServer came up.
- Auth/permissions for join: `join` returned in the report; `join.ts:39,44` passed.
- Producer publish reached the server: `voice.produce` returned (`produce.ts:73-87`), so the send
  transport's DTLS connect succeeded for at least that transport.

### Remaining suspects [speculative — not verified]

1. **Wrong/empty `announcedAddress` behind FRP.** Production candidates use
   `config.webRtc.announcedAddress || SERVER_PUBLIC_IP` (`mediasoup.ts:50`). If unset, auto-detect
   (`network.ts:58-78`) likely returns an address peers cannot reach, so the **recv** transport
   never completes even though the send transport did. Most likely culprit.
2. **UDP port mismatch.** FRP exposes a public UDP port different from `40000`; mediasoup advertises
   the listen port (`mediasoup.ts:17,54-55`), so media to the advertised port is dropped. (§6.1)
3. **Recv-side DTLS never establishes** because of (1)/(2); `init` then fails at
   `consumeExistingProducers`/monitoring (`index.tsx:1198-1201`).
4. **`device.load` RTP-capability mismatch** (`index.tsx:1176-1192`) — unlikely to be FRP-related,
   but cheap to confirm from the client debug log.

### How to confirm

Turn on the client voice debug buffer (`apps/client/src/helpers/voice-debug.ts`) and
`printVoiceStats` (`use-transport-stats.ts:115-120` reports the succeeded `candidate-pair`), then
check: (a) the exact step in `init` that threw, (b) the ICE candidate `address:port` the browser
received, (c) whether it matches the FRP public UDP endpoint. Set `webRtc.announcedAddress`
explicitly and ensure the UDP tunnel's public port equals `40000`; re-test. Anything not reproduced
here stays `unknown`.

---

## Appendix — quick file map

| Concern | File |
|---|---|
| mediasoup worker + WebRtcServer | `apps/server/src/utils/mediasoup.ts` |
| Runtime (routers/transports/producers/consumers) | `apps/server/src/runtimes/voice.ts` |
| Voice tRPC routes | `apps/server/src/routers/voice/*.ts` |
| Signaling transport (HTTP+WS) | `apps/server/src/utils/wss.ts`, `apps/server/src/http/index.ts` |
| Pub/sub events | `apps/server/src/utils/pubsub.ts` |
| Config + public IP resolution | `apps/server/src/config.ts`, `apps/server/src/helpers/network.ts` |
| Client transports (mediasoup) | `apps/client/src/components/voice-provider/hooks/use-transports.ts` |
| Client capture/produce/init | `apps/client/src/components/voice-provider/index.tsx` |
| Client encodings/simulcast | `apps/client/src/components/voice-provider/helpers.ts`, `statics.ts` |
| Client join entry + failure toast | `apps/client/src/hooks/use-select-channel.ts`, `features/server/voice/actions.ts` |
| tRPC WS client | `apps/client/src/lib/trpc.ts` |
