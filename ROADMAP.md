# Sharkord Next — Roadmap

This roadmap is deliberately conservative: it lists what we intend to do, **what we have decided not to
do**, and the evidence behind each decision. Every claim below links to a document in [`docs/`](docs/) that
was written against the actual source at `c611bb4`.

**Languages:** English | [中文](ROADMAP.zh-CN.md)

## Priority order (decided)

1. **macOS, native** — Swift + SwiftUI, no Electron.
2. **Windows, native** — C# + WinUI 3, text first, voice gated on a spike.
3. **iPhone + iPad, native** — one Apple project, sharing the Swift core macOS needs anyway.
4. Direct (P2P) voice, then self-hosting quality, in parallel with the native work.

**Not on this list, on purpose:** Android (a native client already exists) and PWA/mobile-web work in this
fork (proposed upstream instead). Details below.

Status legend: **✅ done** · **🔜 next** · **🧪 needs a spike** · **📋 planned** · **⛔ not doing**

## Guiding principles

1. **Native, not a wrapper.** No Electron shell that reloads the web app.
2. **Stay mergeable with upstream.** We work in upstream's shape so improvements can flow both ways.
3. **Bandwidth-aware.** Self-hosters run out of uplink before they run out of features.
4. **Smallest thing that works.** Upstream's own rule; new abstractions need a second call site.
5. **Verify before claiming.** Docs and PRs separate what was measured from what is expected.

## ⛔ What we are not doing

| Not doing | Why |
| --- | --- |
| **A second Android client** | A real native one already exists and is MIT: Kotlin + Jetpack Compose, with voice, video, screen share and DMs ([`Vigno04/sharkord-android`](https://github.com/Vigno04/sharkord-android)). A rewrite duplicates a year of work. |
| **PWA / mobile-web work in this fork** | The three web-client gaps are generic improvements to upstream's client. Fixed upstream, every self-hosted instance and third-party client benefits; fixed here, only we do. Proposed upstream in [Track 5](#track-5-upstream-collaboration). |
| **An Electron desktop client** | Roughly a dozen thin Electron wrappers already exist. A native client is the differentiator; a wrapper is not. |
| **A plugin sandbox / runtime rewrite** | Upstream's plugin model is deliberate (trusted, in-process, capability-gated). Replacing it breaks every existing plugin for no user-visible gain. |
| **Diverging the wire protocol** | Every third-party client depends on tRPC-over-WebSocket + mediasoup signalling as it exists. A fork that invents its own protocol is unusable by the ecosystem it wants to attract. |
| **A large rewrite of the web client** | The reference client works. We leave its architecture alone. |

## Track 1 — macOS, native (first)

| Item | Status |
| --- | --- |
| Project skeleton: SwiftPM core + SwiftUI app under `apps/macos`, wiring to the protocol contract | 📋 |
| M1: login → server → channel → text, against a real server | 📋 |
| M2: voice (mediasoup client via a Swift wrapper), push-to-talk, per-channel audio | 🧪 |
| Native affordances: menu bar presence, global push-to-talk hotkey, native screen capture (ScreenCaptureKit), system audio | 📋 |

Design, module split and the platform API matrix: [`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md).
Known risk: global hotkeys on macOS require Accessibility permission, and native media means the mediasoup
client must be wrapped for Swift — there is no official Swift client.

## Track 2 — Windows, native (second)

| Item | Status |
| --- | --- |
| M3: WinUI 3 client, text-first (login → server → channel → text) | 📋 |
| M4: **voice feasibility spike** — build `libmediasoupclient` (MSVC + libwebrtc) and P/Invoke it, or document why that is not viable | 🧪 |
| Native affordances: system tray, global hotkeys, WASAPI audio, Windows.Graphics.Capture | 📋 |

**Windows voice has no viable engine today** (no C# mediasoup client exists). That is why text ships
first and voice is gated on M4 rather than promised. See
[`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md) for the full risk table.

## Track 3 — iPhone + iPad, native (third)

| Item | Status |
| --- | --- |
| One Apple project for iPhone and iPad, reusing the Swift core built for macOS | 📋 |
| Voice with the platform audio session, APNs notifications, background behaviour | 📋 |

Doing macOS first is deliberate: both are Swift, so the core written for Track 1 is reused rather than
rewritten. Documented constraints worth reading before starting: a recording session cannot be started
from the background on iOS, and `playAndRecord` is pre-empted by incoming calls.

## Track 4 — Direct (P2P) voice

Today *all* media is relayed through the server SFU (`routed, not mixed`), so an N-person channel costs
the host N−1 upstream streams ([RTC](docs/RTC_ARCHITECTURE.md)). For 1:1 calls that is pure overhead.

| Item | Status |
| --- | --- |
| Design a `PeerRelaySession` abstraction beside the existing server transport, starting with 1v1 audio | 🧪 |
| User-visible choice: **Direct** vs **Server** per call/channel, with a safe fallback when direct fails | 📋 |
| Relay capacity accounting + upload-bandwidth guardrails for self-hosters | 📋 |

The concrete change surface (signalling, permissions, server media abstraction, client media layer, ICE)
is listed with `file:line` evidence in [`docs/RTC_ARCHITECTURE.md` §7](docs/RTC_ARCHITECTURE.md).

## Track 5 — Upstream collaboration

| Item | Status |
| --- | --- |
| Propose the small mobile-web fixes upstream: `viewport-fit=cover` + safe-area padding, and iOS standalone meta tags | 🔜 |
| Raise the service worker / offline-shell question upstream as a discussion first (it carries product trade-offs, so it may not be accepted) | 📋 |
| Send general bug fixes upstream rather than keeping them downstream | 🔜 (ongoing) |
| Keep `development` merged forward from `upstream/development` | 🔜 (ongoing) |
| Report back anything the ecosystem needs: protocol versioning, an upstream version endpoint, reconnect parity | 📋 |

Rule of thumb: if a change benefits everyone who self-hosts or writes a client, it belongs upstream. Only
things that are specific to this project's own direction are carried here.

## Track 6 — Self-hosting quality

| Item | Status |
| --- | --- |
| Document the media/ICE constraints that break voice behind tunnels and NAT (announced address, port equality, TCP fallback limits) | 🔜 (partly in [`docs/RTC_ARCHITECTURE.md` §6](docs/RTC_ARCHITECTURE.md)) |
| Diagnose client-side "Failed to initialize voice connection" reports: the server-side flow completes today, so the failure is in the media path — likely announced address or UDP reachability | 🧪 |
| Publish our own pinned image once we ship server-side changes (fingerprint: no `latest`, always a version tag) | 📋 |
| Storage guidance: signed URLs are **off** by default, so attachment URLs are publicly readable unless the server enables signing | 📋 |

## How this roadmap changes

Proposals are welcome as issues. A roadmap item is only promoted to work when its evidence section in
`docs/` is strong enough to describe the change surface — that is the bar this project set for itself, and
it is why the `docs/` set was written before any code was touched.

Milestone numbering here reflects the priority order above (macOS before Windows before iOS). The designs
in [`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md) still apply; only the ordering of the native
tracks was changed.
