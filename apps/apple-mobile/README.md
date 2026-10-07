# Sharkord iOS + Apple Watch

> **这一版有功能了。** 登录、频道、消息、表情回应、语音（开关麦、耳聋保护）、屏幕共享、
> 五种语言、灵动岛，全部走真实协议：`POST /login` + tRPC over WebSocket + mediasoup SFU。
> 没有示例数据，界面上不再有"离线示例"。
>
> **Apple Watch 侧已接入真实会话与消息**：登录、频道、消息、回复、表情回应，以及 Join →
> 按住说话 → 松手收听 → 明确 Leave 的腕上 PTT。语音由服务端桥接到现有 mediasoup 房间；
> 当前已做服务端媒体测试与 Watch/iOS 编译验证，仍待真机音频和长时间后台收听验收。
>
> **This version has working features.** Sign in, channels, messages, reactions, voice
> (mic on/off, output-off protection), screen sharing, five languages and the Dynamic
> Island all run on the real protocol: `POST /login` + tRPC over WebSocket + the mediasoup
> SFU. There is no sample data any more.
>
> **The Apple Watch side now connects to real sessions and messages:** sign-in, channels,
> messages, replies, reactions, and wrist PTT with an explicit join, hold to talk, release
> to listen, and leave lifecycle. A server bridge connects Watch audio to the existing
> mediasoup room. Server media tests and Watch/iOS builds pass; real-device audio and
> long-duration background listening still need acceptance testing.

原生 iPhone/iPad 客户端，第一版功能。设计文档见
[`docs/NATIVE_STRATEGY.md`](../../docs/NATIVE_STRATEGY.md)，目录形态按其 §3.1。

## 设计

视觉语言按 Timmy 提供的参考设计（`~/Downloads/example` 六张截图）重做，全深色：

- 纯黑背景 + 深灰实心大圆角卡片（无描边、无毛玻璃），超大左对齐粗体标题。
- 宝蓝大圆角主按钮（文字 + 右侧箭头）；通话控制为胶囊按钮（激活蓝 / 关扬声器红 / 禁用灰）+ 深红方形退出键。
- 深蓝图标徽章、绿点状态胶囊、分段胶囊控件、胶囊输入框 + 圆形发送键。
- 悬浮胶囊 Tab Bar（语音 / 频道 / 聊天 / 屏幕共享 / 设置），激活项蓝色 + 浅灰圆角高亮。
- 令牌与组件集中在 `Sharkord/DesignSystem.swift`（`SharkordTheme`），全局强制深色（`RootView`）。

## 这一版能做什么

| 功能 | 状态 |
| --- | --- |
| 登录 | `POST /login` 取 token，`others.handshake` + `others.joinServer` 拉全量状态（频道、成员、角色、未读、语音表、权限） |
| 频道与私信 | 分类、文字/语音频道、私信列表、未读角标，文字频道开屏即拉历史，支持向上翻更早消息 |
| 消息 | 发送、编辑、删除、置顶、引用回复、表情回应（长按消息）、正在输入提示、附件名列表 |
| 语音 | 真实 mediasoup 通话：join/leave、send/recv transport、opus 收发、远端参与者实时状态 |
| 开关麦 | 静音只停发轨道不拆 producer（与网页端一致），状态经 `voice.updateState` 广播 |
| **扬声器保护** | **扬声器关闭（`soundMuted`）时麦克风禁止打开**：UI 按钮禁用并给出原因，引擎层 `setMicrophoneEnabled(true)` 同样拒绝，两处同时拦 |
| 耳聋联动 | 关闭扬声器会自动关麦并记住开麦前状态，恢复时还原（与网页端一致）；同时静音所有远端音轨 |
| 屏幕共享 | ReplayKit 采集 → WebRTC 视频轨 → `kind: screen` producer，权限校验 `SHARE_SCREEN`；远端画面在语音房间内渲染 |
| 语言 | 英语、简体中文、西班牙语、法语、德语，设置内即时切换（不用重启） |
| 灵动岛 | 通话时显示频道与人数；设置页保留示例预览按钮 |
| iPad | NavigationSplitView 双栏；iPhone 悬浮胶囊 Tab Bar（语音/频道/聊天/屏幕共享/设置）+ 通话时三键控制条（其他 tab 为"回到通话"条） |

## 构建

```bash
cd apps/apple-mobile
open Sharkord.xcodeproj          # 跑 Sharkord scheme，任意 iOS 17+ 模拟器
```

命令行（模拟器无需签名）：

```bash
xcodebuild -project Sharkord.xcodeproj -scheme Sharkord \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

首次构建会自动解析两个 Swift 包：

| 包 | 来源 | 用途 |
| --- | --- | --- |
| `SharkordCore` | 本地 `apps/macos`（`XCLocalSwiftPackageReference`） | 会话层：tRPC WebSocket、全部 procedure/订阅、数据模型。与 macOS 客户端共用一套，避免两份实现漂移 |
| `Mediasoup` | [VLprojects/mediasoup-client-swift](https://github.com/VLprojects/mediasoup-client-swift) 0.13.2（SPM 二进制包） | libmediasoupclient 的 Swift 封装 + WebRTC，媒体层 |

> `SharkordCore` 暂时从 `apps/macos` 引用（其 `Package.swift` 注释里写明了"later, the iOS target"）。
> 等 macOS 侧稳定后应抽到 `packages/apple-core`，届时只改这一处引用。

## 代码结构

```
Sharkord/
  SharkordApp.swift / RootView.swift    入口与路由
  AppModel.swift                        编排：会话 + 语音引擎 + 语言 + 灵动岛
  Models.swift                          视图本地模型
  DesignSystem.swift                    设计令牌（SharkordTheme）与通用组件（卡片/按钮/胶囊/徽章/头像）
  Onboarding/ConnectView.swift          真实登录
  Workspace/                            频道列表、聊天（分段：频道/私信）、语音房间、屏幕共享、成员、设置
  Voice/
    VoiceEngine.swift                   mediasoup 设备/传输/收发 + 麦克风保护规则
    RemoteVideoView.swift               远端视频/屏幕画面渲染
    RTPCodec.swift                      JSONValue <-> mediasoup JSON 字符串
  i18n/
    L10n.swift                          运行时切换语言
    Resources/<lang>.lproj/Localizable.strings   en / zh-Hans / es / fr / de
  Activities/                           灵动岛（app 侧）
SharkordLiveActivity/                   灵动岛（widget 扩展）
SharkordWatch/                          Apple Watch（真实会话、消息与 PTT，target SharkordWatch）
  SharkordWatchApp.swift / WatchRootView.swift   入口与路由（连接 → 频道 → 对讲房间）
  WatchSessionModel.swift               共享 SharkordCore 会话 + Watch PTT 控制器
  WatchRadioSession.swift               PTT 状态机、音频引擎与已认证 tRPC relay
  WatchConnectView/WatchChannelListView/WatchMessagesView/WatchRoomView.swift   Watch 界面
  WatchTheme.swift                      Watch 设计令牌
  Info.plist                            WKApplication + UIBackgroundModes: audio + 麦克风用途
```

## 语音协议顺序（与 web 端一致）

1. 同一条 WebSocket 上完成全部信令（`?connectionParams=1` + `{"method":"connectionParams","data":{"token":…}}`）
2. `voice.join` → `routerRtpCapabilities` → `Device.load`
3. `voice.createProducerTransport` / `createConsumerTransport` → 建 send/recv transport，`onConnect` 时回 `connectXxxTransport(dtlsParameters)`
4. `voice.getProducers` + `voice.onNewProducer` → `voice.consume` → consumer
5. 开麦：`createProducer` → `onProduce` → `voice.produce` 回填 producerId → `voice.updateState({micMuted:false})`
6. 屏幕共享同理，`kind: screen`；结束走 `voice.closeProducer` + `updateState({sharingScreen:false})`

## 这一版还没有（对照网页端）

文件上传/图片预览、子线程、消息内 HTML 渲染（当前按纯文本显示）、搜索、摄像头、远端画面画质选择、
管理与服务器设置界面、插件、邀请、用户资料编辑、通知与音效、离线重连 UI。协议层（`SharkordCore`）
已具备这些接口，属于界面层未接。

## Apple Watch：腕上 PTT 终端

Watch 不是缩小版客户端，是**语音频道的腕上对讲机**。产品定义是明确的会话生命周期：

1. **Join**：打开 App → 选频道 → 进房间即加入；认证 tRPC socket 加入语音频道并启动
   `AVAudioSession (.playAndRecord)`。
2. **收听**：默认只听；Watch 收到定向 PCM 音频帧后播放。
3. **按住说话**：半双工 PTT，按住才开麦克风采集（RMS 电平表），松手即停，继续收听。
   麦克风只在已建立的会话里允许打开（状态机在 `.listening` 之外拒绝 `beginTransmit`）。
4. **明确 Leave**：离开频道 = 停采集、断传输、`AVAudioSession` 关闭，回到普通 App 状态。
   系统返回手势（`onDisappear`）同样收尾整个会话。

屏幕：连接（复用 connect.* 文案）→ 频道列表（卡片 + 人数）→ 对讲房间（状态胶囊、
参与者与静音状态、大圆 PTT 钮 + 电平表、红色离开键、数码表冠调音量、震动反馈）。
设计沿用 iPhone 的纯黑 + 深灰圆角卡片 + 宝蓝主色（`WatchTheme`）。

媒体通过第二条已认证 tRPC WebSocket 传输。Watch 发送 16 kHz mono PCM 帧；服务端使用
Opus 编解码与 mediasoup `DirectTransport` 将音频桥接到现有语音房，并把远端音频定向发给
各 Watch 接收端。Watch target 不依赖缺少 watchOS 切片的 mediasoup WebRTC 二进制，也不做
P2P。传输仅在明确 Join 与 Leave 之间运行。

关键待验收场景：加入后静默 5/15/30 分钟，另一端突然 PTT，Watch 是否能立即出声；还需检查
腕上麦克风权限、网络切换、松手后快速静音、断线清理与多 Watch 用户并发播放。

## 验证状态

- `xcodebuild`（scheme `Sharkord`，`generic/platform=iOS Simulator`，`CODE_SIGNING_ALLOWED=NO`）编译通过，
  Swift 0 error 0 warning；`Sharkord.app/PlugIns/SharkordLiveActivity.appex` 正常嵌入并校验。
- `xcodebuild`（scheme `SharkordWatch`，`generic/platform=watchOS Simulator`）编译通过，Swift 0 error 0 warning；
  `Sharkord.app/Watch/SharkordWatch.app` 正常嵌入（Embed Watch Content + ValidateEmbeddedBinary）。
- 五语言 `Localizable.strings` 均为 125 键，键集一致，`plutil -lint` 通过；`bun run synci18n` 报告 web locale 完整。
- 服务端 Watch radio 专项测试通过（19 tests），覆盖两向 Opus/PCM 媒体桥接、权限、无效帧、
  RTP 解析、定向事件与桥接清理；`apps/server` 的 `bun --bun run magic` 通过类型检查与格式化，
  lint 有 8 条既有 `no-explicit-any` warning。
- `xcodebuild` 的 `SharkordWatch`（watchOS Simulator）与 `Sharkord`（iOS Simulator）构建通过。
- iOS 27.0 / watchOS 27.0 Simulator smoke test：在已有配对的 iPhone 18 Pro Max + Apple Watch Series 12（46 mm）上安装并启动 Watch App，截图确认登录界面正常显示；未输入账号或连接真实服务器。
- 服务端全量测试为 1475 pass、2 fail：配置测试在覆盖 `SHARKORD_WEBRTC_PORT` 时仍断言默认值；插件路由断连测试单独重跑仍失败（42 pass、1 fail）。不带端口覆盖无法运行配置测试，因为测试预加载与本机已运行 server 抢占 UDP 40000。
- **运行时验收仍不完整**：目前只验证 Watch App 启动和登录界面；未验证登录、消息、权限弹窗、PTT 音频与服务器端到端链路。真机音频、长时间静默后的唤醒、网络切换和后台行为仍待补。
