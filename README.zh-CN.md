# Sharkord Next

**Sharkord Next 是一个基于 [Sharkord](https://github.com/Sharkord/sharkord) 的非官方社区项目。**
它与 Sharkord 项目及其维护者之间没有隶属、背书或支持关系。通用性修复与改进会回流给上游。

**语言：** [English](README.md) | 中文

一个轻量、可自托管、类 Discord 的实时通信平台（文字 + 语音），目标是**真正的原生客户端**，而不是套着网页的 Electron 壳。

[![CI](https://github.com/TimmySheep/sharkord-next/actions/workflows/ci.yml/badge.svg)](https://github.com/TimmySheep/sharkord-next/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/TimmySheep/sharkord-next)](LICENSE)

---

## 我们打算做什么（以及不做什么）

以下是本项目自己的计划，**按优先级排列**。**"原生"是重点**：这个生态里现存的桌面客户端都是加载网页的 Electron 套壳，本项目要做的是与服务端直接通信的**真原生应用**。

### 1. macOS 原生（第一优先）

Swift + SwiftUI，必要时用 AppKit。**不用 Electron，不嵌 web view，不套壳网页客户端**。要做真正的系统集成：菜单栏常驻、全局按键说话（push-to-talk）热键、原生屏幕捕获（ScreenCaptureKit）、系统音频。先文字，后语音。
设计与依据：[`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md)

### 2. Windows 原生（第二）

C# + WinUI 3，原生。先做文字。**语音要先过可行性验证**，因为**目前不存在任何 C# 的 mediasoup 客户端** —— 这是研究课题，不是一个任务。要做系统托盘、全局热键、WASAPI 音频、Windows.Graphics.Capture。
设计与依据：[`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md)

### 3. iPhone + iPad 原生（第三）

统一的一个 Apple 工程，Swift + SwiftUI，复用 macOS 那边本来就要写的 Swift 核心。语音、APNs 通知、后台行为。**先做 macOS 会让这一步更省而不是更晚。**
设计与依据：[`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md)

### 4. Apple Watch 原生（已声明，需先过可行性验证）

一个只做**腕上对讲机**的客户端：**进入**一个语音频道、**按住说话**、**听到频道**、**退出**。不做文字，一次只在一个频道 —— 重点就是形态本身，因为按键说话（push-to-talk）是唯一一种"手表比手机更顺手"的通话方式。

**这是"已声明的意图"，不是承诺。** watchOS 只允许第三方 App 在极窄的例外条件下使用低层网络（[TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)），而本设计依赖的"音频流例外"目前带着一个 Apple 已登记在案的缺陷（**FB24377808**，报告于 2026-08）：音频会话激活后约 36 秒网络路径被收回、不会自行恢复，所以必须**定时续期**才能把连接握着。社区里已经有一个绕过办法 —— 在到期前重新激活，收回就会被重新排程（据报告者实测，且不打断路径与已建立的连接）—— 但它**没有在真实音频下验证过**，也**没有在 watchOS 27 发布后复测过**。因此在 watchOS 上能否维持一个持续的语音会话，是本项目要**先在真机上量出来的第一件事 —— 在任何 UI 动手之前**。如果答案是"不行"，我们会直接写在这个 README 里，而不是发布一个每半分钟卡一次的东西。
设计与一手证据、验证计划：[`docs/APPLE_WATCH.zh-CN.md`](docs/APPLE_WATCH.zh-CN.md)

### 不做：Android

Kotlin 原生客户端**已经存在** —— [`Vigno04/sharkord-android`](https://github.com/Vigno04/sharkord-android)（Kotlin + Jetpack Compose，MIT，已实现文字、私信、语音、视频、屏幕共享）。再写一个等于重复别人一年的工作，不推进任何事。

### 不做：本仓库不做 PWA / 移动端网页

网页客户端的三处缺口（没有 service worker、没有 `viewport-fit=cover`、没有 iOS standalone meta）是**上游客户端的通用改进**。改在上游，**所有自建实例和所有第三方客户端都受益**；改在这里，只有我们受益。所以我们把它**向上游提议**，不在这里自己做：见 [Track 6](ROADMAP.zh-CN.md)。

### 另外还有：P2P 直连语音

目前**所有媒体都经服务器转发**，所以自建者的上行带宽就是天花板。为 1:1 通话提供直连路径（服务器转发作为兜底）属于 [Track 5](ROADMAP.zh-CN.md)。

| 平台 | 决定 | 理由 |
| --- | --- | --- |
| **macOS**（原生，Swift） | **做** —— 第一优先 | 无人占位；现有桌面端全是 Electron 套壳 |
| **Windows**（原生，WinUI 3） | **做** —— 第二 | 无人占位；先文字，语音过验证 |
| **iPhone + iPad**（原生，Swift） | **做** —— 第三 | 无人占位；复用 macOS 本来就要写的 Swift 核心 |
| **Apple Watch**（原生，Swift） | **已声明** —— 需先过验证 | 腕上按键说话是"语音频道变成对讲机"的形态；watchOS 的网络限制尚未解决 |
| **Android** | **不做** | 已有 Kotlin/Compose 原生客户端 |
| **PWA / 移动端网页** | **向上游提议** | 通用改进，改在上游才能惠及所有实例 |
| **网页客户端** | 保留，作为参考客户端 | 它是所有客户端的兼容基线 |

## 当前状态

**地基阶段。** 本仓库目前是上游 `Sharkord/sharkord` 的忠实副本，基线提交 `c611bb4`（`v0.0.25` 之后 6 个提交），**完整保留了上游的 git 历史**。服务端与参考网页客户端**没有做任何行为改动** —— 那部分就是上游代码；[`apps/`](apps/) 下的原生客户端是本项目自己的新增内容。和上游一样，整体处于 **alpha**：会有 bug、未完成功能和破坏性变更。

| 部分 | 状态 |
| --- | --- |
| 服务端（`apps/server`） | 上游代码，未改动。可构建、可运行；**1458 个服务端测试通过** |
| 参考网页客户端（`apps/client`） | 上游代码，未改动。可构建、可运行（Vite 7.3.1） |
| 原生客户端 | **已开始** —— macOS 与 Windows 的客户端源码已在 [`apps/`](apps/) 下（状态见各自的 README）；Apple Watch 已声明，需先过可行性验证（见上） |
| 文档 | 架构、RTC、生态调研、原生策略四份都在 [`docs/`](docs/) |

## 服务端已经具备的能力

以下全部是上游的功能，未做改动 —— 写出来是为了明确这个副本继承了什么：

- **语音频道**，含视频与屏幕共享，基于内置的 mediasoup SFU
- **文字频道**，支持分类、主题串、回复、表情回应、置顶与搜索
- **私信**（成员之间）
- **角色与权限**，支持按频道对角色和用户单独覆盖
- **自定义表情**、@提及 与频道引用
- **邀请链接**，带使用次数限制与自动赋角色
- **文件上传**，带每用户存储配额与可选的签名 URL
- **插件**，通过 [plugin SDK](packages/plugin-sdk) 同时扩展服务端与客户端

## 为什么要做一个 fork

上游做得不错，我们希望保持可合并（mergeable）。做这个 fork 是因为今天有三件事成立（[证据](docs/ECOSYSTEM_RESEARCH.zh-CN.md)）：

1. **没有原生桌面端或移动端客户端。** 上游只有网页客户端；社区关于桌面/移动应用的讨论从 2026-02 开到现在都没有承诺（[#105](https://github.com/Sharkord/sharkord/discussions/105)）。桌面侧存在的都是 Electron 套壳。
2. **网页客户端是"桌面优先"的单页应用**，不是可安装的应用：没有 service worker、没有 `viewport-fit=cover`、没有 iOS standalone meta。（[审计](docs/ECOSYSTEM_RESEARCH.zh-CN.md)）
3. **媒体只走服务器转发（SFU）。** 自建者最先用尽的就是带宽，而且没有 1v1 直连选项。（[RTC 架构](docs/RTC_ARCHITECTURE.zh-CN.md)）

## 快速开始

服务端是单一进程（Bun + mediasoup，一个 SQLite 文件，无外部数据库），同时提供 API 和网页客户端。

> [!WARNING]
> 首次启动时，服务端会生成一个**所有者令牌（owner token）**并打印到控制台。它既是**授予所有者权限的凭据**，也是**签发所有会话与文件 URL 的密钥** —— 拿到它的人**既能夺取所有权，也能冒充任意账号**。不要让它进入日志、截图或 issue 报告，妥善保存，且不要丢失。

**方式 A：上游的独立二进制（最快试用）**。上游提供 Linux、macOS、Windows 的单文件二进制，把服务端和客户端打包在一起：

```bash
# Linux x64 —— 来自 https://github.com/Sharkord/sharkord/releases
curl -L https://github.com/Sharkord/sharkord/releases/latest/download/sharkord-linux-x64 -o sharkord
chmod +x sharkord && ./sharkord
```

本仓库**尚未发布自己的二进制**，而且当前代码与上游完全一致，所以用上游的发行版就是试同一个东西。

**方式 B：Docker（自托管推荐）**

```bash
# 使用本仓库的 Dockerfile 自行构建（本 fork 目前未发布镜像）
docker build -t sharkord-next .

docker run -d --name sharkord-next \
  -p 4991:4991/tcp \
  -p 40000:40000/tcp -p 40000:40000/udp \
  -v "$PWD/data:/home/bun/.config/sharkord" \
  -e PUID=1000 -e PGID=1000 \
  sharkord-next
```

然后打开 <http://localhost:4991>。首次启动时所有者令牌会打印在日志里 —— 从 `docker logs sharkord-next` 取走并妥善保存；有些部署场景更适合不让它落到日志里。

**方式 C：从源码构建运行**，见下面「从源码开发」。

**关键端口**

| 端口 | 协议 | 用途 |
| --- | --- | --- |
| `4991` | TCP | 网页界面、REST、tRPC、WebSocket 信令 |
| `40000` | UDP（+TCP） | WebRTC 媒体（mediasoup） |

**放在隧道 / 反向代理后面时**：网页与信令走 TCP，媒体走 UDP。几乎每一例"语音连不上"都出在下面两条：

1. **媒体端口两端必须一致**（`local_port == remote_port`），因为 mediasoup 通告的是自己的监听端口。
2. **通告的媒体地址必须让客户端能到达**。通过 `SHARKORD_WEBRTC_ANNOUNCED_ADDRESS`（对应配置项 `webRtc.announcedAddress`）设置；否则上游会回退到探测到的公网 IP，在走中继时可能是错的。

环境变量只在运行时生效，**不会回写**到 `config.ini`，所以请把它们保存在 `compose.yml` / 服务定义里，并把容器当作可随时重建的。

## 从源码开发

**前置条件**

- **Bun `1.3.14`** —— 上游 CI（`.github/workflows/ci.yml`）与 `package.json` 的 `@types/bun` 都钉在这个版本。其他版本通常也能跑，但这是被测试过的版本。
- **Node** —— 用于 Vite 开发服务器（Vite 7 要求 Node `20.19+` / `22.12+`）。

```bash
bun install
bun run test                      # 1458 服务端 + 84 客户端 + 209 shared 个测试
cd apps/server && bun run dev     # API + 信令 + 媒体  → :4991
cd apps/client && bun run dev     # Vite 开发服务器    → :5173
```

或者用 `./start.sh` 在 tmux 里同时跑起来。从源码运行时，服务端会把 `/` 重定向到 Vite 开发服务器。

**推送前的完整检查**

```bash
bun run magic          # format + check-types + lint
bun run test
```

**一个必须知道的环境陷阱**：跑测试时**不要**设置 `HTTP_PROXY` / `HTTPS_PROXY`。Bun 的 `fetch` 会把测试客户端的 localhost 请求也走代理，导致 `apps/server/src/http/__tests__/plugin-routes.test.ts` 里那条"连接被断开"的断言稳定失败。要么去掉代理变量，要么加上 `NO_PROXY=localhost,127.0.0.1`。完整分析见 [`docs/ARCHITECTURE.zh-CN.md`](docs/ARCHITECTURE.zh-CN.md)。**我们自己踩过一次；这不是上游的 bug。**

## 文档

英文是主要语言，中文版本以 `*.zh-CN.md` 与英文版并排放置。

| 文档 | 回答什么问题 | 英文 |
| --- | --- | --- |
| [`docs/ARCHITECTURE.zh-CN.md`](docs/ARCHITECTURE.zh-CN.md) | 代码在哪、启动顺序、数据层、插件系统、怎么加一个接口 | [English](docs/ARCHITECTURE.md) |
| [`docs/RTC_ARCHITECTURE.zh-CN.md`](docs/RTC_ARCHITECTURE.zh-CN.md) | 媒体实际怎么流动、mediasoup 生命周期、P2P 该从哪里切入 | [English](docs/RTC_ARCHITECTURE.md) |
| [`docs/ECOSYSTEM_RESEARCH.zh-CN.md`](docs/ECOSYSTEM_RESEARCH.zh-CN.md) | 已有客户端现状、上游动态、PWA / 移动端网页审计 | [English](docs/ECOSYSTEM_RESEARCH.md) |
| [`docs/NATIVE_STRATEGY.zh-CN.md`](docs/NATIVE_STRATEGY.zh-CN.md) | 共享核心的选型，以及 macOS / Windows / iOS 的工程设计 | [English](docs/NATIVE_STRATEGY.md) |
| [`docs/APPLE_WATCH.zh-CN.md`](docs/APPLE_WATCH.zh-CN.md) | 为什么要做 Apple Watch 客户端、watchOS 允许什么、卡住它的 Apple 缺陷、以及验证计划 | [English](docs/APPLE_WATCH.md) |

上游自己的文档（对本代码库仍然适用）在 <https://sharkord.com/docs>；上游的本地开发笔记保留在 [`DEVELOPMENT.md`](DEVELOPMENT.md)。写代码时的代码规约以 [`AGENTS.md`](AGENTS.md) 为准。

## 参与贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)；计划与"明确不做"的清单见 [`ROADMAP.zh-CN.md`](ROADMAP.zh-CN.md)。

## 与上游的关系

- 上游：<https://github.com/Sharkord/sharkord> —— 作为本地 `upstream` remote 保留。
- 本仓库的 `development` 跟随上游 `development` 并向前合并，因此贡献在两个方向上都能合并。
- 通用修复与 PWA / 移动端网页的改进**向上游提**，不留在本地。
- 上游原始的 README、贡献指南与路线图**逐字保留**在 [`upstream-notes/`](upstream-notes/)；本仓库保留了上游**完整的提交历史**，因此贡献者列表与 tag 中会包含上游作者与上游版本 —— 属正常现象。
- 商标与品牌属于 Sharkord 项目；本 fork 只在"说明基于什么"的意义上使用这个名字。

## 致谢

建立在（未改动的）上游技术栈之上：[Bun](https://bun.sh)、[tRPC](https://trpc.io)、[mediasoup](https://mediasoup.org)、[Drizzle ORM](https://orm.drizzle.team)、[React](https://react.dev)、[Radix UI](https://www.radix-ui.com)、[Tailwind CSS](https://tailwindcss.com)。

## 许可证

MIT，见 [`LICENSE`](LICENSE)。原始 Sharkord 的版权声明已保留；对 Sharkord Next 的贡献同样按 MIT 条款接受。
