# 原生客户端现状与局限

本目录包含 Sharkord 的两个原生客户端，面向用户的软件名为 `cove`：

| 目录 | 平台 | 技术栈 | 上游可构建 | 本机已构建 |
| --- | --- | --- | --- | --- |
| `apps/macos` | macOS 14+ | Swift 6 + SwiftUI；WKWebView 仅承载语音媒体 worker | ✅ | Swift tests ✅；媒体运行时待验收 |
| `apps/windows` | Windows 10 1809+ | C# + WinUI 3（.NET 8）；WebView2 仅承载语音媒体 worker | `Core` 跨平台；`App` 仅 Windows | 现有 UI 源码本轮未构建，待 Windows 验收 |

设计与证据见 [`docs/NATIVE_STRATEGY.md`](../docs/NATIVE_STRATEGY.md) 与 [`ROADMAP.md`](../ROADMAP.md)。
两者都**不使用 Electron**，主要界面保持原生；只在原生语音画面中嵌入受限的 WKWebView / WebView2，复用 `mediasoup-client` 传输媒体。客户端仍直接与网页端同一套服务器通信（tRPC over WebSocket + 明文 HTTP）。

---

## 一、已实现并实测的能力

下表状态以「本机实测通过」为准，不是「写完代码」。macOS 端 46 个测试、Windows Core 端 53 个测试全部通过；
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
| 语音媒体传输（音频 / 摄像头 / 屏幕共享） | mediasoup WebRTC | 源码已接入，待 macOS 权限与真机媒体验收 | 源码已接入，待 Windows 编译与媒体验收 |
| 实时消息事件 | `messages.onNew` / `onUpdate` / `onDelete` / `onThreadReplyCountUpdate` | ✅ | ✅ |
| 实时用户事件 | `users.onJoin` / `onLeave` / `onUpdate` / `onCreate` / `onDelete` | ✅ | ✅ |
| 实时频道/分类事件 | `channels.*` / `categories.*` | ✅ | ✅ |
| 实时表情/角色/服务器设置/邀请/插件 | `emojis.*` / `roles.*` / `others.onServerSettingsUpdate` / `invites.*` / `plugins.*` | ✅ | 事件消费 ✅ |
| 在线状态 + 成员分组 | 用户事件 + `status` | ✅ | ✅ |
| 断线重连（固定退避 + 重新加入） | `[1,2,4,8,8]s` | ✅ | ✅ |
| i18n（10 语言 × 9 命名空间） | 与 `apps/client/src/i18n/locales` 同源打包，另补 `de` / `zh-Hant` | ✅ | 基础层 ✅（10 语言 × 2 命名空间） |
| UI 文案全走 i18n（无硬编码英文） | 另有原生专属 `macos` / `windows` 命名空间，10 语言齐备 | ✅ | ✅ |

协议细节集中在单一位置，并由逐字节单测固定：macOS 是 `TRPCProtocol.swift` / `TRPCWebSocketClient.swift`，
Windows 是 `TrpcProtocol.cs` / `TrpcWebSocketClient.cs`。消息 HTML 的解析与生成在 macOS
`MessageHTML.swift`，由 `MessageHTMLTests`（12 个用例）固定住与网页端的词表一致性。

---

## 二、明确的局限

### 2.1 阻塞性（当前无法绕过）

1. **Windows 的 WinUI 3 界面已构建，但从未启动、未走查。** 2026-10-07 的当前 Cove x64
   Release `dotnet publish` **通过，0 警告 0 错误**，并产出便携包；Core 测试 **53/53 通过**。
   窗口外观与实际交互仍未验收。
   `Microsoft.WindowsAppSDK 1.6.240923002` 与 `Microsoft.Windows.SDK.BuildTools 10.0.26100.1742`
   是可还原、可构建的真实固定版本，不是占位值。构建前提是 `-p:Platform=x64` 不能省
   （csproj 声明 `Platforms=x64;ARM64`，默认 `AnyCPU` 不在列表内会报 `OutputPath` 未设置）。
2. **Windows 语音尚未验收。** 语音界面、WebView2 媒体 worker 与 C# 信令桥已接入源码；本轮修改后尚未在 Windows 编译或运行，因此不能把源码接通等同于可用。
3. **macOS 界面没有逐屏人工验收。** 只做了编译、单测与协议层端到端，没有对窗口外观、键盘/鼠标交互逐屏走查。
   本轮尝试用 CUA 自动化截图走查，`cua-driver list-windows` 返回
   `Permission denied: tool 'list-windows' has no reviewed risk classification`，
   按规程未绕过、已暂停该路径，等权限补齐后重跑。

### 2.2 尚未实现的功能（网页端有，原生端还没有）

| 领域 | 缺口 |
| --- | --- |
| **语音媒体** | macOS / Windows 已接入共享 `mediasoup-client` worker，覆盖音频、摄像头和屏幕共享的发送/接收路径；但本轮没有完成设备权限、WebRTC 网络与远端播放的端到端验收。Windows 还缺本轮 WinUI 编译与 GUI 验收。屏幕共享入口位于媒体画面内，因为浏览器要求由页面真实用户操作触发屏幕选择器。 |
| **插件 UI** | 插件 UI 在网页端是针对 `window.__SHARKORD_*` 运行的 React；当前 WebView 仅承载受限媒体页面，不加载服务器插件。原生端已能列出插件、启停、移除、看日志与能力清单，但**插件设置是只读展示**、插件能力权限编辑器未做、插件命令执行界面未做（Core 的 `executePluginCommand` 已就绪）。v1 明确不做插件 UI。 |
| **通知** | 桌面通知（`UNUserNotificationCenter`）、未读汇总、系统托盘常驻均未做；未读角标只在侧栏显示。 |
| **全局快捷键 / 按键通话** | macOS `CGEventTap`（需辅助功能权限）、Windows `RegisterHotKey` / 低级钩子，均未做。 |
| **欢迎对话框 / 服务器密码对话框** | 用「资料」设置页与连接页的密码输入近似实现，没有做成独立的模态对话框与倒计时流程。 |
| **外观** | 主题（深色 token 固定）、字号调节、无障碍（VoiceOver / 讲述人）未做。 |
| **打包与签名** | 已发布 macOS ARM64 开发 DMG（ad-hoc 签名、未公证）和 Windows x64 自包含便携 ZIP（未签名、不是 MSIX）；均无自动更新。 |

### 2.3 已知工程风险

1. **tRPC 线格式不是公开规范。** 它是 `@trpc/client` v11 的实现细节，升级上游可能破坏原生端。缓解：
   格式集中在两个文件里，并有逐字节单测；上游一旦变化，会先在这里失败。
2. **两套逻辑实现。** Swift 与 C# 各自实现一遍协议与会话，存在漂移风险。缓解：两侧单测覆盖同一组
   用例，且 C# 端的线格式测试与 Swift 端的输入/输出完全对齐。中长期按策略文档路线 (c) 引入生成式
   协议契约（`packages/protocol`）来消除重复。
3. **`Sharkord.Core` 的令牌持久化。** Core 只持有令牌；Windows 端真正落盘需要 DPAPI（`ProtectedData`），
   macOS 已用钥匙串。DPAPI 尚未接入。
4. **打包与签名。** 当前 GitHub 预览包不是面向公众的正式签名版本：macOS 未公证，Windows 未代码签名且不是 MSIX。
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

WinUI 3 外壳只能在 Windows 上构建（XAML 编译器 `XamlCompiler.exe` 是 Windows 可执行文件，
随 `Microsoft.WindowsAppSDK` 分发，构建期由 MSBuild 调用）。不需要 Visual Studio，纯 `dotnet build` 即可：

```powershell
# Windows（x64）
cd apps/windows
dotnet build src/Sharkord.App/Sharkord.App.csproj -p:Platform=x64
```

`-p:Platform=x64` 是必需的，见 [`apps/windows/README.md`](windows/README.md)。

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

- macOS：Xcode 27 / Swift 6.4（本机已有，直接复用）。无第三方 Swift 依赖；i18n 资源在
  `apps/macos/Resources/locales`，其中 8 种语言来自 `apps/client/src/i18n/locales` 的逐字节拷贝，
  `de` 与 `zh-Hant` 是原生侧自有的（网页端目前没有这两种）。
- Windows Core：.NET SDK 8.0（本机用官方 `dotnet-install.sh` 装到 `~/.dotnet`，无需 sudo）。
  `Sharkord.App` 另需 Windows App SDK（由 NuGet 还原，无需单独安装 Windows SDK）；实际构建是在一台
  Windows 11 机器上用官方 `dotnet-install.ps1` 装 .NET SDK 8.0.425 到 `%USERPROFILE%\.dotnet` 完成的。
- 两者都不进入 Bun workspace：`apps/macos` 与 `apps/windows` 下没有 `package.json`，`bun.lock` 不受影响。

---

## 五、多语言

两端原生客户端都走同一套 i18n 表，语言集合一致，共 **10 种**：

| 代号 | 显示名 | 要求 |
|---|---|---|
| `zh` | 简体中文 | 必须 |
| `zh-Hant` | 繁體中文 | 必须 |
| `en` | English | 必须 |
| `fr` | Français | 必须 |
| `es` | Español | 必须 |
| `it` | Italiano | 必须 |
| `de` | Deutsch | 必须 |
| `cs` | Čeština | 随网页端保留 |
| `ru` | Русский | 随网页端保留 |
| `pt-BR` | Português | 随网页端保留 |

后 3 种是网页端已有的，保留下来不额外花成本，需要精简时改两处
`supportedLanguages` 数组即可（`L10n.swift` 与 `L10n.cs`）。

### 覆盖范围

- **macOS**：9 个命名空间 × 10 语言，共 938 键/语言，含原生专属 `macos` 命名空间（18 键）。
- **Windows**：2 个命名空间 × 10 语言。`windows` 命名空间 9 条是 WinUI 壳专有文案
  （标语、服务器地址、服务器密码、邀请码、输入框占位、发送、系统消息作者、语言标签、跟随系统选项），
  另 3 条（`identityLabel` / `passwordLabel` / `connectBtn`）与网页端同名同义，直接读共享的
  `connect` 命名空间，不复制一份免得将来漂移。

Windows 的译表**内嵌在 `Sharkord.Core.dll`** 里（`EmbeddedResource`），不靠输出目录拷贝，
也没有运行时路径要解析。注意 MSBuild 会把资源名里的 `-` 改写成 `_`（`pt-BR` → `pt_BR`、
`zh-Hant` → `zh_Hant`），`L10n.OpenTable` 按尾部匹配资源名绕开这一点。

### 修掉的漏英文

审计发现 6 个键**在代码里真被引用**（网页端 + macOS 都用），却只有英文有，其余语言会直接显示英文：

`common.typeAMessage`、`common.messageChannel`、`settings.simulcastLabel`、`settings.simulcastDesc`、
`sidebar.simulcastLayer`、`sidebar.simulcastLayers`

`cs` / `es` / `fr` / `it` / `ru` / `zh` / `zh-Hant` 共 7 种语言缺，已补齐 42 条译文。
同样缺失的 36 条也补进了 `apps/client/src/i18n/locales`（`zh-Hant` 网页端没有），
这样将来按旧流程「网页端 → macOS 重刷」不会把补丁冲掉。

反向还有 11 个**零引用**的残留键（`ru` 的 9 个 security 键、`fr` / `ru` 的 2 个
`EXECUTE_PLUGIN_COMMANDS` 权限键），代码里查不到任何消费点，暂留不动，属于上游清理项。

### 语言判定

- macOS：`Locale.preferredLanguages` 精确匹配，再两字母回落，最后 `en`。中文单独处理，
  `zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO` 落繁体，其余中文落简体。
  不这么做的话繁体用户会被两字母回落打到简体表。
- Windows：有常驻语言选择器，可选「跟随系统」或 10 种语言。手动选择保存在
  `%LOCALAPPDATA%\Sharkord\language`，重启后保留；跟随系统时用 `CultureInfo.CurrentUICulture`，
  同样的中文规则，`pt` 归到 `pt-BR`。

### 测试

- macOS：`LocaleParityTests`（5）固定命名空间齐备与 UI 键存在性，`L10nTests`（10）固定查找、
  复数、占位符、回落与语言清单。合计 swift-testing 27 + XCTest 15 全过。
- Windows：`L10nTests` 固定译表齐备、占位符、回落、语言清单，并扫描
  `MainWindow.xaml` 确认没有硬编码文案、扫描 C# 调用点确认每个键都有定义。
  另检查显式选择的语言不被当前系统语言覆盖；最新 `dotnet test` 50/50 全过。
  WinUI 3 Release 构建已在 Windows 11 x64 实测，0 警告、0 错误；尚未启动应用做 GUI 验收。

回落到英文的行为以前靠「某语言恰好缺某个键」当测试夹具，现在补齐后夹具没了，
改用 `L10n` 的测试接缝（Swift `overrideStrings` / C# `OverrideStrings`）显式构造，
不再需要故意留一个不完整的语系表。
