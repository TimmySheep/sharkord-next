# Apple Watch client — declared intent, and the gate it has to pass

**Languages:** English | [中文](APPLE_WATCH.zh-CN.md)

This is the evidence behind [Track 4](../ROADMAP.md#track-4-apple-watch-native-declared-fourth). Every
platform claim below links to Apple's own documentation; every measurement links to the developer report it
came from. Where something is genuinely unknown, this document says so instead of guessing.

**Status: declared, not promised.** The client is an intention. Whether it can exist at all is decided by
the spike in §5, and that result will be recorded here either way.

## 1. What the client is

A wrist-first push-to-talk client, and nothing more:

- **Join** one voice channel, **tap to talk**, **hear the channel**, **leave**.
- No text, no DMs, no channel administration. One channel at a time.
- Not a shrunk iPhone app: the watch *is* the product, because push-to-talk is the one kind of conversation
  where a watch beats a phone.

Apple discontinued its own Walkie-Talkie in watchOS 27 — "With watchOS 27, Walkie-Talkie has been
discontinued" ([Apple support](https://support.apple.com/en-us/108416)). That leaves the form factor
unoccupied, but §3 explains why it does **not** mean the platform became friendlier to third parties.

## 2. What watchOS allows a third-party app

[TN3135 — Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)
is the authoritative statement, and it is more restrictive than most people assume:

| Rule (TN3135) | Consequence here |
| --- | --- |
| High-level networking — HTTP/HTTPS via `URLSession` — works for every app | Enough for the text/API surface; not enough for voice |
| Low-level networking — `Network.framework`, TCP, UDP, `URLSessionWebSocketTask` — is allowed **only** (a) while an audio-streaming app is actively streaming audio, (b) while a VoIP app runs a call using CallKit (watchOS 9+), (c) for a tvOS pairing listener | The entire design depends on exception (a) |
| The **BSD sockets API does not work on watchOS under any circumstances** | No raw socket code; everything must go through `Network.framework` |
| Outside those exceptions the app gets `ENETDOWN` and `NWPathMonitor` stays `.unsatisfied` | A normal app cannot hold a socket at all |
| **The simulator always allows low-level networking** | Anything measured in the simulator is worthless. Real hardware, every time |

Two more platform facts, each from Apple's documentation:

- **There is no Push to Talk on watchOS.** The [Push to Talk framework](https://developer.apple.com/documentation/pushtotalk)
  lists iOS 16+, iPadOS 16+, Mac Catalyst 16+ — watchOS is not among them — and the APNs `pushtotalk` push
  type is documented only for those platforms. There is therefore **no system-managed background wake-up**
  for a push-to-talk app: if no session is running, nothing can ring the app awake. That is exactly why this
  client is designed to exist **inside** an explicit session ("join … leave") rather than as an
  always-listening pager.
- **A background audio session buys runtime only while audio plays.** Apple: the background audio mode
  "provides additional runtime as long as the audio plays"
  ([Using extended runtime sessions](https://developer.apple.com/documentation/watchkit/using_extended_runtime_sessions)).
  Read the condition carefully — *as long as the audio plays* — and then consider a push-to-talk room, which
  is silent most of the time. §3 is what happens next.
- **Frontmost is not permanent.** A frontmost app returns to the clock after two minutes by default; the
  Always On display keeps showing it while it is frontmost **or** running a background session
  ([Taking advantage of frontmost app state](https://developer.apple.com/documentation/watchkit/taking-advantage-of-frontmost-app-state)).
  A running audio session is what keeps the app practically alive.

## 3. The open defect that gates the whole idea

This is the part that is usually missing from optimistic write-ups, and it is the reason this client is
declared rather than scheduled.

**The report.** Apple Developer Forums thread
[841590](https://developer.apple.com/forums/thread/841590) — "Does the TN3135 audio-session networking
exception have a defined lifetime? Seeing a ~38.5 s revoke/re-grant cycle" (August 2026, Apple Watch Series
10 on watchOS 26.5, reproduced on a Series 6). Setup: `UIBackgroundModes: [audio]`, `AVAudioSession`
`.playAndRecord` / `.spokenAudio`, one `NWConnection` WebSocket over TLS.

**The measurements.** Overnight, 1,549 samples over 19 hours, logged server-side:

| Metric | Value |
| --- | --- |
| Median session length | **38.5 s** |
| Mean / standard deviation | 38.60 s / 0.62 s |
| 5th–95th percentile | 37.9 – 39.2 s |
| Sessions inside 35–40 s | 97.9% (only 21 of 1,549 fell outside 30–50 s) |
| Outage per cycle | consistently ~2.0 s |

**The minimal reproducer.** A watch app that activates the audio session, opens one `NWConnection` to
`www.apple.com:443`, and does nothing else — no microphone, no audio engine, no playback, no retry:

- path **revoked 35.5 s after the single activation**;
- the connection then failed with `POSIXErrorCode 9: Bad file descriptor`;
- because it never re-activated, the path stayed `.unsatisfied` for **8 min 50 s** — it does **not** come
  back on its own. Recovery requires **another activation**.

**What Apple says.** Apple DTS (Quinn "The Eskimo!") confirmed the behaviour is a defect: the system should
ignore a redundant activation, and a fix is tracked as **FB24377808** — "To be clear, it's definitely
misbehaviour". After the reporter removed the redundant activations, the cycles continued anyway, including
after the *first* activation on a fresh launch and after a 7.5-minute quiet period, so the defect is not
explained by the redundant-activate path alone. As of the reporter's last update (2026-08) the thread had no
resolution, and another developer reported the same behaviour in the same period.

**Why the system Walkie-Talkie is not a counter-example.** On the same watch, Apple's own Walkie-Talkie held
sessions well beyond 38.5 s — but it runs as a system VoIP service over FaceTime Audio, not through the
third-party TN3135 exception. Its removal in watchOS 27 does not transfer that capability to anyone else.

**What this means for the design.** The audio-streaming exception behaves less like a long-lived grant and
more like **roughly 36 seconds per activation**: activate, get a path, lose it, and rebuild. Naively that
means a reconnect every half minute — survivable but visible for a walkie-talkie, and disqualifying for a
"sit in the channel all evening" product.

**The mitigation, and why it changes the picture.** Later in the same thread the reporter isolated the
mechanism: the revocation is scheduled relative to the most recent `activate(options:completionHandler:)`,
and a subsequent activation **replaces** the pending revocation instead of adding another — so re-activating
before the deadline moves it, indefinitely. In the measured run, a second activation 20 s after the first
moved the revocation to 36.5 s after the *second* activation (rather than 58.1 s after the first), and in the
reporter's words the re-activation disturbed neither the path nor an open connection. If that holds, a client
holds its socket open by **renewing the audio session on a short timer** rather than reconnecting after each
drop. This is a **community finding, not an Apple statement**, and it has four unverified edges:

- every public measurement used a probe with **no microphone, no audio engine and no playback** — nobody has
  shown this holding while real audio streams;
- "indefinitely" is the reporter's word; no multi-hour continuous run has been published;
- it has **not** been retested on watchOS 27 (the thread's last activity was 2026-09-05; the report was made
  on watchOS 26.5);
- battery cost is unmeasured.

Two further wrinkles:

- TN3135 conditions the exception on *actively streaming audio*, and a PTT room is silent most of the time.
  Streaming continuous silence did not prevent the cycle in the reported case (still 36.4 s).
- The one other legal door is exception (b), VoIP + CallKit (watchOS 9+), which does grant lasting low-level
  networking — but it presents as a *call*: system call UI, ringing semantics. That is a different product
  from a channel-based intercom.

**Where this stands (as of 2026-10).** Thread opened 2026-08-11; the defect was filed in mid-August and the
reproducer plus a sysdiagnose attached on 2026-08-21; Apple's last reply in the thread was 2026-09-05, after
which the DTS engineer said he was stepping out of the loop with the fix tracked by the report. Seven weeks is
young for Feedback Assistant — silence there is neither a promise nor a dismissal — but a fix at this layer
would realistically arrive with a system release rather than a point update, so this is not something to wait
on. The two questions that actually matter are answerable on our own hardware: does the renewal hold with real
audio, and does it still hold on watchOS 27?

We also checked the obvious hope: WWDC26 session 226,
[Create live communication experiences](https://developer.apple.com/videos/play/wwdc2026/226/)
(`LiveCommunicationKit`, the `CXProvider` successor). Its full transcript does not mention watchOS at all —
it is an iOS system-UI integration story, and it does not change the three exceptions in TN3135.

## 4. Media: why the watch will not run WebRTC

Sharkord's voice is [mediasoup](https://mediasoup.org) WebRTC — DTLS-SRTP, ICE, RTP over UDP — not raw Opus
packets over a socket (see [`RTC_ARCHITECTURE.md`](RTC_ARCHITECTURE.md)). A watch client cannot simply
"send Opus", so there are only two routes:

| Route | Cost |
| --- | --- |
| **A. Port WebRTC to watchOS** — `libmediasoupclient` plus `libwebrtc`, cross-compiled for arm64_32 | Very high. `libmediasoupclient` is C++ on top of `libwebrtc`; even the iOS builds are large enough that community clients ship the static library out-of-band. On watchOS it also has to live inside a tight CPU/power budget, and sustained high CPU is grounds for the system to cancel a session. |
| **B. Add a server-side ingest bridge** — take the watch's audio as a plain RTP/Opus source via mediasoup `PlainTransport`, the same mechanism mediasoup documents for ingesting FFmpeg/GStreamer sources, and fan it out to the channel | Moderate, and it is server-side work in a stack we already control. The watch then only needs Opus plus a socket. |

**Direction: B.** The expensive part (a full WebRTC stack) stays on the server, where it already exists, and
the watch client stays small enough to fit the platform's constraints. One consequence is explicit and needs
a decision rather than a default: `PlainTransport` carries **unencrypted** RTP, so the bridge must either
live inside a tunnel (WireGuard/Tailscale) or the audio must be wrapped with SRTP. That is a privacy
question, not a performance one, and it will be settled in W2.

## 5. The spike: three numbers, on real hardware

The measurement gates the **claim**, not the design work. The interface and its state machine are built in
parallel — they do not depend on the answer and are portable to iOS — but nothing is described as working
until the three numbers below exist.

| # | Measurement | Method |
| --- | --- | --- |
| 1 | Is a single audio-session activation revoked ~35–38 s later? | Minimal probe: activate once, hold one `NWConnection`, log `NWPathMonitor` transitions and socket state for 30 minutes |
| 2 | Does renewing the session on a timer hold the path — **with real audio streaming both ways**? | A probe that renews the audio session every ~20 s for at least 60 minutes while real two-way Opus audio runs, logging path state, connection state, audible gaps and dropped frames |
| 3 | What does 30 minutes of an open session cost in battery? | Same probe, percentage drain per 30 minutes, then extrapolate to an hour |

**Acceptance.** If (2) holds a session for an hour of real two-way audio with no audible gap on a current
watchOS, and (3) permits hour-long sessions, the client is buildable as designed. If not, the honest outcomes are: move to the CallKit door (different
product), redesign around connect-on-demand, or state plainly that a wrist client is not viable on watchOS
today. Any of those is a better result than shipping a stutter.

**Rule for this project:** never conclude anything about watchOS networking from the simulator. TN3135 is
explicit that the simulator always permits low-level networking; the simulator is a false-positive machine
for exactly this question.

## 6. Prior art

- **WatchCord** ([App Store](https://apps.apple.com/us/app/watchcord-for-discord-server/id6677009916))
  advertises itself as "the first app supporting Discord Voice Chat on Apple Watch". Its published feature
  list mixes text and voice, and its instructions require signing in through the companion iPhone app, so it
  does not by itself demonstrate a standalone watch voice session. Unverified either way; worth inspecting
  before writing our own.
- **Apple's Walkie-Talkie** ran as a system VoIP service and was discontinued in watchOS 27. It was never
  available as a pattern for third-party apps.
- **PushToTalk-based walkie-talkie apps** (the WWDC22 `Push to Talk` design) target iOS; that framework does
  not exist on watchOS, so those apps are phone apps with a watch remote at best.

## 7. Open questions

1. Does the timer-based renewal hold on **watchOS 27**, and did the defect change with that release? Nobody
   has retested since 2026-09-05.
2. Does the renewal hold indefinitely, and does it hold while genuinely non-silent audio streams? Every public
   measurement used a probe with no microphone, no audio engine and no playback.
3. Does renewal survive platform interruptions — an incoming call, Siri, a session left open for hours with
   the wrist down — or does any of those reset the clock in a way that cannot be renewed through?
4. Is exception (b) (VoIP + CallKit, watchOS 9+) usable for a channel-based intercom, given its call
   semantics, and would Apple's review accept that framing?
5. What is the real battery cost per hour of an open session, and does the system's CPU/power policy ever
   cancel the session mid-conversation?
6. Is the unencrypted `PlainTransport` route acceptable when the server is reached over the public internet,
   or must the bridge add SRTP (and what does that cost on the watch side)?

## Sources

- [TN3135 — Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)
- [Push to Talk framework](https://developer.apple.com/documentation/pushtotalk) (iOS 16+, iPadOS 16+, Mac Catalyst 16+)
- [Using extended runtime sessions](https://developer.apple.com/documentation/watchkit/using_extended_runtime_sessions)
- [Taking advantage of frontmost app state](https://developer.apple.com/documentation/watchkit/taking-advantage-of-frontmost-app-state)
- [Use Walkie-Talkie on your Apple Watch](https://support.apple.com/en-us/108416) (discontinued in watchOS 27)
- [Apple Developer Forums thread 841590](https://developer.apple.com/forums/thread/841590) — the ~38.5 s revoke cycle, Apple defect **FB24377808**
- [WWDC26 session 226 — Create live communication experiences](https://developer.apple.com/videos/play/wwdc2026/226/) (checked in full: no watchOS content)
- [mediasoup documentation](https://mediasoup.org/documentation/v3/mediasoup/) — plain transports, the ingestion path intended for external RTP sources
