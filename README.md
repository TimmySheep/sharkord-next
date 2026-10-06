# Sharkord Next

**Sharkord Next is an unofficial community project based on [Sharkord](https://github.com/Sharkord/sharkord).**
It is not affiliated with, endorsed by, or supported by the Sharkord project or its maintainers.
Fixes and generally useful improvements are offered back upstream where they belong.

A lightweight, self-hostable, Discord-like communication platform — text and voice — that aims for
**native-first clients** instead of a pile of Electron wrappers.

[![CI](https://github.com/TimmySheep/sharkord-next/actions/workflows/ci.yml/badge.svg)](https://github.com/TimmySheep/sharkord-next/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/TimmySheep/sharkord-next)](LICENSE)

---

## Status

**Foundation stage.** This repository is currently a faithful fork of upstream `Sharkord/sharkord`
at commit `c611bb4` (6 commits past `v0.0.25`), with the full upstream history preserved. No
behavioural changes have been made yet — what you see on the `development` branch is upstream code.
Like upstream, it is **alpha**: expect bugs, incomplete features and breaking changes.

| Area | State |
| --- | --- |
| Server (`apps/server`) | Upstream code, unmodified. Builds and runs; **1458 server tests pass**. |
| Reference web client (`apps/client`) | Upstream code, unmodified. Builds and runs (Vite 7.3.1). |
| Our own features | **None yet.** Everything still tracks upstream `development`. |
| Documentation | Architecture, RTC, ecosystem and native-strategy research live in [`docs/`](docs/). |

## What it is

Everything below is upstream's feature set, unchanged — it is worth stating plainly so it is clear what
this fork inherits:

- **Voice channels** with video and screen sharing, over a built-in mediasoup SFU
- **Text channels** grouped into categories, with threads, replies, reactions, pins and search
- **Direct messages** between members
- **Roles and permissions**, with per-channel overrides for individual roles and users
- **Custom emoji**, mentions and channel references
- **Invites** with usage limits and automatic role assignment
- **File uploads** with per-user storage quotas and optional signed URLs
- **Plugins** that extend both server and client, through the [plugin SDK](packages/plugin-sdk)

## Why a fork

Upstream is doing good work and this project wants to stay mergeable with it. The fork exists because
three things are true today ([evidence](docs/ECOSYSTEM_RESEARCH.md)):

1. **There is no official mobile or desktop client.** Upstream ships a web client; the community
   discussion for a desktop/mobile app has been open since 2026-02 with no commitment
   ([#105](https://github.com/Sharkord/sharkord/discussions/105)).
2. **The web client is a desktop-first SPA**, not an installable app: no service worker, no
   `viewport-fit=cover`, no iOS standalone meta. On a phone it works, but it is not a PWA.
   ([audit](docs/ECOSYSTEM_RESEARCH.md#4-current-web-client--pwa--mobile-web-audit))
3. **Media is server-relayed only (SFU).** Bandwidth is the first thing a self-hoster runs out of, and
   there is no option for a direct 1v1 path. ([RTC architecture](docs/RTC_ARCHITECTURE.md))

## Platform plan

| Platform | Plan | Where |
| --- | --- | --- |
| **Web** (reference client) | Keep, improve mobile/PWA behaviour | [`docs/ECOSYSTEM_RESEARCH.md`](docs/ECOSYSTEM_RESEARCH.md) |
| **iPhone + iPad** | One unified Apple project, Swift + SwiftUI — **unclaimed by anyone today** | [`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md) |
| **macOS** | Swift + SwiftUI, no Electron | [`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md) |
| **Windows** | C# + WinUI 3, text-first (voice gated on a spike) | [`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md) |
| **Android** | **Do not rewrite.** Contribute to / fork [`Vigno04/sharkord-android`](https://github.com/Vigno04/sharkord-android) (Kotlin + Compose, MIT) | [`docs/ECOSYSTEM_RESEARCH.md`](docs/ECOSYSTEM_RESEARCH.md#1-existing-android-native-clients) |

## Getting started

The server is a single process (Bun + mediasoup, one SQLite file, no external database) that serves both
the API and the web client.

> [!WARNING]
> On first launch the server generates a secret **owner token** and prints it to the console. It is both
> the credential that grants owner access **and** the key used to sign every session and file URL, so
> anyone who obtains it can take ownership **and** impersonate any account. Keep it out of logs,
> screenshots and issue reports, store it securely, and do not lose it. See
> [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full security model.

**Option A — upstream's standalone binaries (quickest way to evaluate).** Upstream ships single-file
binaries for Linux, macOS and Windows that bundle server and client:

```bash
# Linux x64 — from https://github.com/Sharkord/sharkord/releases
curl -L https://github.com/Sharkord/sharkord/releases/latest/download/sharkord-linux-x64 -o sharkord
chmod +x sharkord && ./sharkord
```

This repository does **not publish its own binaries yet**, and today's code is identical to upstream, so
upstream's release is the fastest way to try the same thing.

**Option B — Docker (recommended for self-hosting).**

```bash
# Build this repository's image (no image is published from this fork yet)
docker build -t sharkord-next .

docker run -d --name sharkord-next \
  -p 4991:4991/tcp \
  -p 40000:40000/tcp -p 40000:40000/udp \
  -v "$PWD/data:/home/bun/.config/sharkord" \
  -e PUID=1000 -e PGID=1000 \
  sharkord-next
```

Then open <http://localhost:4991>. On first launch the owner token is printed to the logs — capture it
from there (`docker logs sharkord-next`) and store it safely; some deployments prefer not to let it land
in logs at all.

**Option C — build and run from source.** See [Development from source](#development-from-source) below.

**Ports that matter**

| Port | Protocol | Purpose |
| --- | --- | --- |
| `4991` | TCP | Web UI, REST, tRPC, WebSocket signalling |
| `40000` | UDP (+TCP) | WebRTC media (mediasoup) |

**Behind a tunnel / reverse proxy.** Web and signalling travel over TCP; media travels over UDP.
Two constraints cause almost every "voice does not connect" report:

1. The **media port must be identical on both sides** (`local_port == remote_port`), because mediasoup
   advertises its own listening port.
2. The advertised media address must be **reachable by the client**. Set it through
   `SHARKORD_WEBRTC_ANNOUNCED_ADDRESS` (the `webRtc.announcedAddress` config key); otherwise upstream falls
   back to the server's detected public IP, which may be wrong behind a relay.

Environment variables are applied at runtime and are **not written back** into `config.ini`, so keep them
in your `compose.yml` / service definition and treat the container as disposable.

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

| Document | Answers |
| --- | --- |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Where the code lives, boot order, data layer, plugin system, how to add an endpoint |
| [`docs/RTC_ARCHITECTURE.md`](docs/RTC_ARCHITECTURE.md) | How media actually flows, mediasoup lifecycle, and where a P2P path would plug in |
| [`docs/ECOSYSTEM_RESEARCH.md`](docs/ECOSYSTEM_RESEARCH.md) | Which clients already exist, what upstream ships, PWA/mobile-web audit |
| [`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md) | Shared-core decision and the Apple / macOS / Windows project designs |

Upstream's own documentation (still accurate for this codebase) is at
<https://sharkord.com/docs>, and its local developer notes remain in [`DEVELOPMENT.md`](DEVELOPMENT.md).
The upstream code conventions in [`AGENTS.md`](AGENTS.md) are authoritative for any code you write.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). The plan and the explicit "we are not doing this" list live in
[`ROADMAP.md`](ROADMAP.md).

## Relationship to upstream

- Upstream: <https://github.com/Sharkord/sharkord> — kept as the `upstream` git remote.
- `development` in this repository mirrors upstream `development` and is merged forward, so contributions
  stay mergeable in both directions.
- Upstream's original README, contribution guide and roadmap are preserved verbatim under
  [`upstream-notes/`](upstream-notes/) so nothing was lost in the rebrand.
- Trademark and branding belong to the Sharkord project; this fork uses the name only to describe what it
  is based on.

## Acknowledgments

Built on upstream's stack, unchanged: [Bun](https://bun.sh), [tRPC](https://trpc.io),
[mediasoup](https://mediasoup.org), [Drizzle ORM](https://orm.drizzle.team), [React](https://react.dev),
[Radix UI](https://www.radix-ui.com), [Tailwind CSS](https://tailwindcss.com).

## License

MIT — see [`LICENSE`](LICENSE). The original Sharkord copyright notice is preserved; contributions to
Sharkord Next are accepted under the same MIT terms.
