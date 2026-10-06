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

下表状态以「本机实测通过」为准，不是「写完代码」。Swift 端 12 个测试、C# 端 12 个测试全部通过，
其中各含 2 个对**真实服务器**的端到端测试（登录 → 加入 → 收发 → 编辑 → 回应 → 删除 → 私信）。

| 能力 | 服务端接口 | macOS | Windows Core |
| --- | --- | --- | --- |
| 服务器信息 / 可达性 | `GET /info` | ✅ | ✅ |
| 登录 / 自动注册 | `POST /login` | ✅ | ✅ |
| 连接 + 握手 + 加入 | WS + `others.handshake` / `others.joinServer` | ✅ | ✅ |
| 令牌持久化 | 钥匙串（macOS）/ DPAPI 规划中（Core 只持有令牌） | ✅ | 部分 |
| 频道树（分类 → 文字/语音） | join 载荷 + `channels.*` 事件 | ✅ | ✅ |
| 消息历史（游标分页） | `messages.get` | ✅ | ✅ |
| 发送消息（含回复、附件 ID） | `messages.send` | ✅ | ✅ |
| 编辑 / 删除消息 | `messages.edit` / `messages.delete` | ✅ | ✅ |
| 表情回应（自定义 + 标准） | `messages.toggleReaction` | ✅ | ✅ |
| 输入中提示 | `messages.signalTyping` + `messages.onTyping` | ✅ | ✅ |
| 已读回执 / 未读角标 | `channels.markAsRead` + `onReadStateUpdate` / `onReadStateDelta` | ✅ | ✅ |
| 私信列表 / 打开会话 | `dms.get` / `dms.open` + `dms.onConversationOpen` | ✅ | ✅ |
| 附件上传 | `POST /upload` | ✅（上传 + 发送） | Core ✅（UI 未接） |
| 实时消息事件 | `messages.onNew` / `onUpdate` / `onDelete` / `onThreadReplyCountUpdate` | ✅ | ✅ |
| 实时用户事件 | `users.onJoin` / `onLeave` / `onUpdate` / `onCreate` / `onDelete` | ✅ | ✅ |
| 实时频道/分类事件 | `channels.*` / `categories.*` | ✅ | ✅ |
| 实时表情/角色/服务器设置 | `emojis.*` / `roles.*` / `others.onServerSettingsUpdate` | ✅ | ✅ |
| 在线状态 + 成员分组 | 用户事件 + `status` | ✅ | ✅ |
| 断线重连（固定退避 + 重新加入） | `[1,2,4,8,8]s` | ✅ | ✅ |

协议细节集中在单一位置，并由逐字节单测固定：macOS 是 `TRPCProtocol.swift` / `TRPCWebSocketClient.swift`，
Windows 是 `TrpcProtocol.cs` / `TrpcWebSocketClient.cs`。

---

## 二、明确的局限

### 2.1 阻塞性（当前无法绕过）

1. **Windows 的 WinUI 3 界面未编译、未运行。** Windows App SDK 只能在 Windows 上构建，macOS 上无法验证。
   `Sharkord.App` 是一个常规 WinUI 3 外壳，但**没有在任何机器上构建过**，其 `Microsoft.WindowsAppSDK`
   版本号是占位值。它必须在 Windows 机器或 CI 上首次构建并修正。
2. **Windows 无语音。** C# 没有任何 mediasoup 客户端；需要 P/Invoke `libmediasoupclient`（MSVC + libwebrtc）
   或在 C# WebRTC 之上重写 mediasoup 协议。这是策略文档里的 1 号风险，尚未开始预研。
3. **macOS 界面没有逐屏人工验收。** 只做了编译、单测与协议层端到端，没有对窗口外观、键盘/鼠标交互逐屏走查。

### 2.2 尚未实现的功能（网页端有，原生端还没有）

| 领域 | 缺口 |
| --- | --- |
| **语音** | 加入语音频道、麦克风/扬声器、屏幕共享、视频（macOS 与 Windows 均无）。语音频道视图目前是占位页。 |
| **插件** | 插件 UI 在网页端是针对 `window.__SHARKORD_*` 运行的 React，原生端不嵌 WebView 就无法承载。v1 明确不做。 |
| **线程** | `messages.getThread` / 线程侧栏 / 回复计数 UI（只订阅了计数事件，未做界面）。 |
| **搜索** | `messages.search` 未接入。 |
| **消息置顶** | `messages.togglePin` / `getPinned` 未接入。 |
| **频道/分类/角色/表情管理** | 相关的写接口（`channels.add/update/delete/reorder`、`categories.*`、`roles.*`、`emojis.*`、`invites.*`）未接入；只消费了这些实体的事件。 |
| **用户管理** | `users.kick/ban/unban/delete/update/addRole/removeRole/changeAvatar/changeBanner/updatePassword` 未接入。 |
| **服务器设置界面** | `others.getSettings/updateSettings/updateServer/getStorageSettings` 未接入。 |
| **附件与头像的完整展示策略** | 图片通过 `/public` 直连；开启签名 URL 的服务器需要 `accessToken`/`expires`（已支持），但大文件、视频预览、下载管理未做。 |
| **富文本** | 网页端编辑器产出 HTML（提及、频道引用、emoji、链接补全）；原生端目前只把纯文本转义为 `<p>`/`<br>`，**不发送链接自动识别、@提及、自定义 emoji 内联**。 |
| **通知** | 桌面通知（`UNUserNotificationCenter` / Windows Toast）、未读汇总、系统托盘常驻均未做。 |
| **全局快捷键 / 按键通话** | macOS `CGEventTap`（需辅助功能权限）、Windows `RegisterHotKey` / 低级钩子，均未做。 |
| **i18n** | 界面字符串目前是内联英文/中文，未接 `SUPPORTED_LOCALES`（8 种语言）。 |
| **外观** | 主题、字号、无障碍（VoiceOver / 讲述人）未做。 |

### 2.3 已知工程风险

1. **tRPC 线格式不是公开规范。** 它是 `@trpc/client` v11 的实现细节，升级上游可能破坏原生端。缓解：
   格式集中在两个文件里，并有逐字节单测；上游一旦变化，会先在这里失败。
2. **两套逻辑实现。** Swift 与 C# 各自实现一遍协议与会话，存在漂移风险。缓解：两侧单测覆盖同一组
   用例，且 C# 端的线格式测试与 Swift 端的输入/输出完全对齐。中长期按策略文档路线 (c) 引入生成式
   协议契约（`packages/protocol`）来消除重复。
3. **`Sharkord.Core` 的令牌持久化。** Core 只持有令牌；Windows 端真正落盘需要 DPAPI（`ProtectedData`），
   macOS 已用钥匙串。DPAPI 尚未接入。
4. **打包与签名。** macOS 目前是 `swift run` 的裸可执行文件，未产出签名/公证的 `.app`；Windows 未产出 MSIX。

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

对真实服务器的端到端测试（会注册用户并发消息，请指向一次性实例）：

```bash
# 起一个隔离实例
cd apps/server
SHARKORD_DATA_PATH=/tmp/sharkord-verify SHARKORD_PORT=4992 SHARKORD_WEBRTC_PORT=40001 \
  SHARKORD_BACKUP_DATABASE=false bun run ./src/index.ts

# macOS
cd apps/macos && SHARKORD_IT_HOST=127.0.0.1:4992 swift test

# Windows Core
cd apps/windows && SHARKORD_IT_HOST=127.0.0.1:4992 dotnet test tests/Sharkord.Core.Tests
```

---

## 四、依赖与工具链

- macOS：Xcode 27 / Swift 6.4（本机已有，直接复用）。无第三方 Swift 依赖。
- Windows Core：.NET SDK 8.0（本机用官方 `dotnet-install.sh` 装到 `~/.dotnet`，无需 sudo）。
  `Sharkord.App` 另需 Windows App SDK，仅 Windows 可还原。
- 两者都不进入 Bun workspace：`apps/macos` 与 `apps/windows` 下没有 `package.json`，`bun.lock` 不受影响。
