# Sharkord iOS (first feature version)

> **这一版有功能了。** 登录、频道、消息、表情回应、语音（开关麦、耳聋保护）、屏幕共享、
> 五种语言、灵动岛，全部走真实协议：`POST /login` + tRPC over WebSocket + mediasoup SFU。
> 没有示例数据，界面上不再有"离线示例"。
>
> **This version has working features.** Sign in, channels, messages, reactions, voice
> (mic on/off, output-off protection), screen sharing, five languages and the Dynamic
> Island all run on the real protocol: `POST /login` + tRPC over WebSocket + the mediasoup
> SFU. There is no sample data any more.

原生 iPhone/iPad 客户端，第一版功能。设计文档见
[`docs/NATIVE_STRATEGY.md`](../../docs/NATIVE_STRATEGY.md)，目录形态按其 §3.1。

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
| iPad | NavigationSplitView 双栏；iPhone 底部 Tab + 通话控制条 |

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
  DesignSystem.swift                    玻璃卡片、品牌色、头像（沿用 webspeak-ios 的美学）
  Onboarding/ConnectView.swift          真实登录
  Workspace/                            频道列表、消息、语音房间、成员、设置
  Voice/
    VoiceEngine.swift                   mediasoup 设备/传输/收发 + 麦克风保护规则
    RemoteVideoView.swift               远端视频/屏幕画面渲染
    RTPCodec.swift                      JSONValue <-> mediasoup JSON 字符串
  i18n/
    L10n.swift                          运行时切换语言
    Resources/<lang>.lproj/Localizable.strings   en / zh-Hans / es / fr / de
  Activities/                           灵动岛（app 侧）
SharkordLiveActivity/                   灵动岛（widget 扩展）
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

## 验证状态

- `xcodebuild`（scheme `Sharkord`，`generic/platform=iOS Simulator`，`CODE_SIGNING_ALLOWED=NO`）编译通过，
  `Sharkord.app/PlugIns/SharkordLiveActivity.appex` 正常嵌入并校验。
- **本机未安装 iOS Simulator runtime，因此没有运行时验收**：通话、屏幕共享、灵动岛均为编译期验证，
  真机/模拟器实测待补。
