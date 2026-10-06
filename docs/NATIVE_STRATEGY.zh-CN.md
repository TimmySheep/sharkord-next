# Sharkord Next — 原生客户端策略

> 本文是 [`NATIVE_STRATEGY.md`](NATIVE_STRATEGY.md) 的中文翻译。英文版为权威版本，如有歧义以英文版为准。

为第一批原生目标平台（iPhone + iPad、macOS、Windows）以及那个本应避免它们把同一套业务逻辑重复实现三遍的共享核心而编写的设计文档。

| 字段 | 值 |
| --- | --- |
| 仓库 | `TimmySheep/sharkord-next`（`Sharkord/sharkord` 的公开社区分支） |
| 审阅版本 | 分支 `development` 上的 `c611bb4`（2026-10-06） |
| 范围内的原生项目（建议） | `apps/apple-mobile`、`apps/macos`、`apps/windows` |
| 这些目录的状态 | **尚不存在** —— 本文档仅对它们进行描述 |
| 文档日期 | 2026-10-06 |

**证据图例。** 每条论断都带有标记：
**[V]** = 已于上述日期针对本仓库或厂商一手资料核实（文件路径与计数均可复现）。**[R]** = 建议或判断，而非关于系统的既有事实。

下文的数字来自在 `c611bb4` 检出上执行的 `wc -l`/`grep`/`bun install` 探测。

---

## 1. 证据基础：今天实际存在什么

### 1.1 工作区清单 **[V]**

| 工作区 | 技术栈 | 受跟踪的 LOC | 职责 |
| --- | --- | --- | --- |
| `apps/client` | React 19 + Vite + Redux Toolkit + Tailwind 4 | 52,759 | Web 客户端（参考客户端） |
| `apps/server` | Bun + tRPC v11 + Drizzle/SQLite + mediasoup | 97,546（不含 `__tests__`） | 服务器、SFU、HTTP |
| `packages/shared` | TypeScript 类型/枚举/helper | 2,438 非测试 + 2,261 测试 | 横切 TS |
| `packages/ui` | 仅含展示型 React 组件 | — | 无应用逻辑 |
| `packages/plugin-sdk` | 插件 API 接口面（`src/actions.ts`、`client.ts`、`index.ts`） | — | 插件 |

根 `package.json` 声明了 `workspaces: ["apps/*", "packages/*"]` **[V]**。

### 1.2 逐文件审视 `packages/shared` —— 候选核心的种子 **[V]**

这里给出的是「`packages/shared` 中有多少可以充当跨平台核心的种子」这个问题的诚实答案：它能充当一份*规范*的种子，而不是一个*库*。见 §1.4。

| 文件 | LOC | 内容 | 可否原生化使用？ |
| --- | --- | --- | --- |
| `src/types.ts` | 225 | `ChannelType`、`StreamKind`、`UserStatus`、`TMessageMetadata`、`TPublicServerSettings`、`TMessagesCursor` + `zMessagesCursor`、hex/invite/emoji 正则 | 结构可以；`zMessagesCursor` 是 zod |
| `src/events.ts` | 61 | `ServerEvents` 枚举（39 个成员）、`TNewMessage` | 可以 —— 纯枚举 |
| `src/statics/permissions.ts` | 45 | `Permission`（24）、`ChannelPermission`（6）、`DEFAULT_ROLE_PERMISSIONS` | 可以 —— 纯枚举 |
| `src/statics/storage.ts` | 47 | 配额/大小常量、`StorageOverflowAction` | 可以 —— 纯常量 |
| `src/statics/index.ts` | 29 | `DisconnectCode`（1006/40000/40001/40002）、各类限制值、`DEFAULT_BITRATE`、`OWNER_ROLE_ID` | 可以 —— 纯常量 |
| `src/statics/locales.ts` | 18 | `SUPPORTED_LOCALES`（8 种）、`zLocale` | 可以（校验器用 zod） |
| `src/statics/upload.ts` | 6 | `UploadHeaders`（`x-file-name`、`x-file-type`、`x-token`） | 可以 —— 上传所必需 |
| `src/statics/metrics.ts` | 13 | `TDiskMetrics`、`TPluginStorageUsage` | 可以 —— 仅结构 |
| `src/voice.ts` | 58 | `TVoiceUserState`、`TVoiceMap`、`TTransportParams`、`TVoiceProducerInfo`、`TChannelState` | 结构可以，但它 import 了 `mediasoup/types` |
| `src/tables.ts` | 157 | 通过 drizzle `InferSelectModel` 得到的数据库行类型；**import 了 `apps/server/src/db/schema`** | 不可以 —— 与服务器/数据库耦合 |
| `src/logs.ts` | 237 | `ActivityLogType` 枚举（很大） | 枚举可以；类型依赖 `tables.ts` |
| `src/helpers/*` | 522 | `message-sanitizer`、`strip-zalgo`、`linkify-html`、`extract-urls`、`command-parser`、`prepare-message-html`、`has-mention`、`sha256`、`trpc-errors`、…… | 大多为纯 JS/正则 —— 可作为算法参考移植 |
| `src/plugins/*` | ~880 | 插件 manifest/能力/钩子/契约/命令/组件 | 契约类型可移植；`client-sdk.ts` / `components.ts` 引用了 `window`/React |
| `src/trpc.ts` | 1 | `export type { AppRouter } from '../../../apps/server/src/routers'` | 不可以 —— TS 类型再导出 |

**可直接作为规范移植的约为 2,438 行非测试代码中的 1,200 行（约 49%）** **[R，方法见上表]**：所有枚举、常量、DTO 结构与正则，再加上纯 helper。其余部分则与 Web DOM、服务器数据库 schema 或 tRPC/mediasoup 的 TS 类型相耦合。

### 1.3 协议接口面 —— 契约的真实规模 **[V]**

| 指标 | 数量 |
| --- | --- |
| tRPC query/mutation 过程 | **91** |
| tRPC WebSocket 订阅 | **43** |
| 带 zod `.input()` schema 的过程 | **76** |
| 非 tRPC 的 HTTP 端点 | 13 |
| HEAD 上的 SQLite 迁移 | 35 |

各 router 的过程/订阅数 **[V]**：`voice` 14/10 · `plugins` 15/6 · `users` 12/5 · `messages` 11/5 · `channels` 9/6 · `others` 9/1 · `categories` 5/3 · `roles` 5/3 · `emojis` 4/3 · `invites` 3/0 · `dms` 2/1 · `files` 2/0。

非 tRPC 的 HTTP **[V]**（`apps/server/src/http/index.ts`）：`GET /healthz`、`/info`、`/manifest.json`、`/oidc/login`、`/oidc/callback`，前缀 `/public/*`、`/plugin-components/*`、`/plugin-bundle/*`；`POST /upload`、`/login`、`/oidc/exchange`、`/oidc/backchannel-logout`。

| 流程步骤 | 契约 **[V]** |
| --- | --- |
| 登录 | `POST /login` `{identity, password, invite?}` → `{success, token}`（JWT，7 天有效期）—— `http/login.ts` |
| WS 连接 | `connectionParams = {token}`；socket 以*用户*身份完成身份认证，但**尚未加入** —— `lib/trpc.ts`、`utils/wss.ts` |
| 握手 | `others.handshake.query()` → `{handshakeHash, hasPassword}` —— `routers/others/handshake.ts` |
| 加入 | `others.joinServer.query({handshakeHash, password?, locale?})` → 完整的初始状态（categories、channels、users、roles、emojis、`voiceMap`、`channelPermissions`、`readStates`、settings、插件元数据、外部推流）—— `routers/others/join.ts` |
| 实时 | 43 个订阅，每个都是 `pubsub.subscribeFor(userId, ServerEvents.X)`，例如 `onMessageRoute` —— `routers/messages/events.ts` |
| 重连 | 固定退避 `[1000, 2000, 4000, 8000, 8000]` ms，然后重新加入；重连后的 socket 以未认证状态开始 —— `features/server/actions.ts`、`lib/trpc.ts` |
| 上传 | `POST /upload`，请求头为 `x-token`、`x-file-name`，请求体 = 原始八位字节流（octet-stream）→ `TTempFile`；大小必须与 `content-length` 一致 —— `http/upload.ts` |

### 1.4 决定整个设计的两个结构性事实

**事实 A —— `packages/shared` 是一个编译期的 TypeScript 包，而不是运行时中立的核。** 它无法被 Swift 或 C# 使用，并且自身并不自洽 **[V]**：

- `src/tables.ts` import 了**服务器的** Drizzle schema（`apps/server/src/db/schema`）。
- `src/voice.ts` import 了 `mediasoup/types`。
- `src/trpc.ts` 只是对**服务器的** `AppRouter` 的类型导入。
- `src/types.ts` 和两个 helper 依赖 **zod**；`linkify-html.ts`/`extract-urls.ts` 依赖 **linkify-it**。

因此 `packages/shared` 只能作为核心的*来源*，而永远不能成为核心本身。

**事实 B —— 语音栈是 SFU（客户端↔服务器），而不是点对点。**
本仓库的客户端依赖 `mediasoup-client`，并驱动 `device.createSendTransport` / `createRecvTransport`、`voice.produce`、`voice.consume`、`voice.setConsumerQuality` **[V]**（`components/voice-provider/hooks/use-transports.ts`、`routers/voice/*`）。mediasoup 的*客户端*库是构建在 Google libwebrtc 之上的 C++ 库（`versatica/libmediasoupclient`，其 API 与 `mediasoup-client` 对应）**[V]**。**Swift、C# 或 Rust 都没有官方的 mediasoup 客户端**；Apple 支持来自第三方封装（`VLprojects/mediasoup-client-swift`、`ethand91/mediasoup-ios-client`），Android 则来自 `haiyangwu/mediasoup-client-android` **[V]**。

这意味着媒体引擎 —— 一个类 Discord 客户端中最大、最昂贵的一块 —— **在任何路线上都必须各端原生实现并做平台绑定。** 任何共享核心的选择都无法消除这项工作。

---

## 2. 共享核心：选择哪条路线

### 2.1 三条路线的定义

| 路线 | 定义 |
| --- | --- |
| **（a）Rust 核心 + FFI** | 由一个 Rust crate 持有模型/逻辑；Swift 通过 `uniffi`（官方 Swift/Kotlin 后端）消费，C# 通过社区生成器（`uniffi-bindgen-cs`）或 `csbindgen` 消费 **[V]**。 |
| **（b）各平台各自实现，仅共享文档** | 每个应用各自实现全部内容；只有一份书面协议 + JSON Schema 是共享的。 |
| **（c）以 TS/`shared` 为唯一真源 + 代码生成** | `packages/shared`（加上从 server routers 中抽出的 zod schema）保持为真源；一个生成器产出 Swift/C# 模型和一份带版本的 schema 产物。 |

### 2.2 影响对比表

| 维度 | （a）Rust 核心 | （b）仅文档 | （c）TS 源 + 代码生成 |
| --- | --- | --- | --- |
| **移动端后台语音** | 无影响 —— 这纯粹是 `AVAudioSession` / `UIBackgroundModes` 的问题 **[V]**；Rust crate 无法持有音频会话 **[R]** | 无影响 | 无影响 |
| **二进制体积** | **每个平台**额外 +约 1–3 MB 的 Rust 静态库以及额外的 FFI 垫片，且叠加在 libwebrtc（约 30–100 MB）之上 **[R]** | 代码占用最小，但逻辑重复 3 次 **[R]** | 可忽略 —— 只有生成的模型 **[R]** |
| **启动时间** | 初始化开销可忽略，但每次状态更新都会增加一个跨语言调用边界 **[R]** | 最快（无额外层） | 最快 —— 代码生成没有运行时开销 **[R]** |
| **开发速度** | 最慢：3 种语言 + 3 套构建系统 + 每次改动都要重新生成 FFI **[R]** | 单平台开发快，但每次协议变更都要手工改 3 遍 | 快：改一次 zod/TS，重新生成即可 **[R]** |
| **社区贡献门槛** | **最高** —— 贡献者必须学会 Rust + Swift + C# + `uniffi` | 单文件门槛最低，但没有一个统一的地方修 bug | **最低** —— 上游团队本来就在写 TS；贡献者可以继续用 TS 工作 **[V]** |
| **逻辑复用（既定目标）** | **最好** —— 状态同步、重连、权限、缓存只有一份实现 | 最差 | 只有模型；运行时逻辑仍需各平台重写 |
| **RTC / 媒体复用** | 无 —— 不存在 Rust 的 mediasoup 客户端 **[V]** | 无 | 无 |
| **漂移风险** | 逻辑层面低；边界层面**高**（TS 真源 vs Rust 真源） | 最高 | 中 —— 由代码生成 + 一致性测试套件强制约束 |
| **与上游的可合并性** | 差 —— 在 Bun monorepo 里放一棵 Rust 树会与 `upstream/development` 渐行渐远 | 好 | **最好** —— 不引入新语言；`packages/shared` 仍是合并点 |

### 2.3 推荐

> **现在采用路线（c），并为其设定一条明确的、向路线（a）过渡的毕业门槛。拒绝路线（b）。**

**核心推荐，一句话：** *让 `packages/shared` 成为一份 schema 优先、语言中立的协议契约，并据此生成 Swift/C# 模型 —— 在三个 Apple 目标之间共享一个真正的 SwiftPM 核心 —— 只有当协议不再剧烈变动时，才抽出 Rust「大脑」。*

在项目明确希望有一个共享核心的前提下，为什么选（c）而不是（a）：

1. **路线（a）并不能买来它看起来能买来的东西。** §1.4 事实 B：媒体引擎在任何路线上都保持原生，而音频/采集/后台模式是 Rust 无法触及的操作系统 API。因此 Rust 核心消除的是*便宜*的重复（模型、reducer、重连），而*昂贵*的重复（WebRTC + mediasoup + 音频 + 采集）依然存在。对首个版本而言，这是一笔不划算的交换。**[R]**
2. **仓库中的既有准则目前不允许这么做。** `AGENTS.md` 指出核心原则是*「不过度工程化……只加能用的最小东西……不要引入不必要的抽象或依赖」* **[V]**。在一个仍在演进的协议（35 次迁移、91 个过程、版本 `0.0.25`）面前，把一个 Rust + `uniffi` + Windows `.NET` 工具链引入 Bun monorepo，恰恰是这条原则的反面 **[V]**。今天冻结下来的 FFI 边界，是一个你每个月都要重新冻结一次的边界。**[R]**
3. **四个目标中有三个是同一种语言。** iPhone 和 iPad 是同一个项目，macOS 是第二个，两者都是 Swift —— 因此一个共享的 **SwiftPM** 核心可以完全不用 FFI，就原生地覆盖三个目标。只有 Windows（C#）分道扬镳。所以路线（c）意味着**两**套实现，而不是四套，且 Swift 那一半是一个真正的共享库，而不是一堆生成的模型。**[R]**

为什么拒绝（b）：它没有任何强制执行机制。76 个 zod schema 内联在 server routers 中，又没有机器可校验的契约，一旦某个输入结构发生变化，三个手写客户端就会悄无声息地与服务器产生分歧。**[R]**

为什么*暂时*不选（a）：它是正确的终点，但不是正确的第一步。路线（c）产出的恰恰是未来 Rust 核心无论如何都需要的东西 —— 一份正式的、带版本的、机器可校验的协议描述 —— 所以现在选择（c）并不会把 Rust 的工作丢掉；它是在你承诺长期维护之前，先把 Rust crate 的接口定义清楚。**[R]**

**向（a）过渡的毕业门槛** —— 只有以下条件全部成立时才抽出 Rust 核心 **[R]**：
1. 协议变动趋缓（例如某个版本没有任何 router 过程签名的变更）。
2. 存在一套一致性测试套件，TS 与任何原生客户端都能针对它运行。
3. Windows 在语音上与 macOS 达到对等（即 C# 客户端是真的，而不是一个占位桩）。
4. 有实际证据表明存在由运行时逻辑重复所导致的漂移 bug。

### 2.4 Rust 核心模块划分 —— 目标设计（在门槛达成时适用）**[R]**

**进入核心 crate 的部分**（与平台无关，不含 OS API，不含它自己不持有的 socket）：

| 模块 | 职责 |
| --- | --- |
| `protocol::models` | 来自 `shared/src/types.ts`、`tables.ts`（仅结构）、`events.ts`、`voice.rs` 的所有 DTO，用 serde 序列化 |
| `protocol::enums` | `ServerEvents`、`Permission`、`ChannelPermission`、`ChannelType`、`StreamKind`、`DisconnectCode`、`UploadHeaders` —— 1:1 镜像 |
| `protocol::validate` | zod 规则的移植（`MESSAGE_MAX_LENGTH`、cursor 结构、locale 枚举） |
| `transport::ws` | WS 分帧 + tRPC 风格的请求/订阅信封（§2.5 风险） |
| `auth` | token 生命周期：存储句柄 → 连接参数 → `handshake` → `joinServer` → 重连时重新加入 |
| `state` | store：归一化的 channels/users/messages/roles/voice，以及来自 `features/server/slice.ts` 的 reducer |
| `state::sync` | 订阅应用（那 43 个事件）、去重/合并顺序、detached-window 逻辑 |
| `presence`、`reconnect` | 退避状态机 `[1,2,4,8,8]s` + 重新加入 |
| `perm` | 仅用于 UX 的权限判定 —— 永远不作为安全边界 |
| `rtc::signaling` | *仅*做编排：创建 transport、连接、produce、consume、设置 consumer 质量 |
| `media::metadata` | 推流种类、质量层、外部推流元数据、以数据形式表示的 ICE 状态 |
| `cache` | 频道/消息的带索引离线缓存 |

**必须留在原生层的部分**（核心必须把这些作为抽象接口暴露出来，但自己从不调用）：

| 原生关注点 | 为什么不能放进核心 |
| --- | --- |
| 音频采集/播放/路由、设备选择、回声消除 | `AVAudioSession`（Apple）、WASAPI（Windows）—— 由 OS 持有，受权限门控 **[V]** |
| WebRTC 媒体引擎 + `mediasoup-client` 语义 | 基于 libwebrtc 的 C++ `libmediasoupclient`；不存在 Rust 绑定 **[V]** |
| 编解码器选择 / 硬件编解码 | VideoToolbox（Apple）、Media Foundation / DXVA（Windows）**[R]** |
| 屏幕采集 | ScreenCaptureKit / ReplayKit（Apple）、Windows.Graphics.Capture（Windows）**[R]** |
| 来电 UI + 唤醒 | PushKit / CallKit / LiveCommunicationKit、APNs **[V]** |
| 全局按键通话（PTT） | `CGEventTap` / 辅助功能权限（macOS）、`RegisterHotKey` + 低级钩子（Windows）**[R]** |
| 静态存储的 token | Keychain（Apple）、DPAPI（Windows）**[R]** |
| 托盘、通知、应用生命周期 / 后台模式、UI | 由平台持有 **[R]** |

**边界，明确陈述：** Rust 核心永远无法获取受平台保护的音频或采集句柄。它的媒体职责仅限于*信令与状态*；媒体本身则交给原生引擎。任何期望由核心来持有 `AVAudioSession` 或 WASAPI 的设计都是不健全的，应在评审时被否决。**[R]**

### 2.5 风险与不成立的前提

| # | 前提 / 风险 | 结论 |
| --- | --- | --- |
| 1 | 「为 peer mesh 共享 P2P 信令 / ICE」 | **前提不成立。** 本系统是 SFU；既没有 P2P mesh，也没有可共享的点对点 ICE。原生客户端只与服务器的 mediasoup router 通信。**[V]** |
| 2 | 「`packages/shared` 可以直接作为核心」 | **不成立。** 它 import 了服务器 schema、mediasoup 类型、zod 和 linkify-it；它是纯 TS 的。**[V]** |
| 3 | 「Rust 核心能消除 RTC 重复」 | **不成立。** 不存在 Rust 的 mediasoup 客户端；无论如何，C++/原生引擎的工作都是各平台各自的。**[V]** |
| 4 | tRPC WebSocket 线格式 | **真实风险。** tRPC v11 的 WS 分帧是实现细节，而非带版本的公开规范。任何非 TS 客户端（Rust 或 C#）都必须镜像它，并且可能因上游升级而损坏。缓解措施：增加一个小型的、有文档、带版本的协议端点，或增加一套在出现漂移时让 CI 失败的一致性测试框架。**[R]** |
| 5 | 客户端侧权限 | **若被误用则是真实风险。** 服务器是权威的（每条路由上都有 `ctx.needsPermission` / `ctx.needsChannelPermission`）**[V]**。原生权限代码只能用于隐藏 UI，永远不能用于拦截操作。 |
| 6 | 认证 token 的处理 | JWT 由 `POST /login` 下发，并作为 WS 连接参数发送 **[V]**。原生端必须把它存进 Keychain/DPAPI，并将其视为凭据。 |
| 7 | 签名文件 URL | 当 `storageSignedUrlsEnabled` 开启时，`/public/*` 会校验 `accessToken` + `expires` **[V]**（`http/public.ts`、`files-crypto.ts`）。原生端的图片/文件加载器必须携带这些查询参数。 |
| 8 | 插件 UI | 插件的客户端部分是在 Web 客户端内部、针对 `window.__SHARKORD_STORE__` / `window.__SHARKORD_REACT__` 运行的 React **[V]**（`plugins/client-sdk.ts`、`plugins/components.ts`）。原生端若不嵌入 Web 视图就无法承载插件 UI。**这是原生计划必须明确声明的范围缺口。** |
| 9 | iOS 后台音频 | Apple：录制会话无法从后台启动；`voip` 用于来电唤醒，而 `audio` 用于让*已经活跃*的会话保持存活，且任何来电都会抢占一个普通的 `playAndRecord` 会话 **[V]**。原生端必须围绕「用户发起、前台启动」的通话来设计。 |
| 10 | 启动/状态假设 | `joinServer` 在一次响应中返回整个世界 **[V]**；在 WS 断开与重新加入之间的空档期内遗漏的订阅会被静默丢失，除非客户端重新加入并重新拉取。 |

---

## 3. 三个原生项目

### 3.0 三者共同的决定

| 决定 | 选择 | 依据 |
| --- | --- | --- |
| 仓库位置 | `apps/apple-mobile`、`apps/macos`、`apps/windows`；共享 Swift 放在 `packages/apple-core`；生成的协议模型放在 `packages/protocol` | 与既有的 `apps/*` + `packages/*` 布局一致 **[V]** |
| `bun install` 会不会被它们卡住？ | **不会。** `apps/*` 下**没有** `package.json` 的目录会被 Bun workspaces 忽略 —— 已在 Bun 1.3.14 上用 `bun install` 探测验证 **[V]**。除非你希望它进入 workspace 依赖图，否则**不要**添加 `package.json`。 | 已探测 |
| 功能/版本门控 | 读取 `/info`（`TServerInfo.version`）和 `X-Sharkord-Version` 响应头，用 `semver` 进行比较 | **[V]** `http/info.ts`、`http/index.ts` |
| 协议来源 | 把 `apps/server/src/routers/*` 中的 76 个内联 zod schema 抽出来作为生成器的输入；产出 Swift/C# 模型 + 一份 schema 文件 | **[V]** +（c） |
| 传输层就绪 | 先于其他一切实现 `others.handshake` → `others.joinServer`：它是通往全部状态的唯一关口 | **[V]** |
| CI | Apple 用 `macos-latest` runner；WinUI 用 `windows-latest`（Windows 应用**无法**在 Mac 上构建） | **[V]** |

### 3.1 `apps/apple-mobile` —— iPhone + iPad（Swift + SwiftUI）

**如何创建。** 一个 Xcode 应用 target（`Sharkord`），设置 iOS/iPadOS 部署目标，外加若干本地 SwiftPM 包。不要把逻辑放进应用 target；应用只是一个外壳，它引入（vendors）`packages/apple-core`（与 `apps/macos` 共享）和 `packages/protocol`。

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

**分层划分。**

| 层 | 内容（Apple） |
| --- | --- |
| 网络 | WS + tRPC 信封，`handshake`/`joinServer`，重连 `[1,2,4,8,8]s`，`POST /login`，`POST /upload`，`/public` 文件 URL |
| 状态 | 镜像 `features/server/slice.ts` 的 reducer；带 detached-window 规则的消息缓存 |
| RTC | 通过 Swift 封装（例如 `mediasoup-client-swift`）使用 `libmediasoupclient`；producer/consumer transport |
| UI | SwiftUI；iPad 用 `NavigationSplitView`，iPhone 用 tab/stack |
| 平台 | `AVAudioSession`、CallKit、PushKit/APNs、ScreenCaptureKit/ReplayKit、VideoToolbox |

**第一阶段顺序（登录 → 服务器 → 频道 → 文本）。** 移动端的语音是第二阶段。

| 步骤 | 工作 | 服务器调用 |
| --- | --- | --- |
| 1 | 输入服务器 URL + 可达性检测 | `GET /info` |
| 2 | 登录界面（identity + password） | `POST /login` → 把 JWT 存进 Keychain |
| 3 | 连接 + 握手 | WS + `others.handshake` |
| 4 | 服务器密码 / 加入 | `others.joinServer` |
| 5 | 渲染树：categories → channels | 来自 join 的载荷 |
| 6 | 打开文本频道，加载历史 | `messages.getMessages`（cursor） |
| 7 | 发送消息 | `messages.sendMessage` |
| 8 | 实时更新 | 订阅 `onMessage`、`onMessageUpdate`、`onMessageDelete`、`onMessageTyping` |
| 9 | 重连 + 重新加入 | 镜像 `reconnectToServer` |
| 10 | 附件 | 先 `POST /upload`，再 `sendMessage.files` |

**所需的系统能力与 API。**

| 能力 | API | 阶段 |
| --- | --- | --- |
| 音频会话 / 路由 | `AVAudioSession`（`playAndRecord`、`voiceChat`） | 2 |
| 通话 UI + 唤醒 | CallKit / LiveCommunicationKit + PushKit + APNs | 2 |
| 后台音频 | `UIBackgroundModes: audio`（+ `voip` 用于推送唤醒） | 2 |
| 屏幕共享 | ReplayKit（iOS 上为应用内广播） | 3 |
| 视频编解码 | VideoToolbox（经由 WebRTC） | 2 |
| 凭据 | Keychain Services | 1 |
| 后台刷新 | BGTaskScheduler | 3 |

**关键风险。**

- **后台语音是移动端的头号风险 [V/R]。** Apple：音频会话无法从后台*开始*录制；`audio` 让*活跃*的会话保持存活；`voip` 用于来电唤醒；任何来电都会抢占一个普通的 `playAndRecord` 会话。因此应用必须处于前台才能发起通话，而一次持续的通话需要活跃的会话以及对中断的正确处理。要按「用户在前台发起通话，通话可在转入后台后存活」来设计 —— 而不是「常开」。
- 模拟器上没有 PushKit/CallKit → 完整的唤醒路径必须在真机上测试。
- 如果你在没有真正来电流程的情况下声明 `voip`，会面临 `uid` 式的 App Store 审核压力。
- iPad 多任务：不要假设单一的「移动端」布局；使用 size classes。

### 3.2 `apps/macos` —— Swift + SwiftUI/AppKit

**如何创建。** 一个单独的 Xcode 应用 target，它**引入同一个 `packages/apple-core`** —— 这正是路线（c）的回报：macOS 与 iOS/iPadOS 共享同一个 Swift 核心，且无需 FFI。只有在 SwiftUI 力有不逮之处（菜单栏项、全局事件监听、屏幕共享选择器）才使用 AppKit。

```
apps/macos/
  Sharkord.xcodeproj
  Sharkord/
    SharkordApp.swift                # @main
    AppKitBridge/   GlobalPTT.swift, StatusItem.swift, ScreenPicker.swift
    Info.plist + Sharkord.entitlements  # audio input; sandbox; accessibility (TCC)
# packages/apple-core is the SAME package — do not fork it
```

**分层划分。** 与 §3.1 相同 —— `apple-core` 提供网络、状态与 RTC 编排。macOS 的差异在于 UI 层（SwiftUI 窗口 + `NSStatusItem` 菜单栏常驻）和平台层（Core Audio 设备、ScreenCaptureKit、VideoToolbox、用于 PTT 的 `CGEventTap`）。

**第一阶段顺序** —— 与 §3.1 相同的十个步骤，然后**语音也在第一阶段**（macOS 是原生语音的旗舰）：加入语音 → producer/consumer transport → 麦克风 → 屏幕共享。

**所需的系统能力与 API。**

| 能力 | API | 阶段 |
| --- | --- | --- |
| 音频采集/播放 | Core Audio / `AVAudioEngine`；HAL 设备选择 | 1 |
| 屏幕采集 | ScreenCaptureKit（需要屏幕录制 TCC 权限） | 1 |
| 视频编解码 | VideoToolbox | 1 |
| 菜单栏 / 托盘 | `NSStatusItem` | 1 |
| 全局按键通话 | `CGEventTap` / `NSEvent.addGlobalMonitorForEvents` —— **需要辅助功能（Accessibility）TCC 权限** | 2 |
| 通知 | `UNUserNotificationCenter` | 1 |
| 凭据 | Keychain | 1 |

**关键风险。**

- **全局 PTT 需要辅助功能权限。** 在用户授予辅助功能/输入监控权限之前，全局按键监听会静默地什么都不做；应用必须能检测到这一失败并向用户解释。
- **Windows 服务器**：整个会话必须在重连后存活（状态层是共享的，所以这只需测试一次，就能同时惠及两个 Apple 目标）。
- 沙盒：屏幕录制 + 辅助功能是两项独立的 TCC 授权；两者都必须配置好。
- 屏幕共享必须排除自身的音频采集，以避免回声。

### 3.3 `apps/windows` —— C# + WinUI 3

**如何创建。** 在解决方案中 `dotnet new` 一个 WinUI 3 应用，然后添加类库。注意两个硬事实：**WinUI 3 / Windows App SDK 仅限 Windows，无法在 macOS 上构建** **[V]**，且**当前 Mac 上没有安装 .NET SDK** **[V]**。所以这个项目在 Windows 机器或虚拟机上开发，CI 在 `windows-latest` 上运行。

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

**分层划分。**

| 层 | 内容（Windows） |
| --- | --- |
| 网络 | `ClientWebSocket` + tRPC 信封；用 `HttpClient` 处理 `/login`、`/upload`、`/public` |
| 状态 | reducer + 缓存；**手工移植同样的规则**（路线（c）仍会在此处重复逻辑） |
| RTC | `P/Invoke` 调用用 MSVC 编译的 `libmediasoupclient`，并接到原生 libwebrtc 构建上 |
| UI | WinUI 3（Fluent）；托盘用 `TaskbarIcon`/`NotifyIcon` |
| 平台 | WASAPI、Windows.Graphics.Capture、Media Foundation、`RegisterHotKey` / 低级键盘钩子、DPAPI |

**第一阶段顺序** —— 与 §3.1 相同的十个步骤，**仅文本**；语音是第二波（见风险）。

**所需的系统能力与 API。**

| 能力 | API | 阶段 |
| --- | --- | --- |
| 音频采集/播放 | WASAPI（共享/独占模式，设备枚举） | 2 |
| 屏幕采集 | Windows.Graphics.Capture（`GraphicsCaptureItem`） | 2 |
| 编解码 | Media Foundation（H.264、Opus） | 2 |
| 系统托盘 | 通过 WinUI/Shell 集成使用 `NotifyIcon` | 1 |
| 全局 PTT | `RegisterHotKey`（按窗口生效）+ 用于全局的 `WH_KEYBOARD_LL` 钩子 | 2 |
| 手势 | 触摸设备上的 `PointerPressed`/`LongPress` | 2 |
| 凭据 | Windows DPAPI（`ProtectedData`） | 1 |

**关键风险。**

- **语音是 Windows 的头号风险。** C# 没有任何 mediasoup 客户端 **[V]**；你必须要么 P/Invoke `libmediasoupclient`（C++、MSVC 构建、依赖 libwebrtc、原生二进制体积大），要么在 C# WebRTC 栈之上重新实现 mediasoup 协议（极其昂贵）。**建议：Windows 先交付文本功能，把语音的门控放到一个单独的里程碑上。** **[R]**
- **无法从 macOS 交叉构建** —— CI/CD 必须在 Windows 上运行；本地开发需要一台 Windows 虚拟机。**[V]**
- `RegisterHotKey` 是按窗口生效的，可能被其他应用抢占；真正全局的 PTT 需要低级键盘钩子，而这可能被杀毒软件标记。
- 打包部署与非打包部署会改变文件路径和提权行为。
- 这里编写的任何状态逻辑都会重复 `apple-core` —— 这正是路线（c）所接受的代价。

### 3.4 跨平台风险排序

| 排名 | 风险 | 受影响的路线 | 缓解措施 |
| --- | --- | --- | --- |
| 1 | **C# 没有可用的语音引擎 → Windows 可能在很长一段时间内只能发布纯文本** | 所有 | 把 Windows 语音门控在独立里程碑上；尽早 P/Invoke `libmediasoupclient` 并做原型 **[V]** |
| 2 | **iOS 后台语音限制**（无法在后台启动会话；中断会抢占）**[V]** | Apple | 在前台发起通话；可接听时使用 CallKit；在真机上测试 |
| 3 | **tRPC WS 线格式不是公开规范** | （b）/（c）原生端 | 带版本的协议端点，或 CI 中的一致性测试框架 **[R]** |
| 4 | **不嵌入 Web 视图，插件 UI 就无法原生存在** **[V]** | 所有 | 在 v1 中声明插件仅限 Web；后续再规划一个 WebView 宿主 |
| 5 | macOS 的全局 PTT 需要辅助功能 TCC | macOS | 检测被拒情况，给出引导式修复 |
| 6 | Windows 构建只能在 Windows 上进行 **[V]** | Windows | CI 用 `windows-latest`；本地用虚拟机 |
| 7 | 上游演进带来的协议漂移（`0.0.25`、35 次迁移）**[V]** | 所有 | 生成模型；针对 `/info` 版本做断言；保持 `packages/shared` 为合并点 |

### 3.5 建议的首批里程碑

| 里程碑 | 交付物 | 阻塞 |
| --- | --- | --- |
| M0 | `packages/protocol` 生成器，从抽出的 zod schema 产出 Swift + C# 模型，并带一致性测试 | 一切 |
| M1 | `packages/apple-core` 的网络 + 状态 + 会话；iOS 的登录→频道→文本跑通 | Apple 各目标 |
| M2 | 复用 `apple-core` 的 macOS 应用；加入语音 | macOS |
| M3 | Windows 应用（WinUI 3）复用生成的模型；登录→频道→文本 | Windows |
| M4 | Windows 语音预研（spike）：`libmediasoupclient` P/Invoke 可行性报告 | Windows 语音 |

### 3.6 在 M0 之前需要敲定的开放问题

1. 项目是否接受在服务器上提供一个有文档、带版本的协议端点（对风险 #3 的干净修复）？还是说镜像 tRPC v11 的内部实现是可以接受的？**[R]**
2. 插件是否明确不在原生 v1 的范围内（风险 #4）？**[R]**
3. `packages/apple-core` 这个 SwiftPM 包是*两个* Apple 目标共用的核心，还是 macOS 要单独一份？建议：一个包，只有在 Voice 提出互相冲突的需求时才拆分。**[R]**
4. 哪一个 mediasoup 的 Apple 封装会成为受支持的那一个（`VLprojects/mediasoup-client-swift` vs `MediaSFU/mediasfu-mediasoup-client-apple`）？两者都是第三方的；都不是官方的。**[V]**
