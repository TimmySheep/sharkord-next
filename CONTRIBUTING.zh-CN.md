# 为 Sharkord Next 贡献

> 本文是 [`CONTRIBUTING.md`](CONTRIBUTING.md) 的中文翻译。英文版为权威版本，如有歧义以英文版为准。

**语言：** [English](CONTRIBUTING.md) | 中文

感谢你愿意考虑为这个项目出力。本项目是一个社区 fork —— 关于它是什么、为什么存在，请看 [README](README.md)；关于计划，以及我们决定**不做**的事情，请看 [`ROADMAP.md`](ROADMAP.md)。

## 最重要的两条规则

1. **保持与上游（upstream）可合并。** 我们始终沿用上游的形态。凡是会让 `git merge upstream/development` 变得痛苦的改动，都需要非常有说服力的理由，而且理由应当写进 PR。
2. **不要过度设计（over-engineering）。** 这是上游自己的核心原则，我们也坚持它：只加能跑起来的最小改动，在出现第二个调用点之前不要引入新的抽象，并且宁可删代码也不要新增配置。

[`AGENTS.md`](AGENTS.md) 是所有纳入版本控制内容的权威风格指南。在你提交第一个 PR 之前请先读它。简要版：文件名用 kebab-case，优先使用具名导出（named exports）而不是默认导出（default exports），使用箭头函数，保证不可变性（immutability），代码和 commit message 中不得使用破折号（em dashes），面向用户的字符串一律走 i18n（绝不硬编码）。

## 从哪里开始

以下是一些小而独立、随时可以上手的工作：

- **移动端 Web / PWA** —— 三个具体的缺口（没有 service worker、没有 `viewport-fit=cover`、没有 iOS standalone meta）都在 [`docs/ECOSYSTEM_RESEARCH.md` §5.3](docs/ECOSYSTEM_RESEARCH.md) 中附有文件级证据。每一个都是一个自成体系的 PR。
- **文档** —— `docs/` 中的每一篇文档都是被跟踪的研究成果。如果你发现某条说法已不再与代码相符，修正它就是一项受欢迎的贡献。
- **Android** —— 原生 Android 客户端是另一个独立项目（[`Vigno04/sharkord-android`](https://github.com/Vigno04/sharkord-android)，MIT 许可）。协议兼容性工作，以及固定版本的兼容性 CI，正是我们关心的缺口；见 [`docs/ECOSYSTEM_RESEARCH.md` §5.1](docs/ECOSYSTEM_RESEARCH.md)。
- **上游也会想要的东西** —— 通用 bug 修复最好先提给上游，这样两个项目都能受益，我们的 diff 也能保持很小。

如果你不确定某个想法是否合适，就开一个 issue 问一下。在这里，“需要讨论”是一种正常状态，而不是拒绝。

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

- `development` 与上游保持一致。不要用 force push 改写它的历史。
- 从 `development` 切出分支，让分支保持聚焦，并按工作内容命名（`fix/mobile-safe-area`、`feat/p2p-signalling`）。
- commit 遵循上游的 conventional 风格，有 issue 或 PR 引用时就带上：

  ```
  fix(552): keep subscriptions alive across device sleep
  feat(105): add apple-mobile-web-app meta tags
  docs: correct the proxy caveat in the test notes
  ```

- 不需要做特别的签名，但**务必**使用你自己的 git 身份。如果你是在这台机器上贡献，当前使用的身份是 `TimmySheep <100548146+TimmySheep@users.noreply.github.com>`。

## Pull requests

这里一个合格的 PR 是小的、可验证的。在你提交之前：

1. `bun run magic` 和 `bun run test` 在本地都是干净的。
2. 新行为有测试，或者 PR 正文解释了为什么测试不切实际。
3. 当 `docs/` 所描述的行为发生变化时，相应文档已更新。
4. PR 正文要说明**改了什么、为什么改、你验证了什么** —— 包括命令及其输出。没有实际验证过的说法应当标注出来；本项目明确区分“已验证”与“未验证”，并期待 PR 中同样如此。

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
- 不要以暗示本 fork 为官方的方式使用 Sharkord 名称或 logo。应将其描述为 “an unofficial community project based on Sharkord” —— 与 README 中使用的措辞一致。

上游原始的贡献指南（为上游项目而写，其关于范围和 PR 理念的内容仍值得一读）原样保留在 [`upstream-notes/UPSTREAM-CONTRIBUTING.md`](upstream-notes/UPSTREAM-CONTRIBUTING.md)。
