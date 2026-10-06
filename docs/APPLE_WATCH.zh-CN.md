# Apple Watch 客户端 —— 已声明的意图，以及它必须先过的关口

> 本文是 [`APPLE_WATCH.md`](APPLE_WATCH.md) 的中文翻译。英文版为权威版本，如有歧义以英文版为准。
**语言：** [English](APPLE_WATCH.md) | 中文

本文是 [Track 4](../ROADMAP.zh-CN.md#track-4--apple-watch-原生声明为第四) 的依据。下文每一条平台论断都链接到 Apple 自己的文档；每一项实测数据都链接到它出自的开发者报告。凡是真的未知之处，本文会直说，而不是猜。

**状态：已声明，不是承诺。** 这个客户端目前只是一个意图。它到底能不能做出来，由第 5 节的验证决定 —— 无论结果如何，都会记录在此。

## 1. 这个客户端是什么

一个只做腕上按键说话（push-to-talk）的客户端，别的都不做：

- **进入**一个语音频道、**按住说话**、**听到频道**、**退出**。
- 不做文字、不做私信、不做频道管理。一次只在一个频道。
- 它不是缩小版的 iPhone 应用：手表本身就是产品，因为按键说话是唯一一种"手表胜过手机"的通话方式。

Apple 已在 watchOS 27 撤掉了自家的 Walkie-Talkie —— "With watchOS 27, Walkie-Talkie has been discontinued"（[Apple 支持页](https://support.apple.com/en-us/108416)）。那个形态随之空出，但第 3 节会说明为什么这**并不**意味着平台对第三方变得更友好。

## 2. watchOS 允许第三方 App 做什么

[TN3135 —— watchOS 上的低层网络](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos) 是权威说明，而且它比大多数人以为的更严格：

| 规则（TN3135） | 对本项目的后果 |
| --- | --- |
| 高层网络 —— 通过 `URLSession` 的 HTTP/HTTPS —— 对所有 App 可用 | 足够支撑文字/API 部分；不足以支撑语音 |
| 低层网络 —— `Network.framework`、TCP、UDP、`URLSessionWebSocketTask` —— **只有**三种情况允许：(a) 音频流 App 正在主动播放音频时；(b) VoIP App 使用 CallKit 进行通话时（watchOS 9+）；(c) 为 tvOS 做配对监听时 | 本设计**完全**依赖例外 (a) |
| **BSD sockets API 在 watchOS 上任何情况下都不能用** | 不能写裸 socket 代码；一切都必须走 `Network.framework` |
| 在上述例外之外，App 会拿到 `ENETDOWN`，`NWPathMonitor` 一直停在 `.unsatisfied` | 普通 App 根本握不住一个 socket |
| **模拟器永远放行低层网络** | 在模拟器里测到的任何数据都没有价值。必须每次都上真机 |

还有两条平台事实，同样出自 Apple 文档：

- **watchOS 上没有 Push to Talk。** [Push to Talk 框架](https://developer.apple.com/documentation/pushtotalk) 标注的是 iOS 16+、iPadOS 16+、Mac Catalyst 16+ —— 里面没有 watchOS —— 而 APNs 的 `pushtotalk` 推送类型也只在这些平台上有文档。因此按键说话类 App **没有任何系统级的后台唤醒机制**：如果没有正在运行的会话，就没有任何东西能把 App 叫醒。这正是本客户端被设计成**只在显式会话之内**存在（"进入……退出"）而不是一个常听的对讲机的原因。
- **后台音频会话只在"有音频在播"时买到运行时间。** Apple 的原话是：后台音频模式 "provides additional runtime as long as the audio plays"（[Using extended runtime sessions](https://developer.apple.com/documentation/watchkit/using_extended_runtime_sessions)）。请仔细读那个条件 —— *只要有音频在播* —— 然后再想想按键说话的房间：它大部分时间是安静的。第 3 节讲的就是接下来会发生什么。
- **前台状态不是永久的。** 前台 App 默认两分钟后回到表盘；只要它处于前台**或**正在运行后台会话，常亮（Always On）显示就会继续显示它（[Taking advantage of frontmost app state](https://developer.apple.com/documentation/watchkit/taking-advantage-of-frontmost-app-state)）。真正让 App 在实际上活着的是正在运行的音频会话。

## 3. 卡住整个设想的那个未修复缺陷

这一段通常是那些乐观的解读里缺失的部分，也正是本客户端被"声明"而不是被"排期"的原因。

**报告来源。** Apple 开发者论坛帖 [841590](https://developer.apple.com/forums/thread/841590) —— "Does the TN3135 audio-session networking exception have a defined lifetime? Seeing a ~38.5 s revoke/re-grant cycle"（2026 年 8 月，Apple Watch Series 10 / watchOS 26.5，并在 Series 6 上复现）。配置：`UIBackgroundModes: [audio]`、`AVAudioSession` 的 `.playAndRecord` / `.spokenAudio`、一个走 TLS 的 `NWConnection` WebSocket。

**实测数据。** 挂机过夜，19 小时采 1,549 个样本，在服务端记录：

| 指标 | 数值 |
| --- | --- |
| 会话长度中位数 | **38.5 秒** |
| 均值 / 标准差 | 38.60 秒 / 0.62 秒 |
| 5–95 百分位 | 37.9 – 39.2 秒 |
| 落在 35–40 秒内的会话 | 97.9%（1,549 个里只有 21 个超出 30–50 秒） |
| 每轮中断时长 | 稳定约 2.0 秒 |

**最小复现。** 一个手表 App：激活音频会话、向 `www.apple.com:443` 打开一个 `NWConnection`，别的什么都不做 —— 没有麦克风、没有音频引擎、没有播放、没有重试：

- 路径在**单次激活后 35.5 秒被收回**；
- 随后连接以 `POSIXErrorCode 9: Bad file descriptor` 失败；
- 因为它从不重新激活，路径**连续 8 分 50 秒**都停在 `.unsatisfied` —— 它**不会**自己恢复。恢复必须**再激活一次**。

**Apple 的说法。** Apple DTS（Quinn "The Eskimo!"）确认该行为是缺陷：系统本应忽略多余的激活，修复由 **FB24377808** 跟踪 —— "To be clear, it's definitely misbehaviour"。但在报告者移除多余激活之后，循环照旧发生，包括全新启动后的**第一次**激活、以及设备静默 7.5 分钟之后的激活 —— 因此这个缺陷不能只用"重复激活"这一条来解释。截至报告者最后一次更新（2026-08），该帖没有结论；同期另一位开发者也报告了相同现象。

**为什么系统版 Walkie-Talkie 不构成反例。** 在同一块手表上，Apple 自家的 Walkie-Talkie 能稳定保持远超 38.5 秒的会话 —— 但它是作为系统级 VoIP 服务走 FaceTime Audio 运行的，并不走第三方那条 TN3135 例外。它在 watchOS 27 被撤掉，并不会把这种能力转移给任何第三方。

**这对设计意味着什么。** 那条"音频流例外"表现得不像一张长期通行证，而更像**每次激活大约 36 秒**：激活、拿到路径、失去它、再重建。按字面理解，这就是每半分钟重连一次 —— 对讲机场景"能活但看得见"，而对"整个晚上待在频道里"这类产品则是致命伤。

**绕过办法，以及它为什么改变局面。** 在同一帖的后半段，报告者把机制摸清了：这次"收回"是**按最近一次 `activate(options:completionHandler:)` 排程**的，而随后的一次激活会**替换**掉这个待执行的收回，而不是再排一个 —— 所以在到期前重新激活，就能把截止时间无限期往后推。实测数据：第 1 次激活后 20 秒再激活一次，收回发生的时间变成**第 2 次激活之后 36.5 秒**（而不是第 1 次之后的 58.1 秒）；用报告者的话说，这次重新激活**既不打断网络路径，也不打断已经建立的连接**。如果这成立，客户端就可以靠**定时续期音频会话**把 socket 一直握着，而不必每次掉线后再重连。这是**社区结论，不是 Apple 的表态**，而且有四个未验证的边界：

- 目前所有公开测量用的都是一个**没有麦克风、没有音频引擎、没有播放**的探针 —— 没有任何人证明过"真实音频在传"时它还能成立；
- "无限期"是报告者的说法，公开数据里没有连续几小时的记录；
- 它在 **watchOS 27 上没有复测过**（帖子最后活动是 2026-09-05，而报告是在 watchOS 26.5 上做的）；
- 耗电代价完全没有测量。

还有两个额外的麻烦：

- TN3135 把例外限定在*正在主动播放音频*时，而 PTT 房间大部分时间是安静的。在已报告的那个案例里，持续播放静音并没有阻止循环（仍然是 36.4 秒）。
- 另一扇合法的大门是例外 (b)，即 VoIP + CallKit（watchOS 9+），它确实能拿到持久的低层网络 —— 但它的表现形式是**一通电话**：系统通话界面、振铃语义。那是与"频道式对讲"不同的另一种产品。

**目前的态势（截至 2026-10）。** 帖子发表于 2026-08-11；缺陷在 8 月中旬立案，最小复现与系统诊断日志于 2026-08-21 附上；Apple 在该帖的最后一次回复是 2026-09-05，之后 DTS 工程师表示他将退出这个循环，修复由那份报告跟踪。对 Feedback Assistant 而言七周还很年轻 —— 那里的沉默既不是承诺，也不是不受理 —— 但这一层面的修复现实上会随**系统版本**发布，而不是点版本，所以这不是一件值得等的事。真正重要的两个问题，在我们自己的硬件上就能回答：**续期在真实音频下是否成立，以及在 watchOS 27 上是否仍然成立？**

我们也查了那个看起来很乐观的线索：WWDC26 第 226 场 [Create live communication experiences](https://developer.apple.com/videos/play/wwdc2026/226/)（`LiveCommunicationKit`，`CXProvider` 的继任者）。它的**全文都没提到 watchOS** —— 那是一套 iOS 系统界面集成方案，并不改变 TN3135 里的三种例外。

## 4. 媒体：为什么手表上不会跑 WebRTC

Sharkord 的语音是 [mediasoup](https://mediasoup.org) WebRTC —— DTLS-SRTP、ICE、UDP 上的 RTP —— 而不是往 socket 里塞裸 Opus 包（见 [`RTC_ARCHITECTURE.zh-CN.md`](RTC_ARCHITECTURE.zh-CN.md)）。因此手表客户端不可能"直接发 Opus"，只有两条路：

| 路线 | 代价 |
| --- | --- |
| **A. 把 WebRTC 移植到 watchOS** —— `libmediasoupclient` 加 `libwebrtc`，为 arm64_32 交叉编译 | 极高。`libmediasoupclient` 是构建在 `libwebrtc` 之上的 C++；即便 iOS 版本，体积已经大到社区客户端只能把静态库放在站外分发。在 watchOS 上它还要挤进极紧的 CPU/功耗预算，而持续高 CPU 正是系统取消一个会话的理由。 |
| **B. 在服务端加一座接入桥** —— 通过 mediasoup 的 `PlainTransport` 把手表的音频当成普通 RTP/Opus 音源接进来（mediasoup 文档中为接入 FFmpeg/GStreamer 音源所记录的正是这条路径），再转发进频道 | 中等，而且是服务端的活，在我们已经掌控的那套技术栈里做。手表端于是只需要 Opus 加一个 socket。 |

**方向：B。** 最贵的部分（一整套 WebRTC 栈）留在服务端，那里本来就有；手表客户端则保持小到能在该平台的约束里活下来。有一个后果必须明确，不能默认略过：`PlainTransport` 承载的是**未加密**的 RTP，所以这座桥要么放在隧道里（WireGuard/Tailscale），要么就得给音频套上 SRTP。这是隐私问题而不是性能问题，将在 W2 里定下来。

## 5. 验证：三个数字，在真机上

把关的是**对外声明**，不是设计工作。界面与它的状态机**并行开发** —— 它们不依赖这个答案，而且可以移植到 iOS —— 但在下面这三个数字出来之前，我们不会把任何东西说成“能用”。

| # | 要测什么 | 方法 |
| --- | --- | --- |
| 1 | 单次音频会话激活后，是否约 35–38 秒被收回？ | 最小探针：只激活一次，握着一个 `NWConnection`，记录 30 分钟内的 `NWPathMonitor` 状态变化与 socket 状态 |
| 2 | 定时续期能否把会话一直握着 —— 而且是在**双向真实音频流动**的情况下？ | 一个探针：在真实的双向 Opus 音频流动时，每约 20 秒续期一次音频会话，持续至少 60 分钟，记录路径状态、连接状态、可听见的中断与丢帧 |
| 3 | 一个 30 分钟的开放会话要耗多少电？ | 同一个探针，测每 30 分钟的电量下降百分比，再外推到 1 小时 |

**通过标准。** 如果 (2) 在当前的 watchOS 上能用真实双向音频撑住一小时的会话、且全程无可听见的中断，并且 (3) 允许一小时的会话，那么这个客户端就可以按设计做出来。如果不是，诚实的出路只有：改走 CallKit 那扇门（另一种产品）、围绕"按需连接"重新设计、或者直接说明今天在 watchOS 上做腕上客户端不可行。这任何一种结果，都比发布一个卡顿的东西要好。

**本项目的硬规矩：** 绝不要用模拟器给 watchOS 网络问题下任何结论。TN3135 明确写着模拟器永远放行低层网络 —— 对这个具体问题而言，模拟器就是一台制造假阳性的机器。

## 6. 前例

- **WatchCord**（[App Store](https://apps.apple.com/us/app/watchcord-for-discord-server/id6677009916)）自称是 "the first app supporting Discord Voice Chat on Apple Watch"。它公开的功能列表把文字和语音混在一起，而使用说明要求先在配对的 iPhone 应用上登录，因此它本身并不能证明"手表独立的语音会话"可行。两种可能都未经验证；在自己动手之前值得先解剖它看看。
- **Apple 自家的 Walkie-Talkie** 作为系统 VoIP 服务运行，已在 watchOS 27 被撤掉。它从来不是第三方可以套用的范式。
- **基于 PushToTalk 的对讲类 App**（WWDC22 那套 `Push to Talk` 设计）面向 iOS；该框架在 watchOS 上并不存在，所以那些 App 顶多是"手机 App + 手表遥控"。

## 7. 待解答的问题

1. 定时续期在 **watchOS 27** 上还成立吗？那个缺陷有没有随该版本变化？自 2026-09-05 以来没有任何人复测过。
2. 续期能否**无限期**成立？而且是在**真的有非静音音频**在流动时也成立？目前所有公开测量用的探针都没有麦克风、没有音频引擎、也没有播放。
3. 续期能否扛过平台级打断 —— 来电、Siri、手腕放下后会话开着好几个小时 —— 还是其中任意一种会把那个时钟重置成"续不回来"的状态？
4. 考虑到通话语义，例外 (b)（VoIP + CallKit，watchOS 9+）能否用于频道式对讲？Apple 的审核会接受这种用法吗？
5. 开放会话每小时真实的耗电是多少？系统的 CPU/功耗策略会不会在通话中途取消会话？
6. 当服务器是从公网访问时，未加密的 `PlainTransport` 路线可以接受吗？还是这座桥必须补上 SRTP（如果是，手表侧的代价是什么）？

## 来源

- [TN3135 —— watchOS 上的低层网络](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)
- [Push to Talk 框架](https://developer.apple.com/documentation/pushtotalk)（iOS 16+、iPadOS 16+、Mac Catalyst 16+）
- [Using extended runtime sessions](https://developer.apple.com/documentation/watchkit/using_extended_runtime_sessions)
- [Taking advantage of frontmost app state](https://developer.apple.com/documentation/watchkit/taking-advantage-of-frontmost-app-state)
- [Use Walkie-Talkie on your Apple Watch](https://support.apple.com/en-us/108416)（watchOS 27 已撤掉）
- [Apple 开发者论坛帖 841590](https://developer.apple.com/forums/thread/841590) —— 约 38.5 秒的收回循环，Apple 缺陷 **FB24377808**
- [WWDC26 第 226 场 —— Create live communication experiences](https://developer.apple.com/videos/play/wwdc2026/226/)（已读全文：没有任何 watchOS 内容）
- [mediasoup 文档](https://mediasoup.org/documentation/v3/mediasoup/) —— plain transport，即接入外部 RTP 音源所设计的那条路径
