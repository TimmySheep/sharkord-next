# Sharkord Next — 路线图
> 本文是 [`ROADMAP.md`](ROADMAP.md) 的中文翻译。英文版为权威版本，如有歧义以英文版为准。
**语言：** [English](ROADMAP.md) | 中文

本路线图刻意保持保守：它列出我们打算做的事、**我们已决定不做的事**，以及每项决定背后的依据。下文每一条论断都链接到 [`docs/`](docs/) 中的一份文档，这些文档是针对 `c611bb4` 版本的实际源码撰写的。

## 优先级顺序（已确定）

1. **macOS，原生** — Swift + SwiftUI，不使用 Electron。
2. **Windows，原生** — C# + WinUI 3，先做文本，语音需通过可行性验证（spike）后才推进。
3. **iPhone + iPad，原生** — 一个 Apple 项目，复用 macOS 本来就需要的那套 Swift 核心。
4. **Apple Watch，原生** — 已声明；腕上按键说话客户端，需先过可行性验证。
5. 直连（P2P）语音，然后是自托管质量，与原生开发工作并行推进。

**Android 原生客户端已开始开发**，代码位于 [`apps/android`](apps/android)。本 fork 中的 PWA/移动 Web 工作仍计划向上游提议。

状态图例：**✅ 已完成** · **🔜 下一步** · **🧪 需要可行性验证（spike）** · **📋 已计划** · **⛔ 不做**

## 指导原则

1. **原生，而非套壳。** 不做那种重新加载 Web 应用的 Electron 外壳。
2. **保持与上游可合并。** 我们按上游的形态来工作，这样改进才能双向流动。
3. **带宽意识。** 自托管者往往先耗尽上行带宽，而不是先耗尽功能。
4. **能用的最小实现。** 这是上游自己的规则；新的抽象必须有第二个调用点才值得引入。
5. **先验证再下结论。** 文档和 PR 会把实测结果与预期分开陈述。

## ⛔ 我们不做的事

| 不做 | 原因 |
| --- | --- |
| **本 fork 中的 PWA / 移动 Web 工作** | 这三个 Web 客户端的缺口都是对上游客户端的通用改进。在上游修复，所有自托管实例和第三方客户端都能受益；在这里修复，只有我们受益。已在 [Track 6](#track-6-upstream-collaboration) 向上游提议。 |
| **Electron 桌面客户端** | 大约已经有十几个轻量的 Electron 套壳。原生客户端才是差异点；套壳不是。 |
| **插件沙箱 / 运行时重写** | 上游的插件模型是刻意设计的（受信任、进程内、按能力授权）。替换它会破坏所有现有插件，而用户感知不到任何收益。 |
| **让线路协议（wire protocol）产生分歧** | 每个第三方客户端都依赖现有的 tRPC-over-WebSocket + mediasoup 信令。一个自创协议的 fork，无法被它想吸引的生态所使用。 |
| **对 Web 客户端做大重写** | 参考客户端是可用的。我们不碰它的架构。 |

## Track 1 — macOS 原生（第一）

| 项目 | 状态 |
| --- | --- |
| 项目骨架：`apps/macos` 下的 SwiftPM 核心 + SwiftUI 应用，接入协议契约 | 📋 |
| M1：登录 → 服务器 → 频道 → 文本，对接真实服务器 | 📋 |
| M2：语音（通过 Swift 封装调用 mediasoup 客户端）、按键说话（push-to-talk）、按频道音频 | 🧪 |
| 原生体验能力：菜单栏驻留、全局按键说话快捷键、原生屏幕捕获（ScreenCaptureKit）、系统音频 | 📋 |

设计、模块划分和平台 API 矩阵：[`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md)。
已知风险：macOS 上的全局快捷键需要辅助功能（Accessibility）权限；原生媒体意味着必须为 Swift 封装 mediasoup 客户端——目前没有官方的 Swift 客户端。

## Track 2 — Windows 原生（第二）

| 项目 | 状态 |
| --- | --- |
| M3：WinUI 3 客户端，文本优先（登录 → 服务器 → 频道 → 文本） | 📋 |
| M4：**语音可行性验证（spike）**——构建 `libmediasoupclient`（MSVC + libwebrtc）并对其进行 P/Invoke，或记录为何这条路不可行 | 🧪 |
| 原生体验能力：系统托盘、全局快捷键、WASAPI 音频、Windows.Graphics.Capture | 📋 |

**今天 Windows 语音尚无可用引擎**（不存在 C# 的 mediasoup 客户端）。因此文本先行，语音由 M4 把关，而不是直接承诺。完整风险表见 [`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md)。

## Track 3 — iPhone + iPad 原生（第三）

| 项目 | 状态 |
| --- | --- |
| 一个服务于 iPhone 和 iPad 的 Apple 项目，复用为 macOS 构建的 Swift 核心 | 📋 |
| 使用平台音频会话的语音、APNs 通知、后台行为 | 📋 |

先做 macOS 是刻意的：两者都用 Swift，因此为 Track 1 编写的核心会被复用而非重写。开工前值得一读的已记录约束：在 iOS 上录音会话无法从后台启动，且 `playAndRecord` 会被来电抢占。

## Track 4 — Apple Watch 原生（声明为第四）

一个只做腕上对讲机的客户端：进入一个语音频道、按住说话、听到频道、退出。不做文字，一次只在一个频道。这是**已声明的意图**，**不是**功能承诺 —— 因为下面那个平台问题还没有答案，而答案决定它到底能不能做出来。

**设计与验证并行推进；验证把关的是"对外声明"。** 界面与它的状态机不依赖那个平台答案，而且可以移植到 iOS，所以它们与 W1 并行开发。W1 把关的是**声明**：在测量出结果之前，这里不会把任何东西说成"能用"。

| 项目 | 状态 |
| --- | --- |
| W1：**在真机上的 watchOS 网络可行性验证** —— 在当前的 watchOS 上，单次音频会话激活是否约 36 秒后被收回（Apple 缺陷 **FB24377808**）；定时续期能否用真实双向音频撑住一小时；以及这要付出多少耗电代价 | 🧪 |
| W1b（并行，不依赖 W1）：**watchOS 界面与状态机** —— 频道列表、频道内按键说话、如实呈现的**重连中**与**降级**状态，以及把音频引擎放在可替换接口之后，让模拟器能用桩件跑起界面。现在就开始做，且可移植到 iOS | 📋 |
| W2：架构决定 —— 服务端接入桥（mediasoup `PlainTransport`，也就是 FFmpeg/GStreamer 音源走的那条路）对比在手表上跑 WebRTC 栈，并记录两种选择各自的传输加密后果 | 🧪 |
| W3：最小客户端 —— 进入、按键说话、退出，对接真实服务器 | 📋 |
| 判断这个客户端到底能否存在，并把结论（无论哪种）记录在此 | 🧪 |

为什么值得为手表单开一条线：按键说话是唯一一种手表胜过手机的通话方式，而 Apple 已在 watchOS 27 撤掉了自家的 Walkie-Talkie。但撤掉它对第三方**没有帮助** —— 系统版是以 FaceTime Audio 的 VoIP 服务运行的，从来没走第三方那条例外。相关限制连同**一手来源**记录在 [`docs/APPLE_WATCH.zh-CN.md`](docs/APPLE_WATCH.zh-CN.md)：watchOS 只在音频流、VoIP + CallKit、tvOS 配对三种情况下允许低层网络（TN3135）；Push to Talk 框架与 `pushtotalk` 推送类型在 watchOS 上都不存在；模拟器永远放行低层网络，所以只有真机数据算数；而已知的那次收回虽然有社区绕过办法，但尚未在真实音频下验证。

## Track 5 — 直连（P2P）语音

目前*所有*媒体都通过服务器 SFU 转发（`routed, not mixed`），因此一个 N 人频道会消耗主机 N−1 路上行流（[RTC](docs/RTC_ARCHITECTURE.md)）。对 1 对 1 通话而言，这纯属额外开销。

| 项目 | 状态 |
| --- | --- |
| 在现有服务器传输之外设计一个 `PeerRelaySession` 抽象，从 1 对 1 音频开始 | 🧪 |
| 用户可见的选择：每次通话/每个频道可在 **直连（Direct）** 与 **服务器（Server）** 之间选择，直连失败时有安全回退 | 📋 |
| 中继容量核算 + 面向自托管者的上行带宽护栏 | 📋 |

具体的改动面（信令、权限、服务器媒体抽象、客户端媒体层、ICE）连同 `file:line` 证据列于 [`docs/RTC_ARCHITECTURE.md` §7](docs/RTC_ARCHITECTURE.md)。

## Track 6 — 与上游协作

| 项目 | 状态 |
| --- | --- |
| 向上游提议小的移动 Web 修复：`viewport-fit=cover` + 安全区（safe-area）内边距，以及 iOS 独立（standalone）meta 标签 | 🔜 |
| 先把 service worker / 离线外壳（offline-shell）问题作为讨论向上游提出（它涉及产品取舍，因此可能不会被接受） | 📋 |
| 把通用 bug 修复提交上游，而不是留在下游 | 🔜（持续进行） |
| 保持 `development` 从 `upstream/development` 向前合并 | 🔜（持续进行） |
| 反馈生态所需的任何东西：协议版本化、上游版本端点、重连行为对齐 | 📋 |

经验法则：如果一项改动能惠及所有自托管者或客户端开发者，它就属于上游。只有专属于本项目自身方向的东西才在本仓库维护。

## Track 7 — 自托管质量

| 项目 | 状态 |
| --- | --- |
| 记录在隧道（tunnel）和 NAT 后导致语音失败的媒体/ICE 约束（announced address、端口对等、TCP 回退限制） | 🔜（部分见 [`docs/RTC_ARCHITECTURE.md` §6](docs/RTC_ARCHITECTURE.md)） |
| 诊断客户端侧上报的「Failed to initialize voice connection」：目前服务端流程是能跑完的，所以故障在媒体路径——很可能是 announced address 或 UDP 可达性 | 🧪 |
| 一旦我们发布服务端改动，就发布自己的固定版本镜像（特征：不使用 `latest`，始终用版本标签） | 📋 |
| 存储指引：签名 URL 默认是**关闭**的，因此除非服务器启用签名，附件 URL 是可公开读取的 | 📋 |

## Android 原生客户端，开发中

本仓库正在 [`apps/android`](apps/android) 下开发 Kotlin + Jetpack Compose 原生 Android 客户端。
当前实现与构建说明见 [Android 项目 README](apps/android/README.md)。

## 本路线图如何变更

欢迎通过 issue 提出建议。只有当某项路线图条目在 `docs/` 中的证据部分足够充分、能够描述出改动面时，它才会被提升为待办工作——这是本项目为自己设定的门槛，也正是为什么在任何代码被改动之前，就先写好了那套 `docs/`。

此处的里程碑编号反映上文的优先级顺序（macOS 先于 Windows，Windows 先于 iOS，iOS 先于 watchOS）。[`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md) 中的设计仍然适用；改变的只是各原生 Track 的先后顺序。
