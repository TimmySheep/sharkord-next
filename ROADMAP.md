# Sharkord Next — Roadmap

This roadmap is deliberately conservative: it lists what we intend to do, **what we have decided not to
do**, and the evidence behind each decision. Every claim below links to a document in [`docs/`](docs/) that
was written against the actual source at `c611bb4`.

**Languages:** English | [中文](ROADMAP.zh-CN.md)

## Priority order (decided)

1. **macOS, native-first** — Swift + SwiftUI, with a restricted local media worker view.
2. **Windows, native-first** — C# + WinUI 3, with a restricted local media worker view.
3. **iPhone + iPad, native-first** — one Apple project, sharing the Swift core macOS needs anyway.
4. **Apple Watch, native-first** — declared; a wrist push-to-talk client, gated on a feasibility spike.
5. Direct (P2P) voice, then self-hosting quality, in parallel with the native work.

**Android development is now underway** in [`apps/android`](apps/android). PWA/mobile-web work in this
fork remains proposed upstream. Details below.

Status legend: **✅ done** · **🔜 next** · **🧪 needs a spike** · **📋 planned** · **⛔ not doing**

## Guiding principles

1. **Native-first, not native-only.** Prefer a native primary interface, but choose technology for the user experience and total cost, not purity. A bounded web runtime is reasonable when it solves a specific problem well.
2. **Keep the client light, and measure it.** Low idle memory and CPU are product goals. TeamSpeak 3 is the user's personal experience reference; roughly 100 MB or less of idle memory and very low idle CPU are aspirations, not verified TeamSpeak measurements or hard release gates. Report package size, installed size, and runtime use separately.
3. **Stay mergeable with upstream.** We work in upstream's shape so improvements can flow both ways.
4. **Bandwidth-aware.** Self-hosters run out of uplink before they run out of features.
5. **Smallest thing that works.** Upstream's own rule; new abstractions need a second call site.
6. **Verify before claiming.** Compare the whole application process tree on the same Windows device in idle, text use, voice, camera, and screen-share states. Include WebView2 helpers and any bundled server; separate measured results from expectations.

## ⛔ What we are not doing

| Not doing | Why |
| --- | --- |
| **PWA / mobile-web work in this fork** | The three web-client gaps are generic improvements to upstream's client. Fixed upstream, every self-hosted instance and third-party client benefits; fixed here, only we do. Proposed upstream in [Track 6](#track-6-upstream-collaboration). |
| **A full web or Electron wrapper by default** | The native-first client remains the baseline. A wrapper is not categorically forbidden, but it must demonstrate a better overall result, including total process-tree memory and CPU, distribution size, compatibility, and maintenance cost. |
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

## Track 4 — Apple Watch, native (declared fourth)

A wrist-first push-to-talk client: join one voice channel, tap to talk, hear the channel, leave. No text,
one channel at a time. Declared as intent — **not** as a feature promise, because the platform question
below is unanswered and its answer decides whether this ships at all.

**Design work proceeds in parallel; the spike gates the claim.** The interface and its state machine do not
depend on the platform answer, and they are portable to iOS, so they are built alongside W1. What W1 gates is
the claim: nothing here is described as working until the measurement says so.

| Item | Status |
| --- | --- |
| W1: **watchOS networking spike on real hardware** — on a current watchOS, does a single audio-session activation get revoked ~36 s later (Apple defect **FB24377808**), does timer-based renewal hold a session through an hour of real two-way audio, and what does that cost in battery | 🧪 |
| W1b (parallel, independent of W1): **watchOS interface and state machine** — channel list, in-channel push-to-talk, honest **reconnecting** and **degraded** states, and the audio engine behind a swappable interface so the simulator runs the UI with a stub. Built now, portable to iOS | 📋 |
| W2: architecture decision — a server-side ingest bridge (mediasoup `PlainTransport`, the same path FFmpeg/GStreamer sources use) versus a WebRTC stack on the watch, including the transport-encryption consequence either way | 🧪 |
| W3: minimal client — join, push-to-talk, leave, against a real server | 📋 |
| Decide whether the client can exist at all, and record the answer here either way | 🧪 |

Why the watch at all: push-to-talk is the one kind of conversation where a watch beats a phone, and Apple
discontinued its own Walkie-Talkie in watchOS 27. That removal does not help third parties — the system app
ran as a FaceTime-Audio VoIP service, never through the third-party networking exception. The constraints
are documented with primary sources in [`docs/APPLE_WATCH.md`](docs/APPLE_WATCH.md): watchOS grants
low-level networking only for audio streaming, VoIP + CallKit, or tvOS pairing (TN3135); the Push to Talk
framework and the `pushtotalk` push type do not exist on watchOS; the simulator always permits low-level
networking, so only real hardware counts; and the known revocation has a community workaround that is still
unvalidated with real audio.

## Track 5 — Direct (P2P) voice

Today *all* media is relayed through the server SFU (`routed, not mixed`), so an N-person channel costs
the host N−1 upstream streams ([RTC](docs/RTC_ARCHITECTURE.md)). For 1:1 calls that is pure overhead.

| Item | Status |
| --- | --- |
| Design a `PeerRelaySession` abstraction beside the existing server transport, starting with 1v1 audio | 🧪 |
| User-visible choice: **Direct** vs **Server** per call/channel, with a safe fallback when direct fails | 📋 |
| Relay capacity accounting + upload-bandwidth guardrails for self-hosters | 📋 |

The concrete change surface (signalling, permissions, server media abstraction, client media layer, ICE)
is listed with `file:line` evidence in [`docs/RTC_ARCHITECTURE.md` §7](docs/RTC_ARCHITECTURE.md).

## Track 6 — Upstream collaboration

| Item | Status |
| --- | --- |
| Propose the small mobile-web fixes upstream: `viewport-fit=cover` + safe-area padding, and iOS standalone meta tags | 🔜 |
| Raise the service worker / offline-shell question upstream as a discussion first (it carries product trade-offs, so it may not be accepted) | 📋 |
| Send general bug fixes upstream rather than keeping them downstream | 🔜 (ongoing) |
| Keep `development` merged forward from `upstream/development` | 🔜 (ongoing) |
| Report back anything the ecosystem needs: protocol versioning, an upstream version endpoint, reconnect parity | 📋 |

Rule of thumb: if a change benefits everyone who self-hosts or writes a client, it belongs upstream. Only
things that are specific to this project's own direction are carried here.

## Track 7 — Self-hosting quality

| Item | Status |
| --- | --- |
| Document the media/ICE constraints that break voice behind tunnels and NAT (announced address, port equality, TCP fallback limits) | 🔜 (partly in [`docs/RTC_ARCHITECTURE.md` §6](docs/RTC_ARCHITECTURE.md)) |
| Diagnose client-side "Failed to initialize voice connection" reports: the server-side flow completes today, so the failure is in the media path — likely announced address or UDP reachability | 🧪 |
| Publish our own pinned image once we ship server-side changes (fingerprint: no `latest`, always a version tag) | 📋 |
| Storage guidance: signed URLs are **off** by default, so attachment URLs are publicly readable unless the server enables signing | 📋 |

## Android client, in progress

Native Android client development is underway in [`apps/android`](apps/android), using Kotlin and
Jetpack Compose. Current implementation and build instructions are in the [Android app README](apps/android/README.md).

## How this roadmap changes

Proposals are welcome as issues. A roadmap item is only promoted to work when its evidence section in
`docs/` is strong enough to describe the change surface — that is the bar this project set for itself, and
it is why the `docs/` set was written before any code was touched.

Milestone numbering here reflects the priority order above (macOS before Windows before iOS before
watchOS). The designs
in [`docs/NATIVE_STRATEGY.md`](docs/NATIVE_STRATEGY.md) still apply; only the ordering of the native
tracks was changed.
