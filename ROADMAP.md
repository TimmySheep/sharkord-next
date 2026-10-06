# Sharkord Next — Roadmap

This roadmap is deliberately conservative: it lists what we intend to do, **what we have decided not to
do**, and the evidence behind each decision. Every claim below links to a document in [`docs/`](docs/) that
was written against the actual source at `c611bb4`.

Status legend: **✅ done** · **🔜 next** · **🧪 needs a spike** · **📋 planned** · **⛔ not doing**

## Guiding principles

1. **Stay mergeable with upstream.** We work in upstream's shape so improvements can flow both ways.
2. **Native-first, not wrapper-first.** No Electron shell that reloads the web app.
3. **Bandwidth-aware.** Self-hosters run out of uplink before they run out of features.
4. **Smallest thing that works.** Upstream's own rule; new abstractions need a second call site.
5. **Verify before claiming.** Docs and PRs separate what was measured from what is expected.

## ⛔ What we are not doing

| Not doing | Why |
| --- | --- |
| A second Android client written from scratch | A real one already exists and is MIT: Kotlin + Compose, voice/video/screen-share/DMs. Rewriting duplicates months of work with no protocol advantage. Fork it if needed instead. |
| An Electron desktop client | ~12 thin Electron wrappers already exist and upstream does not compete with them. A native client is the differentiator, a wrapper is not. |
| A plugin sandbox / runtime rewrite | Upstream's plugin model is deliberate (trusted, in-process, capability-gated). Replacing it breaks every existing plugin for no user-visible gain. |
| Diverging the wire protocol | Every third-party client depends on tRPC-over-WebSocket + mediasoup signalling as it exists. A fork that invents its own protocol is unusable by the ecosystem it wants to attract. |
| A large rewrite of the web client | The reference client works. We improve mobile/PWA behaviour and leave the architecture alone. |

## Track 0 — Foundation

| Item | Status | Evidence |
| --- | --- | --- |
| Fork with full upstream history, `upstream` remote configured | ✅ | 679 commits, 25 tags, base `c611bb4` |
| Pinned, documented toolchain (Bun 1.3.14) and green baseline | ✅ | `bun run test` → 1458 server / 84 client / 209 shared, 0 failures |
| Architecture, RTC, ecosystem and native research written down | ✅ | [`docs/`](docs/) |
| README / CONTRIBUTING / ROADMAP describing what this project is | ✅ | this file |

## Track 1 — Mobile web and PWA

Cheapest path to "usable on the phone I already own", all three verified in source
([audit](docs/ECOSYSTEM_RESEARCH.md#4-current-web-client--pwa--mobile-web-audit)):

| Item | Status |
| --- | --- |
| Service worker: offline app shell, precache of hashed assets, Web Push plumbing | 🔜 |
| `viewport-fit=cover` + safe-area padding on the shell so `env(safe-area-inset-*)` stops being inert | 🔜 |
| iOS standalone meta (`apple-mobile-web-app-capable`, status bar style, startup image) and a real mobile layout pass on the topbar/sidebars | 🔜 |
| Touch behaviour: `touch-action` / `overscroll-behavior` on scroll containers | 📋 |

Success criterion: install from Safari/Chrome, open with no network and get the app shell, and receive a
notification while the app is closed.

## Track 2 — Direct (P2P) voice

Today *all* media is relayed through the server SFU (`routed, not mixed`), so an N-person channel costs
the host N−1 upstream streams ([RTC](docs/RTC_ARCHITECTURE.md)). For 1:1 calls that is pure overhead.

| Item | Status |
| --- | --- |
| Design a `PeerRelaySession` abstraction beside the existing server transport, starting with 1v1 audio | 🧪 |
| User-visible choice: **Direct** vs **Server** per call/channel, with a safe fallback when direct fails | 📋 |
| Relay capacity accounting + upload-bandwidth guardrails for self-hosters | 📋 |
| Deployment guidance for ICE behind tunnels/NAT: announced address, port equality, when a TURN-style relay is unavoidable | 🔜 (documentation first — this is where real installs break) |

The concrete change surface (signalling, permissions, server media abstraction, client media layer, ICE)
is listed with `file:line` evidence in [`docs/RTC_ARCHITECTURE.md` §7](docs/RTC_ARCHITECTURE.md).

## Track 3 — Native clients

Decision: adopt **route (c)** — `packages/shared` becomes a schema-first, language-neutral protocol
contract with codegen to Swift/C# models, plus **one shared SwiftPM core across the Apple targets** — and
extract a Rust core only after the protocol stops churning ([rationale](docs/NATIVE_STRATEGY.md)). Route
(b), four independent implementations, is rejected.

| Milestone | Scope | Status |
| --- | --- | --- |
| M0 | Protocol contract extracted + codegen skeleton (models from `packages/shared`) | 📋 |
| M1 | Apple Mobile (iPhone + iPad, one project): login → server → channel → text | 📋 |
| M2 | macOS (SwiftUI): text, then voice | 📋 |
| M3 | Windows (WinUI 3): text-first, voice gated | 📋 |
| M4 | Windows voice feasibility spike: `libmediasoupclient` P/Invoke report | 🧪 |

The shared-core split (what belongs in the core vs what must stay platform-native) and the per-platform
API matrix are in [`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md). The single biggest known risk is
that **no C# mediasoup client exists**, so Windows voice is a research problem, not a task — treat M4 as
the gate for M3's voice scope.

## Track 4 — Android

| Item | Status |
| --- | --- |
| Open a compatibility conversation with [`Vigno04/sharkord-android`](https://github.com/Vigno04/sharkord-android) (MIT, Kotlin + Compose) | 🔜 |
| Contribute the thing that project structurally lacks: an upstream-version pin + protocol-compatibility CI | 📋 |
| Fork only if the fork triggers documented in [`docs/ECOSYSTEM_RESEARCH.md` §5.1](docs/ECOSYSTEM_RESEARCH.md) are met | 📋 |

## Track 5 — Self-hosting quality

| Item | Status |
| --- | --- |
| Document the media/ICE constraints that break voice behind tunnels and NAT (announced address, port equality, TCP fallback limits) | 🔜 (partly in [`docs/RTC_ARCHITECTURE.md` §6](docs/RTC_ARCHITECTURE.md)) |
| Diagnose client-side "Failed to initialize voice connection" reports: the server-side flow completes today, so the failure is in the media path — likely announced address or UDP reachability | 🧪 |
| Publish our own pinned container image once we ship server-side changes (fingerprint: no `latest`, always a version tag) | 📋 |
| Storage guidance: signed URLs are **off** by default, so attachment URLs are publicly readable unless the server enables signing | 📋 |

## Track 6 — Upstream collaboration

| Item | Status |
| --- | --- |
| Send general bug fixes upstream rather than keeping them downstream | 🔜 (ongoing) |
| Keep `development` merged forward from `upstream/development` | 🔜 (ongoing) |
| Report back anything the ecosystem needs: protocol versioning, an upstream version endpoint, reconnect parity | 📋 |

## How this roadmap changes

Proposals are welcome as issues. A roadmap item is only promoted to work when its evidence section in
`docs/` is strong enough to describe the change surface — that is the bar this project set for itself, and
it is why the `docs/` set was written before any code was touched.
