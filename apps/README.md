# 原生客户端现状与局限

本目录包含 Sharkord 的两个原生客户端：

| 目录 | 平台 | 技术栈 | 上游可构建 | 本机已构建 |
| --- | --- | --- | --- | --- |
| `apps/macos` | macOS 14+ | Swift 6 + SwiftUI（SwiftPM） | ✅ | ✅ 已验证 |
| `apps/windows` | Windows 10 1809+ | C# + WinUI 3（.NET 8） | `Core` 跨平台；`App` 仅 Windows | Core ✅；App ❌（未构建） |

设计与证据见 [`docs/NATIVE_STRATEGY.md`](../docs/NATIVE_STRATEGY.md) 与 [`ROADMAP.md`](../ROADMAP.md)。
两者都**不使用 Electron、不内嵌 WebView**，直接与网页端同一套服务器通信（tRPC over WebSocket + 明文 HTTP）。

---

## 一、已实现并实测的能力

下表状态以「本机实测通过」为准，不是「写完代码」。macOS 端 41 个测试、Windows Core 端 12 个测试全部通过；
macOS 其中 6 个、Windows Core 其中 2 个是打**真实服务器**的端到端测试。

| 能力 | 服务端接口 | macOS | Windows Core |
| --- | --- | --- | --- |
| 服务器信息 / 可达性 | `GET /info` | ✅ | ✅ |
| 登录 / 自动注册 | `POST /login` | ✅ | ✅ |
| 连接 + 握手 + 加入 | WS + `others.handshake` / `others.joinServer` | ✅ | ✅ |
| 令牌持久化 | 钥匙串（macOS）/ DPAPI 规划中（Core 只持有令牌） | ✅ | 部分 |
| 频道树（分类 → 文字/语音） | join 载荷 + `channels.*` 事件 | ✅ | ✅ |
| 分类 / 频道增删改 + 排序 | `categories.*` / `channels.*` | ✅ | 事件消费 ✅ |
| 频道权限覆盖（角色 / 用户） | `channels.getPermissions` / `updatePermissions` / `deletePermissions` | ✅ | — |
| 消息历史（游标分页） | `messages.get` | ✅ | ✅ |
| 消息跳转窗口（含 `hasNewer`） | `messages.get` + `targetMessageId` | ✅ | — |
| 发送消息（含回复、线程、附件 ID） | `messages.send` | ✅ | ✅ |
| 编辑 / 删除消息 | `messages.edit` / `messages.delete` | ✅ | ✅ |
| 富文本（提及 / 频道引用 / 自定义 emoji / 链接 / 代码块） | 与 `sanitize-html.ts` 白名单逐字对齐 | ✅ | — |
| 表情回应（自定义 + 标准） | `messages.toggleReaction` | ✅ | ✅ |
| 消息置顶 | `messages.togglePin` / `messages.getPinned` | ✅ | — |
| 线程（回复列表 + 计数 + 侧栏） | `messages.getThread` / `onThreadReplyCountUpdate` | ✅ | 事件消费 ✅ |
| 搜索（消息 + 文件，含截断提示） | `messages.search` | ✅ | — |
| 输入中提示 | `messages.signalTyping` + `messages.onTyping` | ✅ | ✅ |
| 已读回执 / 未读角标 | `channels.markAsRead` + `onReadStateUpdate` / `onReadStateDelta` | ✅ | ✅ |
| 私信列表 / 打开会话 | `dms.get` / `dms.open` + `dms.onConversationOpen` | ✅ | ✅ |
| 附件上传（多选 / 拖拽 / 粘贴图片） | `POST /upload` | ✅ | Core ✅（UI 未接） |
| 角色管理（增删改、权限勾选、默认角色、存储配额覆盖） | `roles.*` | ✅ | — |
| 自定义表情管理（上传 / 改名 / 删除） | `emojis.*` | ✅ | — |
| 邀请码管理（创建 / 复制链接 / 删除） | `invites.*` | ✅ | — |
| 用户管理（列表 / 详情 / 踢 / 封 / 解封 / 删号 / 分配角色） | `users.*` | ✅ | — |
| 用户资料（名称 / 头像 / 横幅 / 资料色 / 简介 / 改密） | `users.update` / `changeAvatar` / `changeBanner` / `updatePassword` | ✅ | — |
| 服务器设置（General / Storage） | `others.getSettings` / `updateSettings` / `getStorageSettings` | ✅ | — |
| 服务器更新 | `others.getUpdate` / `others.updateServer` | ✅ | — |
| 插件管理（列表 / 启停 / 移除 / 日志 / 能力 / 设置只读） | `plugins.*` | ✅ | — |
| 语音控制面（加入 / 离开 / 静音 / 闭麦 / 摄像头与屏幕共享标志 / 反应 / 移动成员） | `voice.*` | ✅ | — |
| 语音媒体传输（音频 / 视频 / 屏幕共享实际流） | mediasoup WebRTC | ❌ | ❌ |
| 实时消息事件 | `messages.onNew` / `onUpdate` / `onDelete` / `onThreadReplyCountUpdate` | ✅ | ✅ |
| 实时用户事件 | `users.onJoin` / `onLeave` / `onUpdate` / `onCreate` / `onDelete` | ✅ | ✅ |
| 实时频道/分类事件 | `channels.*` / `categories.*` | ✅ | ✅ |
| 实时表情/角色/服务器设置/邀请/插件 | `emojis.*` / `roles.*` / `others.onServerSettingsUpdate` / `invites.*` / `plugins.*` | ✅ | 事件消费 ✅ |
| 在线状态 + 成员分组 | 用户事件 + `status` | ✅ | ✅ |
| 断线重连（固定退避 + 重新加入） | `[1,2,4,8,8]s` | ✅ | ✅ |
| i18n（8 语言 × 8 命名空间） | 与 `apps/client/src/i18n/locales` 同源打包 | ✅ | — |
| UI 文案全走 i18n（无硬编码英文） | 另有原生专属 `macos` 命名空间，8 语言齐备 | ✅ | — |

协议细节集中在单一位置，并由逐字节单测固定：macOS 是 `TRPCProtocol.swift` / `TRPCWebSocketClient.swift`，
Windows 是 `TrpcProtocol.cs` / `TrpcWebSocketClient.cs`。消息 HTML 的解析与生成在 macOS
`MessageHTML.swift`，由 `MessageHTMLTests`（12 个用例）固定住与网页端的词表一致性。

---

## 二、明确的局限

### 2.1 阻塞性（当前无法绕过）

1. **Windows 的 WinUI 3 界面未编译、未运行。** Windows App SDK 只能在 Windows 上构建，macOS 上无法验证。
   `Sharkord.App` 是一个常规 WinUI 3 外壳，但**没有在任何机器上构建过**，其 `Microsoft.WindowsAppSDK`
   版本号是占位值。它必须在 Windows 机器或 CI 上首次构建并修正。
2. **Windows 无语音。** C# 没有任何 mediasoup 客户端；需要 P/Invoke `libmediasoupclient`（MSVC + libwebrtc）
   或在 C# WebRTC 之上重写 mediasoup 协议。这是策略文档里的 1 号风险，尚未开始预研。
3. **macOS 界面没有逐屏人工验收。** 只做了编译、单测与协议层端到端，没有对窗口外观、键盘/鼠标交互逐屏走查。
   本轮尝试用 CUA 自动化截图走查，`cua-driver list-windows` 返回
   `Permission denied: tool 'list-windows' has no reviewed risk classification`，
   按规程未绕过、已暂停该路径，等权限补齐后重跑。

### 2.2 尚未实现的功能（网页端有，原生端还没有）

| 领域 | 缺口 |
| --- | --- |
| **语音媒体** | 控制面已全接通（`voice.*` 全部路由、订阅与成员状态），但**没有 WebRTC 媒体传输**：听不到、看不到、无法真的共享屏幕。Swift 侧没有现成的 mediasoup 客户端，这是「全部能力」里最大的一块，需要引 WebRTC 原生库或自实现 mediasoup 信令之上的传输层。界面上已标注该限制。 |
| **插件 UI** | 插件 UI 在网页端是针对 `window.__SHARKORD_*` 运行的 React，原生端不嵌 WebView 就无法承载。原生端已能列出插件、启停、移除、看日志与能力清单，但**插件设置是只读展示**、插件能力权限编辑器未做、插件命令执行界面未做（Core 的 `executePluginCommand` 已就绪）。v1 明确不做插件 UI。 |
| **通知** | 桌面通知（`UNUserNotificationCenter`）、未读汇总、系统托盘常驻均未做；未读角标只在侧栏显示。 |
| **全局快捷键 / 按键通话** | macOS `CGEventTap`（需辅助功能权限）、Windows `RegisterHotKey` / 低级钩子，均未做。 |
| **欢迎对话框 / 服务器密码对话框** | 用「资料」设置页与连接页的密码输入近似实现，没有做成独立的模态对话框与倒计时流程。 |
| **外观** | 主题（深色 token 固定）、字号调节、无障碍（VoiceOver / 讲述人）未做。 |
| **打包与签名** | macOS 是 `swift run` 的裸可执行文件，未产出签名/公证的 `.app`、无 `Info.plist`、无 Sparkle 更新；Windows 未产出 MSIX。 |

### 2.3 已知工程风险

1. **tRPC 线格式不是公开规范。** 它是 `@trpc/client` v11 的实现细节，升级上游可能破坏原生端。缓解：
   格式集中在两个文件里，并有逐字节单测；上游一旦变化，会先在这里失败。
2. **两套逻辑实现。** Swift 与 C# 各自实现一遍协议与会话，存在漂移风险。缓解：两侧单测覆盖同一组
   用例，且 C# 端的线格式测试与 Swift 端的输入/输出完全对齐。中长期按策略文档路线 (c) 引入生成式
   协议契约（`packages/protocol`）来消除重复。
3. **`Sharkord.Core` 的令牌持久化。** Core 只持有令牌；Windows 端真正落盘需要 DPAPI（`ProtectedData`），
   macOS 已用钥匙串。DPAPI 尚未接入。
4. **打包与签名。** macOS 目前是 `swift run` 的裸可执行文件，未产出签名/公证的 `.app`；Windows 未产出 MSIX。
5. **消息 HTML 词表是复刻，不是共享实现。** 网页端的 `prepare-message-html` / `linkify-html` /
   `message-sanitizer` 是 TS，Swift 端 `MessageHTML.swift` 是逐条复刻。上游改词表时原生端不会自动跟上，
   只能靠 `MessageHTMLTests` 里那 12 个对拍用例先红。这是最可能静默漂移的地方。

---

## 三、如何复现验证

离线单测（不联网）：

```bash
# macOS
cd apps/macos && swift build && swift test

# Windows Core（在 macOS/Linux 上也能编译与测试）
cd apps/windows && dotnet build src/Sharkord.Core/Sharkord.Core.csproj
dotnet test tests/Sharkord.Core.Tests/Sharkord.Core.Tests.csproj
```

对真实服务器的端到端测试（会注册用户并发消息、建分类频道角色表情邀请，请指向一次性实例）：

```bash
# 起一个隔离实例
cd apps/server
SHARKORD_DATA_PATH=/tmp/sharkord-verify SHARKORD_PORT=4992 SHARKORD_WEBRTC_PORT=40001 \
  SHARKORD_BACKUP_DATABASE=false bun run ./src/index.ts

# macOS（离线 + 端到端一起跑）
cd apps/macos && SHARKORD_IT_HOST=127.0.0.1:4992 swift test

# Windows Core
cd apps/windows && SHARKORD_IT_HOST=127.0.0.1:4992 dotnet test tests/Sharkord.Core.Tests
```

端到端用例（`SHARKORD_IT_HOST` 门控，不设则整套跳过）：

- `IntegrationTests.loginJoinSendAndReceive` 登录 → 握手 → 加入 → 发送 → 分页 → 订阅收到
- `IntegrationTests.editReactDeleteAndDirectMessage` 编辑 → 回应 → 输入中 → 已读 → 私信 → 删除
- `AdminSurfaceTests.categoryAndChannelTreeRoundTrip` 分类/频道增删改 + 排序 + 频道权限覆盖
- `AdminSurfaceTests.rolesEmojisAndInvites` 角色 + 表情上传改名删除 + 邀请创建删除
- `AdminSurfaceTests.pinsThreadsSearchAndSettings` 置顶 + 线程 + 跳转窗口 + 搜索 + 设置 + 语音加入离开
- `AdminSurfaceTests.pluginSurfaceIsQueryable` 插件列表与命令面可查询

跑 macOS GUI：

```bash
cd apps/macos && swift run SharkordMac
```

---

## 四、依赖与工具链

- macOS：Xcode 27 / Swift 6.4（本机已有，直接复用）。无第三方 Swift 依赖；i18n 资源是
  `apps/client/src/i18n/locales` 的逐字节拷贝，放在 `apps/macos/Resources/locales`。
- Windows Core：.NET SDK 8.0（本机用官方 `dotnet-install.sh` 装到 `~/.dotnet`，无需 sudo）。
  `Sharkord.App` 另需 Windows App SDK，仅 Windows 可还原。
- 两者都不进入 Bun workspace：`apps/macos` 与 `apps/windows` 下没有 `package.json`，`bun.lock` 不受影响。
