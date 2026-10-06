# RTC 架构
> 本文是 [`RTC_ARCHITECTURE.md`](RTC_ARCHITECTURE.md) 的中文翻译。英文版为权威版本，如有歧义以英文版为准。

Sharkord Next 中媒体究竟如何流转 —— 服务端、客户端、信令、部署 —— 每一条论断都配有
file:line 定位，其后是对 P2P（“直连”）媒体路径所需改动的具体分析。

读者：即将着手实现 P2P 1v1 媒体与更多客户端的开发者。基线提交
`c611bb4`（分支 `development`）。服务端 SFU 为 **mediasoup 3.19.19**（`apps/server/package.json:57`），
客户端媒体层为 **mediasoup-client ^3.18.0**（`apps/client/package.json:47`）。

图例：**[v]** 表示已在本代码树中验证。`unknown` 标记无法仅凭此处代码证明的事项。
路径均相对于仓库根目录。

---

## 0. 30 秒速览模型

- 每个语音频道一个 `VoiceRuntime`，每个 runtime 一个 mediasoup `Router`（`apps/server/src/runtimes/voice.ts:501-513`）。
- 每个参与者获得**两个** WebRTC 传输通道（transport）：一个发送传输通道和一个接收传输通道
  （`apps/server/src/runtimes/voice.ts:534-600`）。
- 服务端**转发（routes）** RTP。它从不混流。来自 A 的 producer 会被复制为 B、C……每个其他成员各自的
  consumer（`apps/server/src/routers/voice/consume.ts:48-52`）。
- 控制面（认证、信令、事件）是通过 **WebSocket** 承载的 tRPC，与 HTTP 共用端口
  （`apps/server/src/utils/wss.ts:257`、`apps/server/src/utils/create-servers.ts:4-8`）。
- 媒体面是运行在 `webRtc.port` 上的 **基于 UDP 的 WebRTC**（TCP 回退），默认 `40000`
  （`apps/server/src/config.ts:124-128`）。

---

## 1. mediasoup 服务端初始化

入口点是 `apps/server/src/utils/mediasoup.ts:16-76` 中的 `loadMediasoup()`，在启动过程中于
HTTP/WS 之后、voice runtime 之前被 await：

- `apps/server/src/index.ts:24-29` — `loadDb` → `pluginManager.init` → `createServers` →
  `loadMediasoup` → `initVoiceRuntimes`。
- `apps/server/src/index.ts:26-27` — HTTP/WS 先启动；mediasoup worker 随后创建。

### Worker

- `apps/server/src/utils/mediasoup.ts:17` — `const port = +config.webRtc.port`。
- `:19-23` — `workerConfig` 设置 `logLevel: 'debug'`、`disableLiburing: true` 以及
  `workerBin: MEDIASOUP_BINARY_PATH`。
- `:33-34` — `patchSpawnForMediasoup(); mediaSoupWorker = await mediasoup.createWorker(workerConfig)`。
  该补丁（`apps/server/src/utils/bun-mediasoup-workaround.ts:1-18`）**仅**对 mediasoup worker
  用 `Bun.spawn()` 替换 `child_process.spawn`，原因是 Windows 上的 Bun 会破坏 mediasoup
  用于 FlatBuffers IPC 的两个额外 stdio 管道（fd 3/4）。
- `:41-45` — 当触发 `'died'` 时，进程记录日志并在 2 秒后 `process.exit(0)`。
- 二进制路径在 `apps/server/src/helpers/paths.ts:41` 中解析。

### WebRtcServer：生产 vs 开发

这是部署时最关键的一处分支：

- **生产环境**（`IS_PRODUCTION`，`:49-63`）：
  - `:50` — `const announcedAddress = config.webRtc.announcedAddress || SERVER_PUBLIC_IP`。
  - `:52-57` — `createWebRtcServer({ listenInfos: [{udp, ip:'0.0.0.0', announcedAddress, port},
    {tcp, ip:'0.0.0.0', announcedAddress, port}] })`。
  - `:59` — `webRtcServerListenInfo = { ip: '0.0.0.0', announcedAddress }`。
- **开发 / 非生产环境**（`:64-75`）：
  - `:66-69` — `listenInfos` 为 `{udp, ip:'127.0.0.1', port}` 和 `{tcp, ip:'127.0.0.1', port}`。
  - `:72` — `webRtcServerListenInfo = { ip: '127.0.0.1' }`（无 `announcedAddress`）。
  - `:74` — 日志行：`WebRtcServer created on 127.0.0.1:${port} (dev mode)`。这是在开发机上
    观察到的日志；它证实开发模式仅绑定 loopback。

`IS_PRODUCTION` 即 `process.env.SHARKORD_ENV === 'production'`（`apps/server/src/utils/env.ts:15-17`），
在构建时注入。因此你走哪条分支取决于构建/容器如何设置 `SHARKORD_ENV`
（仅凭本代码树无法得知某个具体部署使用哪个值，`unknown`）。

### announcedAddress 的来源与优先级

优先级从高到低：

1. 来自 `config.ini` 的显式 `webRtc.announcedAddress`（`apps/server/src/config.ts:64-68`，
   默认 `''`，见 `:126`）。
2. 自动探测得到的公网 IP。

- `apps/server/src/config.ts:291-293` — 当设置了 `config.webRtc.announcedAddress` 时，
  `SERVER_PUBLIC_IP` 为 `undefined`，因此完全跳过第三方查询。
- `apps/server/src/helpers/network.ts:58-78` — `getPublicIp()` 依次尝试 `ipv4.icanhazip.com` →
  `ipify` → `ifconfig.me`，每个超时 3 秒（`:15-18`）。若全部失败，它会告警且语音功能中断（`:72-75`）。
- `apps/server/src/config.ts:287` — `SERVER_PRIVATE_IP` 来自 `getPrivateIp()`
  （`apps/server/src/helpers/network.ts:4-12`，取第一个非内部 IPv4）。
- 环境变量覆盖：`SHARKORD_WEBRTC_ANNOUNCED_ADDRESS`（`apps/server/src/config.ts:278`）。
- 启动时会打印实际生效的公网地址（`apps/server/src/utils/print-debug.ts:13-15`）。

`announcedAddress` 只被 `createWebRtcServer` 消费 —— 它成为服务端下发的每一个 ICE
candidate 中的 IP。`VoiceRuntime.getListenInfo()` 会再次暴露它
（`apps/server/src/runtimes/voice.ts:1082-1087`）。

---

## 2. 语音频道生命周期

所有语音过程（procedure）都注册在 `apps/server/src/routers/voice/index.ts:29-54`。每个 route
都委托给 `apps/server/src/runtimes/voice.ts` 中的 `VoiceRuntime`。

| 步骤 | tRPC route | 服务端 handler | Runtime 方法 |
|---|---|---|---|
| join | `voice.join` | `apps/server/src/routers/voice/join.ts:24-118` | `addUser`（`voice.ts:402-420`） |
| 创建发送传输通道 | `voice.createProducerTransport` | `routers/voice/create-producer-transport.ts:5-15` | `createProducerTransport`（`voice.ts:575-600`） |
| 创建接收传输通道 | `voice.createConsumerTransport` | `routers/voice/create-consumer-transport.ts:5-15` | `createConsumerTransport`（`voice.ts:534-561`） |
| 连接发送传输通道 | `voice.connectProducerTransport` | `connect-producer-transport.ts:6-23` | `transport.connect` |
| 连接接收传输通道 | `voice.connectConsumerTransport` | `connect-consumer-transport.ts:6-23` | `transport.connect` |
| 发布（publish） | `voice.produce` | `produce.ts:55-88` | `addProducer`（`voice.ts:632`） |
| 订阅（subscribe） | `voice.consume` | `consume.ts:20-81` | `addConsumer`（`voice.ts:748`） |
| 列出对端 | `voice.getProducers` | `get-producers.ts:4-8` | `getRemoteIds`（`voice.ts:1050-1068`） |
| 停止单条轨道 | `voice.closeProducer` | `close-producer.ts:8-55` | `removeProducer`（`voice.ts:686-721`） |
| 离开 | `voice.leave` | `leave.ts:11-53` | `removeUser` → `cleanupUserResources`（`voice.ts:422-465`） |

**join**：检查 `Permission.JOIN_VOICE_CHANNELS` 与频道的 `JOIN` 权限
（`join.ts:39,44`），拒绝非语音频道和 DM 频道（`:63-71`），拒绝重复加入
（`:73-80`），随后调用 `runtime.addUser`（`:98`）并返回 `router.rtpCapabilities`（`:113-117`）。

**传输通道（Transports）**：两个传输通道共用一个工厂函数 `createTransport`（`voice.ts:507-533`），
它调用 `router.createWebRtcTransport({ webRtcServer, enableUdp: true, enableTcp: true,
preferUdp: true, preferTcp: false, initialAvailableOutgoingBitrate: Math.min(10_000_000, maxBitrate) })`，
然后把两个方向都钳制到 `config.webRtc.maxBitrate`（`:202-203`）。返回的参数为
`{id, iceParameters, iceCandidates, dtlsParameters}`（`:205-210`）。

**connect**：客户端从 mediasoup-client 收到 `connect` 事件，并将 `dtlsParameters` 往返发往对应的
服务端 route（`apps/client/src/components/voice-provider/hooks/use-transports.ts:92-110`
为发送侧，`:207-225` 为接收侧）。服务端调用 `transport.connect`（`connect-producer-transport.ts:22`）。

**produce**：服务端按类别（kind）校验权限（`produce.ts:16-33`：audio→`SPEAK`，
video→`WEBCAM`+`ENABLE_WEBCAM`，screen→`SHARE_SCREEN`），随后 `producerTransport.produce`
（`produce.ts:73-77`）和 `runtime.addProducer`（`:79`），然后向整个频道发布 `VOICE_NEW_PRODUCER`
（`:81-85`）。

**consume**：`runtime.getProducer(kind, remoteId)`（`consume.ts:23`），`router.canConsume` 守卫
（`:38-46`），随后 `consumerTransport.consume({producerId, rtpCapabilities, paused:false})`（`:48-52`）
和 `runtime.addConsumer`（`:54`）。一个 `producerclose` 监听器会发布 `VOICE_PRODUCER_CLOSED`
（`:56-68`）。

**closeProducer / leave**：关闭一条轨道会关闭对应 producer 并通知频道
（`close-producer.ts:44-54`）。离开会移除该用户，并拆除两个传输通道、全部四种
producer 类别、该用户自己的 consumers，以及**其他每个用户针对该用户**的 consumers
（`voice.ts:433-465`）。非优雅的 WebSocket 关闭同样会调用 `removeUser`
（`apps/server/src/utils/wss.ts:223-232`）。

---

## 3. 一条从 A 到 B 的流

1. **采集（Capture，A）** — 客户端中的 `getUserMedia`/`getDisplayMedia`
   （麦克风见 `apps/client/src/components/voice-provider/index.tsx:519-520`，摄像头见 `:710-711`，
   屏幕见 `:905-907`）。
2. **发布（Produce，A）** — `producerTransport.current.produce({track, codecOptions, appData})`
   （音频见 `index.tsx:628-638`；视频见 `:759-761`；屏幕音频见 `:1057-1068`）。mediasoup-client
   触发其 `produce` 事件，进而调用服务端 route
   （`use-transports.ts:136-186` → `trpc.voice.produce.mutate`，`:153-158`）。
3. **Router（服务端）** — producer 被存储在 runtime 上（`voice.ts:632-684`）。不做任何转码或混流：
   mediasoup 直接转发 RTP。
4. **通知（服务端 → 频道）** — `VOICE_NEW_PRODUCER` 只发布到该频道
   （`produce.ts:81-85`；订阅按频道作用域，`events.ts:65-76`）。
5. **消费（Consume，B）** — B 收到该事件，调用 `consume(remoteId, kind, deviceRtpCapabilities)`
   （`apps/client/src/components/voice-provider/hooks/use-voice-events.ts:63-104`），后者调用
   `trpc.voice.consume.mutate`，随后 `consumerTransport.consume(...)`
   （`use-transports.ts:302-338`），把轨道挂到一个新的 `MediaStream` 上（`:410-420`）并交给
   remote-streams hook。
6. **已存在的 producers** — 加入时 B 不必等待事件；`consumeExistingProducers` 调用
   `voice.getProducers` 并消费每一个远端 id（`use-transports.ts:438-491`）。

**为什么是转发而非混流（routed, not mixed）[v]**：服务端为每个用户维护 producer map，以及一个以
`${remoteId}-${kind}` 为键的 consumer map（`voice.ts:144-151`、`:213-219`、`:748-749`）。
`runtimes/voice.ts` 中任何地方都没有混音器、没有转码器、没有服务端合成器。每个 consumer 都是一条独立的
server→receiver RTP 流。

**带宽模型**：出口带宽大致为 `sum(producer bitrate) × (receivers − 1)`。当 N 个人都在发送音频
（Opus 上限约 128 kbps，`voice.ts:93`）且每人都接收 N−1 条流时，仅语音一项服务端上行就约
`≈ (N−1)² × 128 kbps`。视频/屏幕会让它成倍放大。`webRtc.maxBitrate`
（`config.ts:67`，默认 `30_000_000`，`:127`）是在其之上的每传输通道钳制（`voice.ts:199-203`），
而非全局调度器。这种二次方出口压力正是 simulcast（§4）与 P2P（§7）的共同动因。

---

## 4. 编解码器与参数界面

### Router 编解码器（codecs）（`apps/server/src/runtimes/voice.ts:33-97`）

- Opus（`:82-95`）：`clockRate: 48000`、`channels: 2`，参数 `useinbandfec=1`、`usedtx=1`、
  `stereo=1`、`sprop-stereo=1`、`maxplaybackrate=48000`、`maxaveragebitrate=128000`。
- 视频：`VP9` profile-id 0（`:35-43`）、`VP8`（`:44-51`）、`H264` 42e01f 与 640032（`:52-73`）、
  `AV1`（`:74-81`）。它们都带有 `x-google-start-bitrate: 2000`（kbps）；router 并**不**设置
  `x-google-max-bitrate`。

### 客户端的 Opus 设置（producer 的 `codecOptions`）

- 麦克风（`index.tsx:630-636`）：`opusStereo: false`、`opusFec: true`、`opusDtx: false`、
  `opusMaxPlaybackRate: 48000`、`opusMaxAverageBitrate: 128000`。
- 屏幕共享音频（`index.tsx:1060-1065`）：`opusStereo: true`、`opusFec: true`、`opusDtx: false`，
  速率/上限同上。

注意立体声的不对称：router 通告立体声，但麦克风 producer 将其关闭。DTX 在 router 处通告、
在 producer 处关闭，因此麦克风实际生效设置为 **DTX 关闭**。

### 屏幕共享

- 采集约束（`index.tsx:878-899`）：分辨率/帧率/光标来自
  `devices.screenResolution/screenFramerate/screenCursor`；音频 `channelCount: 2`、`sampleRate: 48000`。
- 默认值（`apps/client/src/components/devices-provider/index.tsx:44-48`）：`simulcastEnabled: true`、
  `screenResolution: '720p'`、`screenFramerate: 30`、`screenCodec: AUTO`、`screenBitrate: 6000`。
- `DEFAULT_BITRATE = 6000` kbps（`packages/shared/src/statics/index.ts:29`）；当没有按设备设置的
  码率时作为回退值使用（`index.tsx:947`）。
- 编解码器选项（`index.tsx:960-972`）：`videoGoogleStartBitrate: min(2000, max)`、
  `videoGoogleMaxBitrate: max`、`videoGoogleMinBitrate: min(200, max)`。

### Simulcast

它由服务端设置与客户端设置**两者**共同门控：`simulcastEnabled = server.webRtcSimulcastEnabled
&& devices.simulcastEnabled`（`index.tsx:210-211`）。服务端默认**关闭**
（`apps/server/src/db/seed.ts:70`；schema 默认 `false`，`apps/server/src/db/schema.ts:83-88`），
尽管客户端默认开启。该设置与 `webRtcMaxBitrate` 一同对外公开
（`apps/server/src/db/queries/server.ts:52-53`）。

启用时，仅使用 **VP8**（`getSimulcastCodec`，`helpers.ts:207-212`），共三层：

- 摄像头编码层（encodings）（`helpers.ts:122-149`，常量见 `statics.ts:1-28`）：low（≤150 kbps，24 fps，
  ×4 降采样）、mid（≤500 kbps，30 fps，×2）、high（源分辨率，调用方给定上限）。摄像头上限为
  `SIMULCAST_WEBCAM_MAX_BITRATE = 900_000`（`statics.ts:2`）。
- 屏幕编码层（`helpers.ts:151-178`）：low（≤1.5 Mbps，30 fps，×4）、mid（≤4 Mbps，60 fps，×2）、
  high（源分辨率，调用方给定上限）—— 屏幕需要高得多的码率，否则浏览器会把这些层降采样。
- 层标签 `Low/Medium/High` 作为 `qualityLayers` appData 附加（`helpers.ts:180-190`），
  并在服务端按编码层数量进行校验（`voice.ts:221-290`）。

非 simulcast 的屏幕共享遵循 `devices.screenCodec`（`index.tsx:929-945`）。如果 simulcast 的
produce 抛错，摄像头/屏幕的 produce 会回退到非 simulcast 的 producer
（`index.tsx:762-773`、`:997-1009`）。

consumers 可以选择空间层；`voice.setConsumerQuality` 由
`set-consumer-quality.ts` 处理，并在 consume 之后应用已存储的质量（`use-transports.ts:393-408`）。

---

## 5. 信令通道

控制面是 tRPC，客户端**只**使用 WebSocket 链路：

- `apps/client/src/lib/trpc.ts:45` — `protocol = https ? 'wss' : 'ws'`。
- `:47-48` — `createWSClient({ url: \`${protocol}://${host}\` })`；`:100-102` `wsLink`。
- 连接参数携带会话令牌（`:88-92`）。

在服务端：

- `apps/server/src/utils/create-servers.ts:4-8` — 先 `createHttpServer()`，后 `createWsServer(httpServer)`。
- `apps/server/src/http/index.ts:104-106` — 一个 `http.createServer`；`:244` `server.listen(port)`。
- `apps/server/src/utils/wss.ts:257` — `new WebSocketServer({ server })` 把 WS 服务端挂到
  **同一个** HTTP 服务端/端口上。`applyWSSHandler` 挂载 tRPC router（`:283-292`）并带 keepalive。
- 默认端口 `4991`（`apps/server/src/config.ts:101`）。

语音事件通过 tRPC 订阅（subscriptions）搭载在这同一个 socket 上：

- `apps/server/src/routers/voice/events.ts:63-89` — `onNewProducer` / `onProducerClosed` 是
  **按频道作用域**的（`subscribeForChannel`）；`:12-42` 的广播事件（`onJoin`、`onLeave`、
  `onUpdateState`、`onReaction`、`onMoved`）为全局/按用户作用域。
- `apps/server/src/utils/pubsub.ts:137-322` — 进程内基于 `EventEmitter` 的 pub/sub，支持
  全局 / 按用户 / 按频道的扇出。
- 客户端订阅：`apps/client/src/components/voice-provider/hooks/use-voice-events.ts:63-189`。

**边界**：HTTP + WS 都在 `config.server.port` 上走 TCP。媒体是 `webRtc.port` 上的 WebRTC
（优先 UDP，启用 TCP 回退）。因此即便客户端的 WebSocket 健康，媒体仍可能独立失败
—— 这正是 §6 与 §8 的要害。

---

## 6. 线上部署拓扑与 ICE 约束

FRP 后面的自托管实例的目标拓扑（`unknown`：本仓库中不存在 FRP 配置；这里描述的是代码所假定的形态）：

```
                    +-------------------------------+
 browser  ----TCP--> | FRP TCP tunnel -> :4991       |  HTTP + WS (tRPC) + static assets
   A      ----UDP--> | FRP UDP tunnel -> :40000      |  WebRTC media (RTP/RTCP/DTLS)
                    +-------------------------------+
```

代码施加的约束：

1. **媒体端口必须与隧道的公网 UDP 端口一致。** mediasoup 使用 `WebRtcServer` 的 `listenInfo.port`
   通告 ICE candidates，而该端口正是 `config.webRtc.port`
   （`apps/server/src/utils/mediasoup.ts:17,54-55`）。此配置中不存在单独的“通告端口
   （announced port）”字段。因此若 FRP 把公网 UDP `P` 映射到内部 `40000` 且 `P != 40000`，
   candidates 将通告 `40000`，客户端会把媒体发往错误的公网端口。**UDP 隧道必须暴露与其转发的
   内部端口相同的端口号（`40000`）。**
2. **`announcedAddress` 必须能被对端访问到。** 在生产环境中，若
   `webRtc.announcedAddress` 为空，服务端会自动探测自身公网 IP
   （`network.ts:58-78`）。在 FRP 后面，这种探测往往返回 FRP 主机的 IP 或私有/
   CGNAT 地址，而非客户端可达的端点。请将 `webRtc.announcedAddress` 显式设置为
   UDP 隧道可公网访问的 IP/主机。
3. **任何地方都没有 STUN/TURN。** 仓库中未配置也未曾引用任何 STUN/TURN 服务端
   （grep `stun:`/`turn:`/`iceServers` 无任何结果）。ICE 完全依赖服务端自身的
   `{announcedAddress, port}` udp+tcp candidates（`mediasoup.ts:52-57`）。mediasoup 在该单一地址上
   作为 ICE-lite 端点运行；若对端 NAT 阻断它，没有回退中继。
4. **TCP 回退也位于 `webRtc.port` 上。** `enableTcp: true`（`voice.ts:196`）意味着若你想要
   回退，同一端口也必须能通过 TCP 访问，否则 UDP 被阻断的客户端会失败。

客户端中已有的调试手段：传输统计会暴露已成功的 `candidate-pair` 和 RTT
（`apps/client/src/components/voice-provider/hooks/use-transport-stats.ts:115-120`、`:75-80`），
此外还有 voice-debug 缓冲区以及 `window.sharkordDebug`
（`apps/client/src/helpers/voice-debug.ts`）。

---

## 7. P2P 切入点分析

**mediasoup 支持 P2P 吗？** 不支持。mediasoup 仅支持 SFU；它没有客户端到客户端的媒体模式，且
`mediasoup-client` 只讲 mediasoup 传输协议（发送/接收传输通道绑定到服务端的 `WebRtcTransport`）。
代码库中唯一一处 `createDirectTransport()`（`apps/server/src/plugins/actions/consume-voice-producer.ts:33`）
是一个**服务端本地、非 WebRTC** 的管道，供插件读取 RTP —— 它不是对等路径。因此，1v1 直连媒体模式
必须是一条**基于 `RTCPeerConnection` 构建的新 WebRTC 路径**，与 SFU 路径并列添加，而不是在现有路径上
做配置。

具体来说，要落地“1v1 直连媒体”，需要触及以下位置：

### 7.1 服务端信令（新增）

- 在 `apps/server/src/routers/voice/` 下新增一个 route 模块（参照范式：
  `create-producer-transport.ts:5-15`），并在 `apps/server/src/routers/voice/index.ts:29-54` 中注册它。
  所需的动作（verbs）：会话打开/关闭、SDP offer/answer 中继、ICE candidate 中继。
- 向 `ServerEvents` 以及 pub/sub 的 `Events` map 新增事件类型
  （`apps/server/src/utils/pubsub.ts:65-111`）；现有的按用户扇出
  （`publishFor`/`subscribeFor`，`pubsub.ts:161-181`、`:205-252`）正是向特定对端中继所需的原语。
- 仅当把直连通话建模为频道成员时，才复用现有的会话门控 `getCurrentVoiceRuntime`
  （`apps/server/src/helpers/get-current-voice-runtime.ts:6-22`）。对于 DM/好友通话，请注意语音 DM
  目前在 runtime 创建阶段被跳过（`apps/server/src/runtimes/index.ts:17`）—— 那正是引入
  非频道房间（room）的自然位置。

### 7.2 权限

- `join.ts:39,44` 与 `produce.ts:16-33` 已对加入和按类别发布做门控。新的信令 route
  必须重新检查同样的权限，并额外断言**两个对端都被授权进入同一房间** —— 否则该中继会变成
  SSRF/骚扰攻击面。`KIND_PERMISSIONS`（`produce.ts:16-33`）是应当对照的表。

### 7.3 服务端媒体层 / 抽象

- 如今 runtime *无条件地*持有 transports（`voice.ts:140-151`，`createTransport`
  `:507-533`）。直连通话**完全不应**创建 `WebRtcTransport`；服务端只中继 SDP/ICE。
  应在 runtime 上引入一个小的 **`MediaSession` 抽象**：
  - `ServerTransport`（现有的 mediasoup 路径）对比 `DirectTransport` 风格的**中继**
    （relay）（没有任何 mediasoup transport；服务端在两个对等端之间转发不透明的 SDP/ICE）。
  - 请**不要**把它命名为 `DirectTransport`，以免与 mediasoup 自身的
    `router.createDirectTransport()` 语义（`consume-voice-producer.ts:33`）冲突 —— 把新增的这一个
    命名为 `PeerRelaySession` 或类似名字。
- 模式选择应归属于 runtime/频道（sfu vs direct vs auto），并对外暴露给客户端。

### 7.4 客户端媒体层（新增）

- `use-transports.ts` 完全基于 mediasoup-client（`Device`、`createSendTransport`、
  `createRecvTransport`、`consume`、`produce` —— `use-transports.ts:77-436`）。直连模式需要一个
  使用 `RTCPeerConnection` 的并列管理器：添加轨道、创建 offer、收集 ICE、应用远端 answer、
  打洞（hole-punch），然后复用现有的 `addRemoteUserStream`
  （`use-transports.ts:410-421`），使 UI 层无需改动。
- 初始化序列（`index.tsx:1158-1225`）必须分支：SFU 模式运行 `Device.load` →
  transports → `consumeExistingProducers` → `startMicStream`；直连模式则改为运行 peer connection
  建立流程。`ConnectionStatus` 枚举（`index.tsx:104-109`）已经适用。

### 7.5 ICE 协商

- SFU 模式从服务端获取 ICE（`createTransport`，`voice.ts:205-210`）。直连模式从浏览器的
  `RTCPeerConnection` 获取 ICE，并且必须**经由上文新增的信令 route 中继它**。
- 为直连模式提供 STUN/TURN 配置 —— 目前完全没有（§6.3）。没有 TURN 中继，相当大比例的
  NAT 组合将打洞失败；这是优先发布 P2P 的主要风险。

### 7.6 建议的第一版范围（first cut）

把 P2P 范围限定为**1v1、音频优先、DM/私密通话**，频道仍走 SFU 路径不作改动。
`runtimes/index.ts:17` 处的 DM 跳过逻辑与按用户的 pub/sub 已经为此准备好了形态，而音频
不需要任何 simulcast/层机制（§4）。一旦 ICE 成功率明确，视频/屏幕即可跟进。

---

## 8. 当前已知问题 —— FRP UDP 中继实例

**观察到的现象 [v, report]**：在一个经 FRP UDP 中继访问的真实自托管实例上，服务端的
`voice.join → produce` 链路无报错地完成，然而客户端却显示
**\"Failed to initialize voice connection\"**。

该字符串来自何处 [v]：

- `apps/client/src/i18n/locales/en/common.json:51` — `\"failedInitVoiceConnection\": \"Failed to initialize voice connection\"`。
- `apps/client/src/hooks/use-select-channel.ts:45-51` — 它**仅在**
  `init(...)` reject 之后才弹出 toast，并立即调用 `leaveVoice({ reason: 'init_failed' })`。

这意味着 [v]：失败严格发生在 `init()` 内部（`index.tsx:1158-1225`），它在 `:1212` 重新抛出任何被
捕获的错误。真正可能抛错的步骤是 `device.load`
（`:1178`）、`consumeExistingProducers` 内部的某处（`:1198`）或 `startMicStream`（`:1199`）。
关键在于，**创建传输通道会吞掉自身的错误**：`createProducerTransport` 和
`createConsumerTransport` 只记录日志后继续（`use-transports.ts:187-189`、`:259-261`），因此单个
传输通道失败本身并不会导致 `init` reject —— 它只是让 ref 保持为 `undefined`，之后
`startMicStream` 会抛出 `'Producer transport is not available'`（`index.tsx:624-626`），而
`consume()` 会静默跳过（`use-transports.ts:270-276`）。

### 已排除的项 [v]

- 服务端启动/worker：开发日志显示 `WebRtcServer created on 127.0.0.1:40000 (dev mode)`
  （`mediasoup.ts:74`），因此 worker 与 WebRtcServer 都成功启动了。
- 加入的鉴权/权限：报告中 `join` 已有返回；`join.ts:39,44` 通过。
- Producer 发布已到达服务端：`voice.produce` 有返回（`produce.ts:73-87`），因此至少就那条
  传输通道而言，发送传输通道的 DTLS 连接成功了。

### 尚存的嫌疑项 [speculative — not verified]（推测 —— 未验证）

1. **FRP 后面的 `announcedAddress` 错误/为空。** 生产环境的 candidates 使用
   `config.webRtc.announcedAddress || SERVER_PUBLIC_IP`（`mediasoup.ts:50`）。若未设置，自动探测
   （`network.ts:58-78`）很可能返回对端不可达的地址，于是即使发送传输通道成功，**接收**传输通道
   也永远无法完成。最可能的元凶。
2. **UDP 端口不匹配。** FRP 暴露的公网 UDP 端口与 `40000` 不同；mediasoup 通告的是监听端口
   （`mediasoup.ts:17,54-55`），因此发往该通告端口的媒体被丢弃。（§6.1）
3. **接收侧 DTLS 始终无法建立**，原因见 (1)/(2)；随后 `init` 在
   `consumeExistingProducers`/监控处失败（`index.tsx:1198-1201`）。
4. **`device.load` 的 RTP 能力（capability）不匹配**（`index.tsx:1176-1192`）—— 不太可能与 FRP 相关，
   但从客户端调试日志确认的成本很低。

### 如何确认

打开客户端的 voice debug 缓冲区（`apps/client/src/helpers/voice-debug.ts`）和
`printVoiceStats`（`use-transport-stats.ts:115-120` 会报告已成功的 `candidate-pair`），然后
检查：(a) `init` 中究竟哪一步抛错，(b) 浏览器收到的 ICE candidate `address:port`，(c) 它是否与
FRP 的公网 UDP 端点一致。显式设置 `webRtc.announcedAddress`，并确保 UDP 隧道的公网端口等于
`40000`；重新测试。此处未复现的任何内容一律保持为 `unknown`。

---

## 附录 —— 文件速查表

| 关注点 | 文件 |
|---|---|
| mediasoup worker + WebRtcServer | `apps/server/src/utils/mediasoup.ts` |
| Runtime（routers/transports/producers/consumers） | `apps/server/src/runtimes/voice.ts` |
| 语音 tRPC routes | `apps/server/src/routers/voice/*.ts` |
| 信令传输（HTTP+WS） | `apps/server/src/utils/wss.ts`、`apps/server/src/http/index.ts` |
| Pub/sub 事件 | `apps/server/src/utils/pubsub.ts` |
| 配置 + 公网 IP 解析 | `apps/server/src/config.ts`、`apps/server/src/helpers/network.ts` |
| 客户端传输通道（mediasoup） | `apps/client/src/components/voice-provider/hooks/use-transports.ts` |
| 客户端采集/发布/初始化 | `apps/client/src/components/voice-provider/index.tsx` |
| 客户端编码层/simulcast | `apps/client/src/components/voice-provider/helpers.ts`、`statics.ts` |
| 客户端加入入口 + 失败 toast | `apps/client/src/hooks/use-select-channel.ts`、`features/server/voice/actions.ts` |
| tRPC WS 客户端 | `apps/client/src/lib/trpc.ts` |
