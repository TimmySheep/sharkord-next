# Covy

**Covy 是面向 [Sharkord](https://github.com/Sharkord/sharkord) 的非官方、开源兼容客户端，不是独立通信平台，也不是独立服务端项目。**
Covy 连接 Sharkord 服务器：后端、账号、频道与媒体基础设施由 Sharkord 提供，Covy 专注原生客户端体验。Covy 不隶属于 Sharkord，也没有获得其维护者的背书。

**当前重点：Android、iOS 和 Apple Watch。欢迎一起来构建这些客户端。**

**语言：** [English](README.md) | 中文

[![CI](https://github.com/TimmySheep/sharkord-next/actions/workflows/ci.yml/badge.svg)](https://github.com/TimmySheep/sharkord-next/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/TimmySheep/sharkord-next)](LICENSE)

## 为什么先做移动端？

单个维护者无法持续同时推进五个平台的原生客户端。Sharkord 已经提供桌面 Web UI：Windows 和 macOS 用户可以直接在浏览器打开自己的 Sharkord 实例，使用上游网页客户端已有的功能。因此，原生移动体验与腕上语音的缺口更迫切，是 Covy 当前投入的重点。

| 平台 | 当前方向 |
| --- | --- |
| **Android** | 核心重点：[`apps/android`](apps/android) 下的 Kotlin / Jetpack Compose 原生客户端 |
| **iOS（iPhone；现有 Apple 工程也包含 iPad）** | 核心重点：[`apps/apple-mobile`](apps/apple-mobile) 下的 Swift / SwiftUI 原生客户端 |
| **Apple Watch** | 与 iOS 一起推进的 watchOS 方向：腕上按住说话，需通过真机网络与音频可行性验证 |
| **Windows / macOS 原生客户端** | 暂缓，不是放弃。保留已有源码与研究，不承诺近期交付 |
| **桌面网页端** | 使用 Sharkord 已有 Web UI；Covy 不另建桌面网页平台 |

这些是优先级，不代表三个客户端已经完成或功能对齐。Apple Watch 的目标是进入一个语音频道、按住说话、听到频道、退出。持续语音、后台行为与耗电必须在真机验证，界面或模拟器跑通不能证明语音可用。见 [`docs/APPLE_WATCH.zh-CN.md`](docs/APPLE_WATCH.zh-CN.md)。

## 与 Sharkord 的关系

- **所需后端：** 已有的 [Sharkord 服务器](https://github.com/Sharkord/sharkord)。Covy 不提供独立服务端或托管服务。
- 仓库保留上游服务端（`apps/server`）、网页客户端（`apps/client`）、共享包与 Git 历史，用于开发、兼容性测试及保留来源。保留这些代码不意味着 Covy 是新的服务端产品。
- 保持与 Sharkord 现有协议兼容，不把 Covy 专属后端作为默认使用前提。
- 通用服务端修复与 Web / PWA 改进应向上游讨论和贡献；客户端特有工作在这里推进。
- 仓库 URL 目前仍为 `TimmySheep/sharkord-next`；**Covy** 是客户端产品名。上游原始文档保留在 [`upstream-notes/`](upstream-notes/)。

## 开始使用与开发

1. 按照 [Sharkord 官方文档](https://sharkord.com/docs) 与[上游发行版](https://github.com/Sharkord/sharkord/releases)部署或使用已有实例。
2. 桌面端直接在浏览器打开该实例的 Web UI，无须等待 Covy 原生桌面客户端。
3. 开发 Covy 请看 [Android 构建说明](apps/android/README.md)或 [Apple 移动端构建说明](apps/apple-mobile/README.md)。各平台的支持与验收状态需分别确认；此首页不是发布公告。

请勿把 owner token、会话令牌、私密聊天或其他敏感信息放进 Issue、截图或日志。

## 欢迎一起构建 Covy

欢迎参与 Android、iOS、Apple Watch 可行性验证、Bug 反馈、界面与无障碍改进、测试、兼容性检查及文档工作。

**提交 PR 前，请先在[本仓库](https://github.com/TimmySheep/sharkord-next/issues)新建或关联 Issue。** 说明问题或使用场景、受影响平台、计划改动与验证方式。较大功能、架构调整、依赖引入及桌面原生开发，先与维护者讨论范围再实现。每个 PR 聚焦一个问题，方便定位、审查和合并。

请阅读 [贡献指南](CONTRIBUTING.zh-CN.md)与[路线图](ROADMAP.zh-CN.md)。Issue 表单和 PR 模板帮助明确：**解决什么问题、改了哪里、实际验证了什么**。进入路线图或已有 Issue，不等于承诺合并或发布。

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

- [路线图](ROADMAP.zh-CN.md)与[贡献指南](CONTRIBUTING.zh-CN.md)
- [架构](docs/ARCHITECTURE.zh-CN.md)与 [RTC 架构](docs/RTC_ARCHITECTURE.zh-CN.md)
- [生态研究](docs/ECOSYSTEM_RESEARCH.zh-CN.md)
- [原生策略研究](docs/NATIVE_STRATEGY.zh-CN.md)：历史设计，不代表当前优先级
- [Apple Watch 研究与验证计划](docs/APPLE_WATCH.zh-CN.md)
- [AGENTS.md](AGENTS.md)：代码规约；[DEVELOPMENT.md](DEVELOPMENT.md)：上游开发说明

研究文档描述其审阅的版本，不保证当前发行版仍然相同。当前产品优先级以此首页和路线图为准。

## 致谢与许可

Covy 建立在 Sharkord 及其贡献者的工作之上。Sharkord 名称与品牌属于上游项目。采用 MIT 许可，见 [LICENSE](LICENSE)；保留上游版权声明。Covy 的贡献同样按 MIT 条款接受。
