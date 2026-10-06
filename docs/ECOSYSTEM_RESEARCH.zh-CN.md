# Sharkord Next — 生态现状调研
> 本文是 [`ECOSYSTEM_RESEARCH.md`](ECOSYSTEM_RESEARCH.md) 的中文翻译。英文版为权威版本，如有歧义以英文版为准。

**用途：** 盘点围绕 Sharkord 的现有第三方客户端生态、上游项目的官方立场，以及当前 Web 客户端 PWA / 移动 Web 支持的真实状态 —— 以便 Sharkord Next 能够决定在何处**贡献 / fork / 重写**，而不是盲目重建。

**证据规则：** 下文每一项论断都附带来源。条目被标注为**已核实（Verified）**（读取自一手来源：仓库元数据、源文件或命令输出）或**未确认（Unconfirmed）**（二手/README 声明，未经独立核实）。没有任何内容凭记忆断言。

| 字段 | 值 |
|---|---|
| 调研日期 | 2026-10-06 (UTC) |
| 审计的本地仓库 | `~/AWS/sharkord-next`，位于 `tims-mbp`（fork `TimmySheep/sharkord-next`） |
| Fork HEAD | `c611bb4` — `git describe` → `v0.0.25-6-gc611bb4`，分支 `development` |
| 上游 remote | `https://github.com/Sharkord/sharkord` |
| 上游状态 | ★1527，forks 138，66 个开放 issue，最后 push 2026-10-06，MIT |
| 运行 GitHub 查询的位置 | MacBook Pro，经 `gh`（账号 `TimmySheep`），代理 `127.0.0.1:7890` |
| 源码审计范围 | `apps/client/src`、`apps/client/index.html`、`apps/client/public`、`apps/server/src/http` |

---

## 0. 可执行结论（TL;DR）

1. **Android —— 不要重写。向 `Vigno04/sharkord-android` 贡献，或将其 fork。**
   它是现存*唯一*真正的原生 Android 客户端：Kotlin + Jetpack Compose、MIT、★15、8 个 release，并且已经针对上游 tRPC-over-WebSocket 协议实现了文字、私信（DM）、语音、视频和屏幕共享。从零再写一个等于重复约一年的工作，却换不来任何协议上的优势。它唯一的结构性弱点是：它是一个**独立的协议重实现，没有跟随上游的保证** —— 而这恰恰正是 Sharkord Next 可以填补的空白。
2. **macOS（Swift/SwiftUI）与 Windows（WinUI 3）确实是无人占领的。**
   不存在任何 Swift、iOS、Flutter、React-Native 或 WinUI 客户端。桌面领域挤满了约 12 个只加载 Web 应用的薄**Electron 外壳**。原生 macOS/Windows 客户端是真正的差异化，而非重复 —— 并且与 Sharkord Next 的规划相符。
3. **这个 PWA 是一份没有应用本体的 manifest。** 服务器生成了 `manifest.json` 和 `display: standalone`，但**任何地方都没有 service worker**、**没有 `viewport-fit=cover`**（因此唯一那条 `env(safe-area-inset-bottom)` 规则形同虚设），并且**没有 iOS standalone meta 标签**。这个 Web 客户端是一个恰好能塞进手机的桌面优先 SPA；它不是一个可安装、可离线的 PWA。
4. **社区对这项工作的需求在上游已有记录：** discussion **#105 "Desktop/Mobile App"**（12 条评论，活跃至 2026-08-07）是最强的单一信号，而 issue **#552 "Reconnect"** / **#778 "re-connect from a different device"** 则印证了移动/漫游的痛点。

---

## 1. 现有 Android 原生客户端

### 1.1 清单

来源：2026-10-06 的 `gh search repos "sharkord android"` + `gh api repos/<repo>`。

| 仓库 | ★ | 语言 | License | 创建于 | 最后 push | 真实客户端？ | 是否维护？ |
|---|---|---|---|---|---|---|---|
| **Vigno04/sharkord-android** | 15 | Kotlin | MIT | 2026-05-22 | 2026-08-11 | **是** —— 完整原生 | 是（8 个 release，issue 有分诊） |
| martintondel02/sharkcordclient | 0 | Rust | MIT | 2026-08-20 | 2026-08-20 | 愿景性质（未落地） | 否 —— 单日爆发式提交 |
| thalisonnunes20/apk-sharkord | 0 | HTML | MIT | 2026-08-24 | 2026-08-24 | 未确认（WebView 外壳？） | 未知 |
| KillerAuzzie/brozantine-sharkord-android | 0 | — | none | 2026-08-07 | 2026-08-07 | 否 —— APK 下载镜像 | 无源码 |
| rf4burns/Kurier-Android-Installer | 0 | — | none | 2026-09-07 | 2026-09-07 | 否 —— 某个*fork*（Brozantine/Kurier）的安装器 | 否 |

### 1.2 `Vigno04/sharkord-android` —— 深入剖析

**已核实（Verified）—— 身份与维护状态**

- `gh api repos/Vigno04/sharkord-android` → MIT、Kotlin，创建于 2026-05-22，`pushed_at` 2026-08-11，0 forks，1 个开放 issue。
- Releases（`gh api .../releases`）：`v0.1.1` 2026-06-30 → `v0.1.2` 07-09 → `v0.1.3` 07-20 → `v0.1.4` 07-24 → `v0.1.5` 07-27 → `v0.1.6` 07-30 → `v0.1.7` 08-07 → **`v0.2.0` 2026-08-11**（每个各 1 个 APK 资产）。节奏先是每周一次，随后在 v0.2.0 停止（距本次调研约 2 个月）。
- 提交日志（`gh api .../commits`）显示真实的特性/修复流：*"Fix Android 14+ FGS crash on screen share"*、*"extracted all hardcoded strings to fix #6"*、*"Merge develop into main for v0.2.0 release"*。
- Issue tracker：13 个 issue，**12 个已关闭**，1 个开放 —— issue **#12 "Publish the app on F-Droid or IzzyOnDroid"**。F-Droid 的基础工作已入树（`fastlane` 元数据提交；*"Remove foojay-resolver for F-Droid compliance"*）。

**已核实（Verified）—— 技术栈**

- `app/build.gradle.kts`：`alias(libs.plugins.kotlin.compose)`、`buildFeatures { compose = true }`、`namespace com.sharkord.android`、**minSdk 28，targetSdk 36**、`versionName "0.2.0"`。
  → **Kotlin + Jetpack Compose**，现代化 SDK 目标（Android 15/16 时代）。
- 源码树（`git/trees?recursive=1`）证实其广度：
  - 网络/协议：`TrpcProtocol.kt`、`WebSocketManager.kt`、`SharkordClient.kt`、`ServerEventHandler.kt`、`HttpClient.kt`、`ParallelDownloader.kt`
  - 媒体：`VoiceEngine.kt`、`VideoEngine.kt`、`VoiceService.kt`（前台服务）、`audio/SoundEngine.kt`、`StreamKind.kt`
  - 数据/会话：`SessionManager.kt`、`MessageSyncWorker.kt`、`ChatRepository.kt`、`ServerRepository.kt`
  - UI：Compose UI + 一个从零实现的 `ui/emojipicker/`（带 test tags）。
- 因此范围 = **文字频道、私信、语音、视频、屏幕共享、emoji、后台消息同步、Android 前台服务语音** —— 即就移动端用例而言，功能与 Web 客户端相当。

**评估**

| 维度 | 结论 | 证据 |
|---|---|---|
| 真实原生（无 WebView） | **已核实：是** | Compose 插件 + tRPC/WebSocket/媒体 Kotlin 源码 |
| 仍在维护 | **部分** | 6 月至 8 月 11 日稳定每周发版，之后安静了约 2 个月 |
| 上游 API 兼容 | **未确认** | README 只说 "connect to a Sharkord server"；它自行重实现了 `TrpcProtocol.kt`，未声明固定的上游版本 |
| License 适合在其上构建 | **已核实：是** | MIT（与上游相同） |
| 可贡献就绪 | **是** | 有 issue/PR 模板、CONTRIBUTING.md、release 工作流 |

> 注：Vigno04 还维护 **`Vigno04/discord-selfhosted-alternatives`**（★148）—— 该作者是生态级别的参与者，而非路过的开发者。这提高了做出有效上游贡献的可能性。

### 1.3 建议 —— Android

**先贡献，fork 作为退路。不要重写。**

| 选项 | 何时选择 | 理由 |
|---|---|---|
| **向 `Vigno04/sharkord-android` 贡献** | 默认 | Compose + MIT + 语音/视频/屏幕共享都已完成。跟随上游的兼容性追踪与 PWA 对齐的 UX 是缺失的部分，且都是 PR 量级。这是通向可信 Android 客户端的最快路径。 |
| **将其 fork 为 `sharkord-next`** | 如果维护者不回应，或 fork 需要走一条不同的设计路线（例如共享的 Rust/Kotlin 协议核心、统一品牌、上游版本固定 + CI 兼容测试） | MIT 允许这样做；但你会继承一个必须持续维护的 Kotlin 代码库。 |
| **从零重写** | 仅当共享的跨平台核心（例如 Rust 的 `martintondel02` 式方案）是硬性架构要求时 | 丢弃可用的媒体/会话代码；没有协议上的优势。 |

**不要依赖 `martintondel02/sharkcordclient`**：其 README 宣传 *"Android (Kotlin + Jetpack Compose)"*，但实际树里**只有 `core/`（Rust）和 `desktop/`（egui）** —— **没有 Android 模块**。全部 8 个提交都落在同一天（2026-08-20）。当作路线图看待，而非代码。

---

## 2. 其他平台的第三方客户端（iOS / macOS / Windows / 桌面 / CLI）

### 2.1 清单

来源：对 `sharkord ios|swift|kotlin|flutter|react native|mobile|cli|desktop|pwa` 执行 `gh search repos` + `gh api search/repositories?q=topic:sharkord`。**对 `sharkord ios`、`sharkord swift`、`sharkord flutter`、`sharkord react native`、`sharkord mobile`、`sharkord cli`、`sharkord pwa` 的查询均返回零个独立的客户端仓库。**

| 仓库 | 平台 | 技术栈 | ★ | License | 最后 push | 范围 | 结论 |
|---|---|---|---|---|---|---|---|
| **Bugel/sharkorddesktop** | Win/Linux/mac | Electron | 15 | MIT | 2026-10-02 | 多服务器、服务器面板、社区、客户端输入/PTT | **最活跃的桌面客户端** |
| agrisci/sharkord-client | Win/Linux | Electron | 1 | MIT | 2026-10-03 | 加载 Web 应用 + 4K60 硬件编码屏幕共享、系统音频、托盘、自动更新 | 活跃 |
| RND332/sharkord-desktop | Linux/Win/mac | Electron | 0 | MIT | 2026-10-04 | 整机音频（去除自身）；AI 生成（"vibecoded"） | 活跃，实验性 |
| captsmuckers/brewer | Linux/Win | Electron | 2 | none | 2026-09-12 | 多服务器侧栏、按服务器独立会话、未读计数 | 活跃 |
| reef-sharkord/reef | 桌面 | TS (+ server plugin) | 3 | MIT | 2026-08-27 | **Sharkord 客户端的分支**：多服务器大厅、统一收件箱、PTT、已保存消息 | 活跃，范围最大 |
| Cyphersphere/Sharkord-Client | Windows | Electron | 3 | none | 2026-06-01 | 薄壳 + PTT + 快捷键 | 半活跃 |
| Erebaran/SharkordAPP | 桌面 | Electron | 1 | none | 2026-08-26 | 薄壳 | 信号弱 |
| martintondel02/hammerhead | 桌面 | **Tauri 2** | 0 | none | 2026-09-12 | "原生桌面客户端"（Tauri 外壳） | 新，未经证实 |
| cr1gger/sharkord-desktop-client | Win/Linux/mac | Electron | 0 | none | 2026-07-19 | 薄壳 | 停滞 |
| GoldcrafterXD/sharkord-client | 桌面 | Electron | 1 | GPL-3.0 | 2026-02-27 | 薄壳 | 停滞 |
| pixelsdontmove/sharkord-thinfin | 桌面 | Electron | 1 | GPL-3.0 | 2026-02-16 | "Cartilage-only" 薄客户端 | 停滞 |
| Ricisss/sharkord-meta-client | 桌面 | TS | 1 | MIT | 2026-03-04 | 多服务器元客户端 | 停滞 |
| Sweets-omg/Sweetshark-client | 桌面 | Electron | 0 | none | 2026-02-24 | "AI 编码"，概念验证 | 停滞 |
| thalisonnunes20/app-sharkord | Windows | Electron | 0 | MIT | 2026-09-09 | 编外 Windows 应用 | 信号弱 |
| kanuracer/sharkord-desktop-releases | — | — | 0 | none | 2026-07-20 | 仅 release 镜像 | 不适用 |

### 2.2 这张表说明了什么

- **桌面端已被薄 Electron 外壳塞满** —— 它们不重实现协议，只加载现有的 Web bundle。这正是上游明确选择 *"browser + self-host server"* 作为官方桌面方案的原因。
- **不存在任何 iOS、原生 macOS、Swift、Flutter、React-Native 或 CLI 客户端。** 唯一的非 Electron 桌面尝试是 `martintondel02/hammerhead`（Tauri 2，创建于 2026-09-12，0 star —— 未经证实）。
- **与 Sharkord Next 规划相符的无人占领领域：**
  - **macOS —— Swift/SwiftUI**（零先例）
  - **Windows —— C# WinUI 3**（零先例；所有 Windows 客户端都是 Electron）
  - **iPhone/iPad —— 一个统一的 Apple Mobile 目标**（零先例）
- **未确认：** 是否有任何 Electron 外壳做了 PTT/音频采集之外的有意义协议工作。README 描述的都是外壳；本轮未核实到任何协议重实现。

---

## 3. 上游官方状态

来源：`gh api repos/Sharkord/sharkord`、`.../releases`、`.../labels`、GraphQL `discussions`、`gh issue list`，以及该 fork 的 README/ROADMAP。

### 3.1 项目本身

| 字段 | 值（2026-10-06 已核实） |
|---|---|
| Stars / forks | 1527 / 138 |
| License | MIT |
| 语言 | TypeScript |
| 创建于 | 2025-10-14 |
| 最后 push | 2026-10-06（提交活跃） |
| 开放 issue | 66 |
| 分发方式 | 打包**服务器 + 客户端**的独立二进制，另有 Docker 镜像 `sharkord/sharkord` |

### 3.2 官方客户端形态：仅 Web

**已核实**，来自上游 README（fork 的树中同样存在）：

- *"Sharkord is distributed as a standalone binary that bundles both server and client components."*
- *"Once the server is running, open your web browser and navigate to `http://localhost:4991` to access the Sharkord client interface."*
- 树内客户端技术栈：React + Vite + Redux Toolkit + Tailwind，i18n（fork 的树中有 8 种 locale：`cs, en, es, fr, it, pt-BR, ru, zh`），用于语音/视频的 mediasoup 客户端。
- **没有官方的原生桌面或移动客户端。** "桌面"方案*就是*浏览器。

### 3.3 发布节奏

`gh api .../releases`：

| Tag | 发布时间 |
|---|---|
| v0.0.25 | 2026-09-04 |
| v0.0.24 | 2026-08-27 |
| v0.0.23 | 2026-07-10 |
| v0.0.22 | 2026-05-22 |
| v0.0.21 | 2026-05-22 |
| v0.0.20 | 2026-05-13 |

→ 到 v0.0.24 大致每月一次，随后**在提交每日持续的同时约 1 个月没有发版**（最后 push 2026-10-06）。按项目自己的说明（*"Sharkord is in alpha stage… breaking changes are to be expected"*）仍处于 alpha 阶段。发版放缓对任何第三方客户端都是真实的兼容性风险。

### 3.4 插件生态

**已核实** —— 官方组织仓库：`Sharkord/plugins`、`Sharkord/plugin-example`、`Sharkord/music-bot`、`Sharkord/iptv`、`Sharkord/klipy`、`Sharkord/website`（全部 push 于 2026-09-04…26），另有位于 `packages/plugin-sdk` 的 monorepo 内 SDK。issue 标签包括 **`plugin-sdk`** 和 **`good first issue`**。

社区插件（仓库均经搜索核实）：`rinky-dinky/sharkord-soundboard`、`remynaps/sharkord-whip-plugin`、`diogomartino/sharkord-music-bot`、`diogomartino/sharkord-iptv`、`Salaron/sharkord-lava-plugin`、`sponger544/sharkord_ai_plugin`、`EssekerDev/sharkord-rss`、`Popoboxxo/sharkord-CastMate`、`degyster/sharkord-extensions`、`0x6DD8/discord-sharkord-bridge`。
社区索引：`Sweets-omg/sharkord-community-creations`（★6，社区维护，明确**"not reviewed, audited, or endorsed"**）。

> **原生客户端的架构注意事项（来自 `martintondel02` README，源码层面未核实）：** 上游插件系统"在进程内加载 JS/React bundle"，原生客户端无法承载这一点。若得到确认，任何原生客户端都会**不带**插件支持地发布 —— 这是范围决策，不是 bug。

### 3.5 官方路线图

`ROADMAP.md`（fork 镜像上游）：短期 = *核心功能与稳定性、QoL、bug 修复、扩展插件 SDK、文档/DX*。**中期 = TODO。长期 = TODO。**
→ **没有公开的官方原生移动/桌面计划。**

### 3.6 社区关注度证据（最活跃的讨论串）

| 讨论串 | 类型 | 评论数 | 最后活动 | 链接 |
|---|---|---|---|---|
| **Desktop/Mobile App** | Discussion（Ideas） | **12** | 2026-08-07 | https://github.com/Sharkord/sharkord/discussions/105 |
| Sharkord is not actively releasing any updates anymore? | Discussion | 5 | 2026-08-07 | https://github.com/Sharkord/sharkord/discussions/760 |
| Firefox Issues | Discussion | 5 | 2026-09-25 | https://github.com/Sharkord/sharkord/discussions/449 |
| **#552 [Feature]: Reconnect** | Issue（`feature,future`） | 2 | 2026-03-17 | https://github.com/Sharkord/sharkord/issues/552 |
| #778 [Feature]: Allow re-connect from a different device when in voice | Issue（`feature`） | 0 | 2026-08-08 | https://github.com/Sharkord/sharkord/issues/778 |
| #756 webrtc: announcedAddress hostname breaks Firefox (ICE) | Issue（`bug`） | 10+ | 2026-08-28 | https://github.com/Sharkord/sharkord/issues/756 |
| #695 Audio input stops after ~10s (UDP 40000 / proxy) | Issue（`bug`） | 10+ | 2026-08-05 | https://github.com/Sharkord/sharkord/issues/695 |
| #785 RTL text support (Arabic/Persian) | Issue（`feature`） | 0 | 2026-08-19 | https://github.com/Sharkord/sharkord/issues/785 |

Discussion #105 正文（逐字引用，已核实）：*"Could this easily be wrapped in a capacitor app and or electron app? Authentication process would be similar to a plex or jellyfin server and could even hold multiple 'servers'… If anyone is interested I could give this a shot as well, not sure if the developers would want this under their own repo."*

---

## 4. 当前 Web 客户端 —— PWA / 移动 Web 审计

方法：直接检视 fork 的工作树（`apps/client`、`apps/server/src/http`）；未做运行时测试 —— 所有状态均为**来源已核实（source-verified）**。

### 4.1 PWA 各部件所在位置

- `apps/client/index.html:6` → `<link rel="manifest" href="/manifest.json" />`
- `apps/server/src/http/index.ts:82` → 注册路由 `'/manifest.json': manifestRouteHandler`
- `apps/server/src/http/manifest.ts` → **manifest 在运行时生成**，不是静态文件
- `vite.config.ts` 在开发环境中将 `/manifest.json` 代理到 dev server
- `apps/client/public/` → 只有 `favicon.ico`、`icon-192.png`、`icon-512.png`、`logo.webp`、`robots.txt` 以及 audio worklet。**没有 `sw.js`、没有 `workbox`、没有 `manifest.webmanifest`。**

### 4.2 Manifest 内容（已核实，`apps/server/src/http/manifest.ts`）

```
name:             settings.name
short_name:       settings.name.slice(0, 12)
description:      settings.description ?? ''
start_url:        '/'
display:          'standalone'
background_color: '#171717'
theme_color:      '#171717'
icons:            /icon-192.png + /icon-512.png  (or the server logo if square; SVG allowed)
```
以 `application/manifest+json`、`Cache-Control: public, max-age=3600` 提供。

**缺失字段：** `scope`、`id`、`orientation`、`categories`、`screenshots`、`dir`、`lang`、`prefer_related_applications`，以及任何带 `purpose: "maskable"` 的图标。

### 4.3 逐项状态

| 项目 | 状态 | 证据 / 文件 |
|---|---|---|
| Manifest 在 HTML 中链接 | **已实现** | `apps/client/index.html:6` |
| Manifest 以正确类型提供 | **已实现** | `apps/server/src/http/manifest.ts:103-106` |
| `start_url` + `display: standalone` | **已实现** | `manifest.ts:95-96` |
| Manifest 完整性（id/screenshots/scope/orientation） | **未实现** | `manifest.ts` 中缺失 |
| **Service worker（离线、预缓存、运行时缓存）** | **未实现** | 在 `apps/client/src`、`apps/server/src`、`packages` 中 `serviceWorker`/`workbox`/`registerSW` 零匹配；`dist/` 中无 `sw.js` |
| **应用关闭时的 Web Push** | **未实现** | 只用了 Notifications API（`features/app/actions.ts:153-179`、`helpers/assert-notifications-permission`）；没有 `PushManager` |
| PWA 安装提示处理 | **未实现** | 客户端源码中没有 `beforeinstallprompt` / `display-mode` / standalone 检测 |
| `viewport-fit=cover` | **未实现** | `index.html:7` 仅有 `width=device-width, initial-scale=1.0` |
| iOS standalone（`apple-mobile-web-app-capable`） | **未实现** | 全仓库零匹配 |
| iOS 主屏标题 / 图标 | **已实现（运行时）** | `features/app/actions.ts:62-63` 设置 `apple-touch-icon` + `apple-mobile-web-app-title` |
| iOS 启动画面 / 状态栏样式 | **未实现** | 无 `apple-touch-startup-image`，无 `status-bar-style` |
| 安全区（safe-area）insets | **部分 / 形同虚设** | 仅 `message-compose/index.tsx:263` 的 `pb-[env(safe-area-inset-bottom)]`；没有 `viewport-fit=cover` 时无效 |
| 动态视口高度 | **已实现** | `h-dvh`，见 `screens/server-view/index.tsx:85` 与 `server-screens/settings-shell/index.tsx:102` |
| 混用固定视口单位 | **部分** | `index.css:141` `#root { min-height: 100vh }` |
| 触摸滑动手势 | **已实现（范围窄）** | `hooks/use-swipe-gestures.ts`，仅在 `screens/server-view/index.tsx:66` 接入 |
| 触摸滚动 / overscroll / tap-highlight 调优 | **未实现** | 无 `touch-action` / `overscroll-behavior` / `user-select` 规则 |
| 响应式断点 | **部分（稀疏）** | client/src 工具类计数：`md:` ×23、`lg:` ×18、`sm:` ×16、`xl:` ×1；仅一条定制媒体查询 `@media (max-width:700px)`（`index.css:447`，仅 masonry 网格） |
| 移动导航外壳 | **已实现** | `server-view/index.tsx` 中的覆盖式抽屉（`md:hidden` / `lg:hidden` 背景遮罩，`isMobileMenuOpen` / `isMobileUsersOpen`） |
| 重连 | **已实现** | `features/server/actions.ts:135` `RECONNECT_DELAYS_MS = [1000,2000,4000,8000,8000]`，以及 reconnect slice/selectors |
| 刷新后的状态恢复 | **已实现（部分）** | `helpers/storage.ts` `LocalStorageKey`（主题、通知、会话）；没有 service worker 级别的状态 |
| i18n | **已实现** | 8 种 locale：`cs, en, es, fr, it, pt-BR, ru, zh` |

### 4.4 解读

- 该客户端是**一个桌面优先的 SPA，可降级为可用的手机布局** —— 不是 PWA。manifest 中的 `display: standalone` 并不是这个应用能兑现的承诺，因为不存在 service worker，且在 iOS 上没有 `apple-mobile-web-app-capable`。
- 在 **iOS Safari** 上的后果："Add to Home Screen" 产生的是 Safari UI 快捷方式，而不是独立应用外壳。在非 `cover` 的视口上，`safe-area` inset 求值为 `0`，因此那唯一一条安全区规则目前在刘海设备上不起任何作用。
- 在 **Chromium** 上的后果：没有 service worker、没有 `id`、没有 `screenshots`，更丰富的安装提示就不可靠；用户实际得到的是 "Create shortcut"。完全没有离线行为。
- 审计所对应到的三个用户可见痛点，正是规划已经瞄准的那三个：**安装/离线、安全区/状态栏、触摸密度。**

---

## 5. 建议

### 5.1 Android —— **向 `Vigno04/sharkord-android` 贡献**

| 为什么贡献 | 为什么不重写 | 何时 fork |
|---|---|---|
| 现存唯一真正的原生 Android 客户端；Compose + MIT；语音/视频/屏幕共享/私信/emoji/后台同步均已实现并每周发版（直到 v0.2.0）。 | 重实现 tRPC-over-WS 协议 + mediasoup 移动客户端等于重复数月工作，却无协议优势。 | 若 (a) 维护者不回应、(b) 你需要共享的跨平台核心，或 (c) 你需要当前项目不会采纳的硬性上游版本固定 + CI 兼容测试，则 fork。 |
| 具体缺口都是 PR 量级且契合 Sharkord Next 目标：上游版本固定 + 兼容 CI、F-Droid 发布（#12）、重连对齐、PWA 对齐的 UX。 | `martintondel02` 的"共享 Rust 核心"方案目前**没有 Android 模块** —— 它是路线图，不是基础。 | MIT license 使 fork 在法律上干净。 |

### 5.2 macOS / iOS / Windows —— **做原生，这里无人占领**

- 不存在任何 Swift/SwiftUI、iOS、Flutter、React-Native 或 WinUI 3 客户端（已核实搜索清扫）。
- 桌面领域约 12 个 Electron 外壳，而上游刻意不与它们竞争。
- 因此 **一个统一的 Apple Mobile 项目（iPhone+iPad）+ 一个 SwiftUI macOS 客户端 + 一个 C# WinUI 3 Windows 客户端**是增量而非重复 —— 并且是这个生态中最强的差异化押注。其中任何一个的协议入口都是 `tRPC`-over-WebSocket + HTTP 文件上传 + mediasoup 信令（与 `Vigno04` 和 `martintondel02` 原生实现的同一套接口面）。

### 5.3 PWA —— 三个最大缺口，按优先级排序

| # | 缺口 | 为什么重要 | 具体修复 |
|---|---|---|---|
| 1 | **没有 service worker**（全仓库 `serviceWorker` 零匹配；`dist/` 中无 `sw.js`） | 没有离线外壳、没有预缓存、应用关闭时没有 Web Push、安装提示不可靠。这是"可安装应用"与"书签"之间的区别。 | 添加 Workbox/Vite-PWA service worker：预缓存应用外壳 + 带哈希的资源，运行时缓存静态媒体，在 `main.tsx` 中注册；接入 `PushManager` 实现后台通知。 |
| 2 | **没有 `viewport-fit=cover` + 仅一条形同虚设的安全区规则**（`index.html:7`；`message-compose/index.tsx:263`） | 在刘海 iPhone 上，底部输入框会被压在 home indicator 之下；键盘/刘海重叠。`env(safe-area-inset-*)` 目前求值为 `0`。 | 将 meta 改为 `width=device-width, initial-scale=1.0, viewport-fit=cover`；为外壳（`server-view`、`settings-shell`、topbar）加上 top/left/right 的安全区 padding。 |
| 3 | **没有 iOS standalone meta / 移动布局稀疏**（无 `apple-mobile-web-app-capable`；只有 58 个断点工具类，面对的却是一个桌面优先的外壳；无 `touch-action`/`overscroll-behavior`） | iOS 的 "Add to Home Screen" 会在 Safari 浏览器框架中打开，而不是应用外壳；触摸目标与滚动链未经调优。 | 添加 `apple-mobile-web-app-capable=yes` + `status-bar-style` + `apple-touch-startup-image`；提高 topbar/侧边栏的移动断点覆盖；在滚动容器上添加 `touch-action`/`overscroll-behavior: contain`。 |

### 5.4 社区在哪里 —— 先去这里

1. **Discussion #105 "Desktop/Mobile App"** — https://github.com/Sharkord/sharkord/discussions/105
   （12 条评论，该主题上参与度最高的单一讨论串；上游尚未对其表态）。
2. **Issue #552 "Reconnect"**（`feature,future`）— https://github.com/Sharkord/sharkord/issues/552
   以及 **Issue #778** — https://github.com/Sharkord/sharkord/issues/778（移动/漫游重连）。
3. **对移动端影响最大的语音/网络 bug**：#756（ICE/FQDN）、#695（经代理的 UDP :40000）、#795（Firefox 屏幕共享黑屏）—— 这些决定了一个移动客户端在离开 Wi-Fi 时是否可用。

---

## 6. 方法与可复现性

所用命令（在 `tims-mbp` 上运行，已导出代理）：

```bash
export HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890
export PATH=/opt/homebrew/bin:$PATH
# ecosystem sweep
gh search repos "sharkord android|ios|swift|kotlin|flutter|react native|mobile|cli|desktop|pwa"
gh api "search/repositories?q=sharkord+in:name,description,readme&sort=stars&per_page=60"
gh search repos --topic sharkord-plugin
# per-repo facts
gh api repos/<owner>/<repo>            # stars, license, pushed_at, archived
gh api repos/<owner>/<repo>/commits    # recency + intent
gh api repos/<owner>/<repo>/releases   # cadence
gh api "repos/<owner>/<repo>/git/trees/HEAD?recursive=1"   # real stack (quote the URL!)
# upstream
gh api repos/Sharkord/sharkord
gh api "repos/Sharkord/sharkord/releases?per_page=12"
gh api graphql -f query='{repository(owner:"Sharkord",name:"sharkord"){discussions(first:25,...){...}}}'
gh issue list --repo Sharkord/sharkord --state open --limit 40
# local source audit
grep -rniE "serviceWorker|workbox|registerSW" apps/client/src apps/server/src packages
grep -rniE "viewport|safe-area|apple-mobile-web-app|touch-action|overscroll" apps/client/src apps/client/index.html
cat apps/server/src/http/manifest.ts
```

**已遵守的约束：** 未修改任何上游源码，未执行 `git commit`/`push`，位于 `/home/timmy/sharkord` 的生产 Docker 实例未被触碰。整个过程工作树为只读。

### 开放 / 未确认项

- **未确认：** `Vigno04/sharkord-android` 是否针对某个特定上游版本做固定或测试（其 README 未提及；未找到兼容性声明）。
- **未确认：** 插件运行时是否真的无法由原生客户端承载（仅为 `martintondel02` README 的说法），以及真实 Chrome/Safari 设备上的确切安装提示行为（仅做了源码级分析；未做设备测试）。
- **未确认：** 是否有任何 Electron 外壳做了 PTT/音频采集之外的协议工作。
