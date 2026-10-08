# Covy

**Covy is an unofficial, open-source compatible client for [Sharkord](https://github.com/Sharkord/sharkord), not a standalone communication platform or an independent server project.**
It connects to a Sharkord server: Sharkord provides the backend, accounts, channels and media infrastructure; Covy focuses on the native client experience. Covy is not affiliated with or endorsed by Sharkord's maintainers.

**Current focus: Android, iOS and Apple Watch.** We welcome contributors to build these clients together.

**Languages:** English | [中文](README.zh-CN.md)

[![CI](https://github.com/TimmySheep/sharkord-next/actions/workflows/ci.yml/badge.svg)](https://github.com/TimmySheep/sharkord-next/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/TimmySheep/sharkord-next)](LICENSE)

## Why mobile first?

A single maintainer cannot sustainably develop five native platforms at once. Sharkord already provides a web UI for desktop use: on Windows and macOS, open your Sharkord instance in a browser to access the upstream web client's features. Native mobile interaction and wrist-based voice are the more urgent gaps Covy aims to address.

| Platform | Current direction |
| --- | --- |
| **Android** | Core focus: native Kotlin / Jetpack Compose client in [`apps/android`](apps/android) |
| **iOS (iPhone; iPad in the existing Apple project)** | Core focus: native Swift / SwiftUI client in [`apps/apple-mobile`](apps/apple-mobile) |
| **Apple Watch** | Part of the iOS / watchOS effort: wrist push-to-talk, subject to real-device networking and audio feasibility validation |
| **Windows / macOS native clients** | Deferred, not abandoned. Existing source and research are retained; no near-term delivery commitment |
| **Desktop web** | Use Sharkord's existing web UI; Covy is not building a separate desktop web platform |

These are priorities, not a claim that all three clients are complete or have feature parity. Apple Watch's intended experience is to join one voice channel, hold to talk, hear the channel and leave. Persistent voice, background behaviour and battery impact must be tested on real hardware; UI or simulator success is not proof that voice works. See [`docs/APPLE_WATCH.md`](docs/APPLE_WATCH.md).

## Relationship to Sharkord

- **Required backend:** an existing [Sharkord server](https://github.com/Sharkord/sharkord). Covy does not offer its own independent server or hosted service.
- This repository retains upstream server (`apps/server`), web client (`apps/client`), shared packages and Git history for development, compatibility testing and attribution. Their presence does not make Covy a new server product.
- Preserve compatibility with Sharkord's existing protocol. Do not require a Covy-only backend as the default client path.
- General server fixes and web / PWA improvements should be discussed and contributed upstream; client-specific work belongs here.
- The repository URL is currently `TimmySheep/sharkord-next`; **Covy** is the client product name. Original upstream documents remain in [`upstream-notes/`](upstream-notes/).

## Getting started

1. Set up or use an existing Sharkord instance following the [official documentation](https://sharkord.com/docs) and [upstream releases](https://github.com/Sharkord/sharkord/releases).
2. On desktop, open that instance's web UI in your browser. You do not need to wait for Covy's native desktop clients.
3. For Covy development, use the [Android build guide](apps/android/README.md) or the [Apple mobile build guide](apps/apple-mobile/README.md). Client support and acceptance status must be checked per platform; this README is not a release announcement.

Do not include owner tokens, session tokens, private messages or other secrets in issues, screenshots or logs.

## Build Covy with us

Contributions are welcome: Android, iOS, Apple Watch feasibility work, bug reports, UI / accessibility improvements, tests, compatibility checks and documentation.

**Before opening a PR, create or link an Issue in [this repository](https://github.com/TimmySheep/sharkord-next/issues).** Describe the problem or use case, affected platform, intended change and verification plan. For larger features, architecture changes, dependencies or desktop-native work, agree on scope with the maintainer before implementing. One focused problem per PR makes review and merging easier.

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [ROADMAP.md](ROADMAP.md). The Issue forms and PR template help identify **what problem you are solving, what changed, and what was actually tested**. Roadmap inclusion or an open Issue is not a promise of merge or release.

## Development from source

**Prerequisites**

- **Bun `1.3.14`** — pinned by upstream CI (`.github/workflows/ci.yml`) and by `@types/bun` in
  `package.json`. Other versions usually work, but this is the tested one.
- **Node** for the Vite dev server (Vite 7 requires Node `20.19+` / `22.12+`).

```bash
bun install
bun run test                      # 1458 server + 84 client + 209 shared tests
cd apps/server && bun run dev     # API + signalling + media  → :4991
cd apps/client && bun run dev     # Vite dev server           → :5173
```

Or run both in tmux with `./start.sh`. From source, the server redirects `/` to the Vite dev server.

**Full check before you push**

```bash
bun run magic          # format + check-types + lint
bun run test
```

**One environment gotcha worth knowing.** Do **not** run the test suite with `HTTP_PROXY` / `HTTPS_PROXY`
set: Bun's `fetch` routes the test client's localhost requests through the proxy, and one assertion
(`apps/server/src/http/__tests__/plugin-routes.test.ts`, the "drops the connection" case) fails
deterministically. Either unset the proxy or add `NO_PROXY=localhost,127.0.0.1`. Full analysis in
[`docs/ARCHITECTURE.md` §9](docs/ARCHITECTURE.md). This bit us once; it is not an upstream bug.

## Documentation

- [Roadmap](ROADMAP.md) and [contribution guide](CONTRIBUTING.md)
- [Architecture](docs/ARCHITECTURE.md) and [RTC architecture](docs/RTC_ARCHITECTURE.md)
- [Ecosystem research](docs/ECOSYSTEM_RESEARCH.md)
- [Native strategy research](docs/NATIVE_STRATEGY.md): historical design, not the current priority order
- [Apple Watch research and feasibility plan](docs/APPLE_WATCH.md)
- [AGENTS.md](AGENTS.md): code conventions; [DEVELOPMENT.md](DEVELOPMENT.md): upstream development notes

Research documents describe the revisions they inspected, not a guarantee about current releases. Current product priorities are defined by this README and the roadmap.

## Acknowledgments and license

Covy builds on Sharkord and its contributors' work. Sharkord's name and branding belong to the upstream project. MIT: see [LICENSE](LICENSE); preserve upstream copyright notices. Contributions to Covy are accepted under the same MIT terms.
