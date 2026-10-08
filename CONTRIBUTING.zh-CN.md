# 为 Cove 贡献

> 本文是 [`CONTRIBUTING.md`](CONTRIBUTING.md) 的中文翻译。英文版为权威版本，如有歧义以英文版为准。

**语言：** [English](CONTRIBUTING.md) | 中文

感谢你愿意考虑为这个项目出力。本项目是一个社区 fork —— 关于它是什么、为什么存在，请看 [README](README.md)；关于计划，以及我们决定**不做**的事情，请看 [`ROADMAP.md`](ROADMAP.md)。

## 最重要的两条规则

1. **保持与上游（upstream）可合并。** 我们始终沿用上游的形态。凡是会让 `git merge upstream/development` 变得痛苦的改动，都需要非常有说服力的理由，而且理由应当写进 PR。
2. **不要过度设计（over-engineering）。** 这是上游自己的核心原则，我们也坚持它：只加能跑起来的最小改动，在出现第二个调用点之前不要引入新的抽象，并且宁可删代码也不要新增配置。

[`AGENTS.md`](AGENTS.md) 是所有纳入版本控制内容的权威风格指南。在你提交第一个 PR 之前请先读它。简要版：文件名用 kebab-case，优先使用具名导出（named exports）而不是默认导出（default exports），使用箭头函数，保证不可变性（immutability），代码和 commit message 中不得使用破折号（em dashes），面向用户的字符串一律走 i18n（绝不硬编码）。

## 欢迎参与：先定位问题，再提交改动

Cove 是 Sharkord 的非官方兼容客户端，不提供独立服务端。当前欢迎 **Android、iOS、Apple Watch** 的实现、测试、UI、无障碍、兼容性研究与文档贡献。桌面原生客户端暂缓；通用服务端和 Web / PWA 改进优先向上游贡献。

1. 先搜索已有 Issue；提交 PR 前必须新建或关联本仓库的 Issue。
2. 说明问题 / 使用场景、受影响平台、Cove 版本或提交、Sharkord 服务端版本。Bug 附复现步骤、预期与实际行为；功能请求说明用户为什么需要它。
3. 描述计划改动的模块、范围与验证方式；已有 Issue 可以留言说明准备参与，不必重复新建。
4. 新功能、架构或协议改动、依赖引入，以及暂缓的桌面工作，先与维护者确认方向再实现。小型修复或文档更正也需关联 Issue，但不要求冗长设计讨论。
5. 每个 PR 聚焦一个问题；不要夹带无关重构或格式修改。维护者可以要求缩小范围或不予合并。

日志与截图务必去除令牌、私密消息和个人信息。使用 AI 工具也需理解并负责所提交的内容，不接受未经运行验证的生成代码。

## 开发环境搭建

```bash
git clone https://github.com/TimmySheep/sharkord-next.git
cd sharkord-next
bun install                      # Bun 1.3.14 is the pinned, tested version
bun run test
cd apps/server && bun run dev     # :4991
cd apps/client && bun run dev     # :5173  (Vite; needs Node 20.19+/22.12+)
```

常用脚本（均在仓库根目录执行）：

| 命令 | 作用 |
| --- | --- |
| `bun run test` | 每个 workspace 的单元测试（1458 server / 84 client / 209 shared） |
| `bun run test:e2e` | Playwright 端到端测试套件 |
| `bun run magic` | `format` + `check-types` + `lint` —— 推送前请执行这个 |
| `bun run format:check` | 仅检查格式，不写入 |
| `bun run check-types` | 仅检查 TypeScript |
| `bun run lint` | 仅执行 lint |
| `bun run knip` | 检查未使用的文件/导出/依赖 |

### 两个环境陷阱

- **运行测试套件时绝不要设置 `HTTP_PROXY` / `HTTPS_PROXY`。** Bun 的 `fetch` 会把测试客户端的 localhost 请求走代理，导致一条连接断开（connection-drop）断言稳定失败。请取消这些变量，或者导出 `NO_PROXY=localhost,127.0.0.1`。分析见 [`docs/ARCHITECTURE.md` §9](docs/ARCHITECTURE.md)。
- **运行全量测试套件前先停掉你的 dev 服务端。** dev 服务端占着 WebRTC 端口，而测试框架需要这个端口。另外注意，设置*任何* `SHARKORD_*` 变量都会让配置默认值测试按设计失败（`apps/server/src/config.test.ts`）。

## 分支与 commit 约定

- `development` 是集成分支，保持上游兼容。不要用 force push 改写它的历史。
- 从 `development` 切出分支，让分支保持聚焦，并按工作内容命名（`fix/mobile-safe-area`、`feat/p2p-signalling`）。
- commit 遵循上游的 conventional 风格，有 issue 或 PR 引用时就带上：

  ```
  fix(552): keep subscriptions alive across device sleep
  feat(105): add apple-mobile-web-app meta tags
  docs: correct the proxy caveat in the test notes
  ```

- 不需要做特别的签名，但**务必**使用你自己的 git 身份。请使用你自己的姓名与邮箱，不要复制维护者的身份。

## Pull requests

这里一个合格的 PR 是小的、可验证的。在你提交之前：

1. 关联 Issue（解决问题用 `Fixes #123`，相关工作用 `Refs #123`），目标分支为 `development`，写明平台、模块与兼容性影响。
2. 运行相关平台的构建与测试，附准确命令和结果。TypeScript / shared / 服务端改动运行 `bun run magic` 和 `bun run test`；纯文档改动检查链接与格式，不适用的检查说明原因，不得声称已通过。
3. 新行为有测试，或者 PR 正文解释了为什么测试不切实际。
4. 当 `docs/` 所描述的行为发生变化时，相应文档已更新。
5. PR 正文要说明**改了什么、为什么改、你验证了什么** —— 包括命令及其输出。没有实际验证过的说法应当标注出来；本项目明确区分“已验证”与“未验证”，并期待 PR 中同样如此。

审查会优先关注范围，以及与上游的可合并性，其次才是风格。如果某个改动对上游也有用，我们可能会请你把它也发到上游。

## 与上游同步

```bash
git remote add upstream https://github.com/Sharkord/sharkord.git   # once
git fetch upstream
git checkout development
git merge upstream/development
```

冲突解决时，除非那个改动是我们自己的，否则以上游为准。如果冲突是来自我们的改动，请在 merge commit message 中说明解决方式。

## 许可与品牌

- 贡献均按 **MIT license** 接受，与上游一致（`inbound = outbound`）。
- 保留上游的版权声明，不要改动。
- 不要以暗示本 fork 为官方的方式使用 Sharkord 名称或 logo。应将其描述为 “an unofficial compatible client for Sharkord” —— 与 README 中使用的措辞一致。

上游原始的贡献指南（为上游项目而写，其关于范围和 PR 理念的内容仍值得一读）原样保留在 [`upstream-notes/UPSTREAM-CONTRIBUTING.md`](upstream-notes/UPSTREAM-CONTRIBUTING.md)。
