# Sharkord Next — Ecosystem Research

> 中文版: [ECOSYSTEM_RESEARCH.zh-CN.md](ECOSYSTEM_RESEARCH.zh-CN.md)

**Purpose:** inventory the existing third-party client ecosystem around Sharkord, the upstream project's
official position, and the real state of the current web client's PWA / mobile-web support — so that
Sharkord Next can decide where to **contribute / fork / rewrite** instead of rebuilding blind.

**Evidence rule:** every claim below carries a source. Items are labelled **Verified** (read from
primary source: repo metadata, source file, or command output) or **Unconfirmed** (secondary/README
claim not independently checked). Nothing is asserted from memory.

| Field | Value |
|---|---|
| Research date | 2026-10-06 (UTC) |
| Local repo audited | `~/AWS/sharkord-next` on `tims-mbp` (fork `TimmySheep/sharkord-next`) |
| Fork HEAD | `c611bb4` — `git describe` → `v0.0.25-6-gc611bb4`, branch `development` |
| Upstream remote | `https://github.com/Sharkord/sharkord` |
| Upstream state | ★1527, forks 138, 66 open issues, last push 2026-10-06, MIT |
| GitHub queries run on | MacBook Pro via `gh` (account `TimmySheep`) through proxy `127.0.0.1:7890` |
| Source audit scope | `apps/client/src`, `apps/client/index.html`, `apps/client/public`, `apps/server/src/http` |

---

## 0. Executable conclusions (TL;DR)

1. **Android — do not rewrite. Contribute to / fork `Vigno04/sharkord-android`.**
   It is the *only* real native Android client in existence: Kotlin + Jetpack Compose, MIT, ★15,
   8 releases, and it already implements text, DMs, voice, video and screen share against the
   upstream tRPC-over-WebSocket protocol. Writing a second one from scratch duplicates ~a year of
   work for no protocol advantage. Its one structural weakness is that it is an **independent protocol
   re-implementation with no upstream-tracking guarantee** — which is exactly the gap Sharkord Next
   can close.
2. **macOS (Swift/SwiftUI) and Windows (WinUI 3) are genuinely unclaimed.**
   Zero Swift, iOS, Flutter, React-Native or WinUI clients exist. The desktop space is crowded with
   ~12 thin **Electron wrappers** that just load the web app. A native macOS/Windows client is a real
   differentiator, not a duplicate — and matches the Sharkord Next plan.
3. **The PWA is a manifest without an app.** There is a server-generated `manifest.json` and
   `display: standalone`, but **no service worker anywhere**, **no `viewport-fit=cover`** (so the one
   `env(safe-area-inset-bottom)` rule is inert), and **no iOS standalone meta tags**. The web client is
   a desktop-first SPA that happens to fit on a phone; it is not a installable, offline-capable PWA.
4. **Community demand for exactly this work is already documented upstream:** discussion
   **#105 "Desktop/Mobile App"** (12 comments, active through 2026-08-07) is the single strongest
   signal, and issues **#552 "Reconnect"** / **#778 "re-connect from a different device"** confirm the
   mobile/roaming pain points.

---

## 1. Existing Android Native clients

### 1.1 Inventory

Source: `gh search repos "sharkord android"` + `gh api repos/<repo>` on 2026-10-06.

| Repo | ★ | Language | License | Created | Last push | Real client? | Maintained? |
|---|---|---|---|---|---|---|---|
| **Vigno04/sharkord-android** | 15 | Kotlin | MIT | 2026-05-22 | 2026-08-11 | **Yes** — full native | Yes (8 releases, triaged issues) |
| martintondel02/sharkcordclient | 0 | Rust | MIT | 2026-08-20 | 2026-08-20 | Aspirational | No — single-day burst |
| thalisonnunes20/apk-sharkord | 0 | HTML | MIT | 2026-08-24 | 2026-08-24 | Unconfirmed (WebView wrapper?) | Unknown |
| KillerAuzzie/brozantine-sharkord-android | 0 | — | none | 2026-08-07 | 2026-08-07 | No — APK download mirror | No source |
| rf4burns/Kurier-Android-Installer | 0 | — | none | 2026-09-07 | 2026-09-07 | No — installer for a *fork* (Brozantine/Kurier) | No |

### 1.2 `Vigno04/sharkord-android` — deep dive

**Verified — identity & maintenance**

- `gh api repos/Vigno04/sharkord-android` → MIT, Kotlin, created 2026-05-22, `pushed_at` 2026-08-11,
  0 forks, 1 open issue.
- Releases (`gh api .../releases`): `v0.1.1` 2026-06-30 → `v0.1.2` 07-09 → `v0.1.3` 07-20 →
  `v0.1.4` 07-24 → `v0.1.5` 07-27 → `v0.1.6` 07-30 → `v0.1.7` 08-07 → **`v0.2.0` 2026-08-11**
  (1 APK asset each). Cadence was weekly, then stopped at v0.2.0 (~2 months before this research).
- Commit log (`gh api .../commits`) shows real feature/fix flow: *"Fix Android 14+ FGS crash on screen
  share"*, *"extracted all hardcoded strings to fix #6"*, *"Merge develop into main for v0.2.0 release"*.
- Issue tracker: 13 issues, **12 closed**, 1 open — issue **#12 "Publish the app on F-Droid or
  IzzyOnDroid"**. F-Droid groundwork is in-tree (`fastlane` metadata commit; *"Remove foojay-resolver
  for F-Droid compliance"*).

**Verified — technical stack**

- `app/build.gradle.kts`: `alias(libs.plugins.kotlin.compose)`, `buildFeatures { compose = true }`,
  `namespace com.sharkord.android`, **minSdk 28, targetSdk 36**, `versionName "0.2.0"`.
  → **Kotlin + Jetpack Compose**, modern SDK targets (Android 15/16 era).
- Source tree (`git/trees?recursive=1`) confirms breadth:
  - Networking/protocol: `TrpcProtocol.kt`, `WebSocketManager.kt`, `SharkordClient.kt`,
    `ServerEventHandler.kt`, `HttpClient.kt`, `ParallelDownloader.kt`
  - Media: `VoiceEngine.kt`, `VideoEngine.kt`, `VoiceService.kt` (foreground service),
    `audio/SoundEngine.kt`, `StreamKind.kt`
  - Data/session: `SessionManager.kt`, `MessageSyncWorker.kt`, `ChatRepository.kt`, `ServerRepository.kt`
  - UI: Compose UI + a from-scratch `ui/emojipicker/` (with test tags).
- Scope therefore = **text channels, DMs, voice, video, screen share, emoji, background message sync,
  Android foreground-service voice** — i.e. feature-comparable to the web client for the mobile use case.

**Assessment**

| Dimension | Verdict | Evidence |
|---|---|---|
| Real native (no WebView) | **Verified yes** | Compose plugin + tRPC/WebSocket/media KT sources |
| Still maintained | **Partially** | steady weekly releases Jun–Aug 11, then silent ~2 months |
| Upstream API compatible | **Unconfirmed** | README says only "connect to a Sharkord server"; it re-implements `TrpcProtocol.kt` itself with no stated upstream version pin |
| License suitable to build on | **Verified yes** | MIT (same as upstream) |
| Contribution-ready | **Yes** | issue/PR templates, CONTRIBUTING.md, release workflow |

> Note: Vigno04 also maintains **`Vigno04/discord-selfhosted-alternatives`** (★148) — the author is an
> ecosystem-level actor, not a drive-by. That raises the odds of a productive upstream contribution.

### 1.3 Recommendation — Android

**Contribute first, fork as fallback. Do not rewrite.**

| Option | When to choose | Rationale |
|---|---|---|
| **Contribute to `Vigno04/sharkord-android`** | Default | Compose + MIT + voice/video/screen-share already done. Upstream-compat tracking and PWA-parity UX are the missing pieces and are PR-sized. Fastest path to a credible Android client. |
| **Fork it into `sharkord-next`** | If the maintainer is unresponsive, or the fork needs a divergent design (e.g. shared Rust/Kotlin protocol core, unified branding, upstream-version pinning + CI compat tests) | MIT permits it; but you inherit a Kotlin codebase you must keep alive. |
| **Rewrite from scratch** | Only if a shared cross-platform core (e.g. Rust `martintondel02`-style) is a hard architectural requirement | Throws away working media/session code; no protocol advantage. |

**Do not depend on `martintondel02/sharkcordclient`**: its README advertises *"Android (Kotlin +
Jetpack Compose)"*, but the actual tree contains **only `core/` (Rust) and `desktop/` (egui)** — there
is **no Android module**. All 8 commits landed on a single day (2026-08-20). Treat as roadmap, not code.

---

## 2. Other-platform third-party clients (iOS / macOS / Windows / desktop / CLI)

### 2.1 Inventory

Source: `gh search repos` for `sharkord ios|swift|kotlin|flutter|react native|mobile|cli|desktop|pwa`
+ `gh api search/repositories?q=topic:sharkord`. **Queries for `sharkord ios`, `sharkord swift`,
`sharkord flutter`, `sharkord react native`, `sharkord mobile`, `sharkord cli`, `sharkord pwa`
returned zero distinct client repositories.**

| Repo | Platform | Stack | ★ | License | Last push | Scope | Verdict |
|---|---|---|---|---|---|---|---|
| **Bugel/sharkorddesktop** | Win/Linux/mac | Electron | 15 | MIT | 2026-10-02 | Multi-server, server panel, communities, client-side input/PTT | **Most active desktop client** |
| agrisci/sharkord-client | Win/Linux | Electron | 1 | MIT | 2026-10-03 | Loads web app + 4K60 HW-encoded screen share, system audio, tray, auto-update | Active |
| RND332/sharkord-desktop | Linux/Win/mac | Electron | 0 | MIT | 2026-10-04 | Whole-PC audio minus self; AI-generated ("vibecoded") | Active, experimental |
| captsmuckers/brewer | Linux/Win | Electron | 2 | none | 2026-09-12 | Multi-server rail, per-server session, unread counts | Active |
| reef-sharkord/reef | Desktop | TS (+ server plugin) | 3 | MIT | 2026-08-27 | **Fork of Sharkord client**: multi-server lobby, unified inbox, PTT, saved messages | Active, largest scope |
| Cyphersphere/Sharkord-Client | Windows | Electron | 3 | none | 2026-06-01 | Thin wrapper + PTT + shortcuts | Semi-active |
| Erebaran/SharkordAPP | Desktop | Electron | 1 | none | 2026-08-26 | Thin wrapper | Low signal |
| martintondel02/hammerhead | Desktop | **Tauri 2** | 0 | none | 2026-09-12 | "Native desktop client" (Tauri shell) | New, unproven |
| cr1gger/sharkord-desktop-client | Win/Linux/mac | Electron | 0 | none | 2026-07-19 | Thin wrapper | Stale |
| GoldcrafterXD/sharkord-client | Desktop | Electron | 1 | GPL-3.0 | 2026-02-27 | Thin wrapper | Stale |
| pixelsdontmove/sharkord-thinfin | Desktop | Electron | 1 | GPL-3.0 | 2026-02-16 | "Cartilage-only" thin client | Stale |
| Ricisss/sharkord-meta-client | Desktop | TS | 1 | MIT | 2026-03-04 | Multi-server meta-client | Stale |
| Sweets-omg/Sweetshark-client | Desktop | Electron | 0 | none | 2026-02-24 | "AI coded", proof of concept | Stale |
| thalisonnunes20/app-sharkord | Windows | Electron | 0 | MIT | 2026-09-09 | Extra-official Windows app | Low signal |
| kanuracer/sharkord-desktop-releases | — | — | 0 | none | 2026-07-20 | Release mirror only | N/A |

### 2.2 What the table means

- **Desktop is saturated with thin Electron wrappers** — they do not reimplement the protocol, they
  load the existing web bundle. This is why upstream explicitly selected *"browser + self-host server"*
  as the official desktop story.
- **No iOS, no macOS-native, no Swift, no Flutter, no React-Native, no CLI client exists.**
  The only non-Electron desktop attempt is `martintondel02/hammerhead` (Tauri 2, created 2026-09-12,
  0 stars — unproven).
- **Unclaimed ground that matches the Sharkord Next plan:**
  - **macOS — Swift/SwiftUI** (zero prior art)
  - **Windows — C# WinUI 3** (zero prior art; all Windows clients are Electron)
  - **iPhone/iPad — one unified Apple Mobile target** (zero prior art)
- **Unconfirmed:** whether any Electron wrapper does meaningful protocol work beyond PTT/audio capture.
  The READMEs describe wrappers; no protocol reimplementation was verified in this pass.

---

## 3. Upstream official status

Source: `gh api repos/Sharkord/sharkord`, `.../releases`, `.../labels`, GraphQL `discussions`,
`gh issue list`, and the fork's README/ROADMAP.

### 3.1 The project itself

| Field | Value (verified 2026-10-06) |
|---|---|
| Stars / forks | 1527 / 138 |
| License | MIT |
| Language | TypeScript |
| Created | 2025-10-14 |
| Last push | 2026-10-06 (commits active) |
| Open issues | 66 |
| Distribution | standalone binary bundling **server + client**, plus Docker image `sharkord/sharkord` |

### 3.2 Official client form: Web only

**Verified** from upstream README (also present in the fork's tree):

- *"Sharkord is distributed as a standalone binary that bundles both server and client components."*
- *"Once the server is running, open your web browser and navigate to `http://localhost:4991` to access
  the Sharkord client interface."*
- Client stack in-tree: React + Vite + Redux Toolkit + Tailwind, i18n (8 locales in the fork's tree:
  `cs, en, es, fr, it, pt-BR, ru, zh`), mediasoup client for voice/video.
- **There is no official native desktop or mobile client.** The "desktop" story *is* the browser.

### 3.3 Release cadence

`gh api .../releases`:

| Tag | Published |
|---|---|
| v0.0.25 | 2026-09-04 |
| v0.0.24 | 2026-08-27 |
| v0.0.23 | 2026-07-10 |
| v0.0.22 | 2026-05-22 |
| v0.0.21 | 2026-05-22 |
| v0.0.20 | 2026-05-13 |

→ Roughly monthly through v0.0.24, then **no release for ~1 month while commits continue daily**
(last push 2026-10-06). Still alpha by the project's own note (*"Sharkord is in alpha stage… breaking
changes are to be expected"*). Release slowdown is a real compat risk for any third-party client.

### 3.4 Plugin ecosystem

**Verified** — official org repositories: `Sharkord/plugins`, `Sharkord/plugin-example`,
`Sharkord/music-bot`, `Sharkord/iptv`, `Sharkord/klipy`, `Sharkord/website` (all pushed 2026-09-04…26),
plus an in-monorepo SDK at `packages/plugin-sdk`. Issue labels include **`plugin-sdk`** and
**`good first issue`**.

Community plugins (repos verified via search): `rinky-dinky/sharkord-soundboard`,
`remynaps/sharkord-whip-plugin`, `diogomartino/sharkord-music-bot`, `diogomartino/sharkord-iptv`,
`Salaron/sharkord-lava-plugin`, `sponger544/sharkord_ai_plugin`, `EssekerDev/sharkord-rss`,
`Popoboxxo/sharkord-CastMate`, `degyster/sharkord-extensions`, `0x6DD8/discord-sharkord-bridge`.
Community index: `Sweets-omg/sharkord-community-creations` (★6, community-maintained, explicitly
**"not reviewed, audited, or endorsed"**).

> **Architectural caveat for native clients (from `martintondel02` README, unverified in source):**
> the upstream plugin system "loads JS/React bundles in-process", which native clients cannot host.
> If confirmed, any native client ships **without** plugin support — a scope decision, not a bug.

### 3.5 Official roadmap

`ROADMAP.md` (fork mirrors upstream): Short term = *core features & stability, QoL, bug fixes, extend
plugin SDK, docs/DX*. **Medium Term = TODO. Long Term = TODO.**
→ There is **no published official native mobile/desktop plan.**

### 3.6 Community attention evidence (most active threads)

| Thread | Type | Comments | Last activity | Link |
|---|---|---|---|---|
| **Desktop/Mobile App** | Discussion (Ideas) | **12** | 2026-08-07 | https://github.com/Sharkord/sharkord/discussions/105 |
| Sharkord is not actively releasing any updates anymore? | Discussion | 5 | 2026-08-07 | https://github.com/Sharkord/sharkord/discussions/760 |
| Firefox Issues | Discussion | 5 | 2026-09-25 | https://github.com/Sharkord/sharkord/discussions/449 |
| **#552 [Feature]: Reconnect** | Issue (`feature,future`) | 2 | 2026-03-17 | https://github.com/Sharkord/sharkord/issues/552 |
| #778 [Feature]: Allow re-connect from a different device when in voice | Issue (`feature`) | 0 | 2026-08-08 | https://github.com/Sharkord/sharkord/issues/778 |
| #756 webrtc: announcedAddress hostname breaks Firefox (ICE) | Issue (`bug`) | 10+ | 2026-08-28 | https://github.com/Sharkord/sharkord/issues/756 |
| #695 Audio input stops after ~10s (UDP 40000 / proxy) | Issue (`bug`) | 10+ | 2026-08-05 | https://github.com/Sharkord/sharkord/issues/695 |
| #785 RTL text support (Arabic/Persian) | Issue (`feature`) | 0 | 2026-08-19 | https://github.com/Sharkord/sharkord/issues/785 |

Discussion #105 body (verbatim, verified): *"Could this easily be wrapped in a capacitor app and or
electron app? Authentication process would be similar to a plex or jellyfin server and could even hold
multiple 'servers'… If anyone is interested I could give this a shot as well, not sure if the developers
would want this under their own repo."*

---

## 4. Current Web client — PWA / Mobile Web audit

Method: direct source inspection of the fork's working tree (`apps/client`, `apps/server/src/http`);
no runtime testing — all statuses are **source-verified**.

### 4.1 Where the PWA pieces live

- `apps/client/index.html:6` → `<link rel="manifest" href="/manifest.json" />`
- `apps/server/src/http/index.ts:82` → register route `'/manifest.json': manifestRouteHandler`
- `apps/server/src/http/manifest.ts` → **the manifest is generated at runtime**, not a static file
- `vite.config.ts` proxies `/manifest.json` to the dev server in development
- `apps/client/public/` → only `favicon.ico`, `icon-192.png`, `icon-512.png`, `logo.webp`,
  `robots.txt`, and audio worklets. **No `sw.js`, no `workbox`, no `manifest.webmanifest`.**

### 4.2 Manifest contents (verified, `apps/server/src/http/manifest.ts`)

```
name:             settings.name
short_name:       settings.name.slice(0, 12)
description:      settings.description ?? ''
start_url:        '/'
display:          'standalone'
background_color: '#171717'
theme_color:      '#171717'
icons:            /icon-192.png + /icon-512.png  (or the server logo if square; SVG allowed)
```
Served as `application/manifest+json`, `Cache-Control: public, max-age=3600`.

**Missing fields:** `scope`, `id`, `orientation`, `categories`, `screenshots`, `dir`, `lang`,
`prefer_related_applications`, and any `purpose: "maskable"` icon.

### 4.3 Item-by-item status

| Item | Status | Evidence / file |
|---|---|---|
| Manifest linked in HTML | **Implemented** | `apps/client/index.html:6` |
| Manifest served with correct type | **Implemented** | `apps/server/src/http/manifest.ts:103-106` |
| `start_url` + `display: standalone` | **Implemented** | `manifest.ts:95-96` |
| Manifest completeness (id/screenshots/scope/orientation) | **Not implemented** | absent from `manifest.ts` |
| **Service worker (offline, precache, runtime cache)** | **Not implemented** | zero matches for `serviceWorker`/`workbox`/`registerSW` in `apps/client/src`, `apps/server/src`, `packages`; no `sw.js` in `dist/` |
| **Web Push when app closed** | **Not implemented** | only Notifications API used (`features/app/actions.ts:153-179`, `helpers/assert-notifications-permission`); no `PushManager` |
| PWA install prompt handling | **Not implemented** | no `beforeinstallprompt` / `display-mode` / standalone detection in client source |
| `viewport-fit=cover` | **Not implemented** | `index.html:7` = `width=device-width, initial-scale=1.0` only |
| iOS standalone (`apple-mobile-web-app-capable`) | **Not implemented** | zero matches repo-wide |
| iOS home-screen title / icon | **Implemented (runtime)** | `features/app/actions.ts:62-63` sets `apple-touch-icon` + `apple-mobile-web-app-title` |
| iOS splash / status-bar style | **Not implemented** | no `apple-touch-startup-image`, no `status-bar-style` |
| Safe-area insets | **Partial / inert** | only `message-compose/index.tsx:263` `pb-[env(safe-area-inset-bottom)]`; inert without `viewport-fit=cover` |
| Dynamic viewport height | **Implemented** | `h-dvh` in `screens/server-view/index.tsx:85` and `server-screens/settings-shell/index.tsx:102` |
| Mixed fixed viewport unit | **Partial** | `index.css:141` `#root { min-height: 100vh }` |
| Touch swipe gestures | **Implemented (narrow)** | `hooks/use-swipe-gestures.ts`, wired only in `screens/server-view/index.tsx:66` |
| Touch scrolling / overscroll / tap-highlight tuning | **Not implemented** | no `touch-action` / `overscroll-behavior` / `user-select` rules |
| Responsive breakpoints | **Partial (sparse)** | client/src utility count: `md:` ×23, `lg:` ×18, `sm:` ×16, `xl:` ×1; only one bespoke media query `@media (max-width:700px)` (`index.css:447`, masonry grid only) |
| Mobile navigation shell | **Implemented** | overlay drawers in `server-view/index.tsx` (`md:hidden` / `lg:hidden` backdrops, `isMobileMenuOpen` / `isMobileUsersOpen`) |
| Reconnect | **Implemented** | `features/server/actions.ts:135` `RECONNECT_DELAYS_MS = [1000,2000,4000,8000,8000]`, reconnect slice/selectors |
| State restoration across reload | **Implemented (partial)** | `helpers/storage.ts` `LocalStorageKey` (theme, notifications, session); no service-worker-level state |
| i18n | **Implemented** | 8 locales: `cs, en, es, fr, it, pt-BR, ru, zh` |

### 4.4 Interpretation

- The client is a **desktop-first SPA that degrades to a usable phone layout** — not a PWA.
  `display: standalone` in the manifest is not a claim the app can honour, because there is no
  service worker and, on iOS, no `apple-mobile-web-app-capable`.
- Consequence on **iOS Safari**: "Add to Home Screen" produces a Safari-UI shortcut, not a
  standalone app shell. On non-`cover` viewports the `safe-area` inset evaluates to `0`, so the one
  safe-area rule currently does nothing on notched devices.
- Consequence on **Chromium**: with no service worker, no `id` and no `screenshots`, the richer
  install prompt is unreliable; users effectively get "Create shortcut". No offline behaviour at all.
- The three user-visible pain points the audit maps to are exactly the ones the plan already targets:
  **install/offline, safe-area/status-bar, and touch-density.**

---

## 5. Recommendations

### 5.1 Android — **contribute to `Vigno04/sharkord-android`**

| Why contribute | Why not rewrite | Fork trigger |
|---|---|---|
| Only real native Android client exists; Compose + MIT; voice/video/screen-share/DMs/emoji/background-sync already implemented and shipping weekly (until v0.2.0). | Reimplementing the tRPC-over-WS protocol + mediasoup mobile client duplicates months of work with no protocol advantage. | Fork if (a) maintainer unresponsive, (b) you need a shared cross-platform core, or (c) you need a hard upstream-version pin + CI compat tests that the current project won't adopt. |
| The concrete gaps are PR-sized and match Sharkord Next goals: upstream-version pinning + compat CI, F-Droid publishing (#12), reconnect parity, and PWA-parity UX. | The `martintondel02` "shared Rust core" alternative has **no Android module** today — it is a roadmap, not a base. | MIT license makes a fork legally clean. |

### 5.2 macOS / iOS / Windows — **build native, it is unclaimed**

- Zero Swift/SwiftUI, iOS, Flutter, React-Native, or WinUI 3 clients exist (verified search sweep).
- The desktop field is ~12 Electron wrappers, which upstream deliberately does not compete with.
- Therefore **one unified Apple Mobile project (iPhone+iPad) + a SwiftUI macOS client + a C# WinUI 3
  Windows client** is additive, not duplicative — and is the strongest differentiated bet in this
  ecosystem. The protocol entry point for any of them is `tRPC`-over-WebSocket + HTTP file upload
  + mediasoup signalling (the same surface `Vigno04` and `martintondel02` implement natively).

### 5.3 PWA — the three biggest gaps, ranked

| # | Gap | Why it matters | Concrete fix |
|---|---|---|---|
| 1 | **No service worker** (`serviceWorker` has zero matches repo-wide; no `sw.js` in `dist/`) | No offline shell, no precache, no Web Push when the app is closed, unreliable install prompt. This is the difference between "installable app" and "bookmark". | Add a Workbox/Vite-PWA service worker: precache app shell + hashed assets, runtime-cache static media, register in `main.tsx`; wire `PushManager` for background notifications. |
| 2 | **No `viewport-fit=cover` + only one inert safe-area rule** (`index.html:7`; `message-compose/index.tsx:263`) | On notched iPhones the bottom composer sits under the home indicator; keyboard/notch overlap. `env(safe-area-inset-*)` currently resolves to `0`. | Change meta to `width=device-width, initial-scale=1.0, viewport-fit=cover`; add safe-area padding for top/left/right on the shell (`server-view`, `settings-shell`, topbar). |
| 3 | **No iOS standalone meta / sparse mobile layout** (no `apple-mobile-web-app-capable`; only 58 breakpoint utilities vs a desktop-first shell; no `touch-action`/`overscroll-behavior`) | iOS "Add to Home Screen" opens in Safari chrome instead of an app shell; touch targets and scroll chaining are untuned. | Add `apple-mobile-web-app-capable=yes` + `status-bar-style` + `apple-touch-startup-image`; raise mobile breakpoint coverage on the topbar/sidebars; add `touch-action`/`overscroll-behavior: contain` on scroll containers. |

### 5.4 Where the community is — go here first

1. **Discussion #105 "Desktop/Mobile App"** — https://github.com/Sharkord/sharkord/discussions/105
   (12 comments, the single most-engaged thread on the topic; upstream has not committed to it).
2. **Issue #552 "Reconnect"** (`feature,future`) — https://github.com/Sharkord/sharkord/issues/552
   and **Issue #778** — https://github.com/Sharkord/sharkord/issues/778 (mobile/roaming reconnect).
3. **Voice/networking bugs that hit mobile hardest**: #756 (ICE/FQDN), #695 (UDP :40000 via proxy),
   #795 (Firefox screen-share black screen) — these shape whether a mobile client is usable off-Wi-Fi.

---

## 6. Method & reproducibility

Commands used (run on `tims-mbp`, proxy exported):

```bash
export HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890
export PATH=/opt/homebrew/bin:$PATH
# ecosystem sweep
gh search repos "sharkord android|ios|swift|kotlin|flutter|react native|mobile|cli|desktop|pwa"
gh api "search/repositories?q=sharkord+in:name,description,readme&sort=stars&per_page=60"
gh search repos --topic sharkord-plugin
# per-repo facts
gh api repos/<owner>/<repo>            # stars, license, pushed_at, archived
gh api repos/<owner>/<repo>/commits    # recency + intent
gh api repos/<owner>/<repo>/releases   # cadence
gh api "repos/<owner>/<repo>/git/trees/HEAD?recursive=1"   # real stack (quote the URL!)
# upstream
gh api repos/Sharkord/sharkord
gh api "repos/Sharkord/sharkord/releases?per_page=12"
gh api graphql -f query='{repository(owner:"Sharkord",name:"sharkord"){discussions(first:25,...){...}}}'
gh issue list --repo Sharkord/sharkord --state open --limit 40
# local source audit
grep -rniE "serviceWorker|workbox|registerSW" apps/client/src apps/server/src packages
grep -rniE "viewport|safe-area|apple-mobile-web-app|touch-action|overscroll" apps/client/src apps/client/index.html
cat apps/server/src/http/manifest.ts
```

**Constraints honoured:** no upstream source modified, no `git commit`/`push`, the production Docker
instance at `/home/timmy/sharkord` was not touched. Working tree was read-only throughout.

### Open / unconfirmed items

- **Unconfirmed:** whether `Vigno04/sharkord-android` pins or tests against a specific upstream version
  (its README is silent; a compat statement was not found).
- **Unconfirmed:** whether the plugin runtime truly cannot be hosted by native clients
  (`martintondel02` README claim only), and the exact install-prompt behaviour on real
  Chrome/Safari devices (source-level analysis only; no device test performed).
- **Unconfirmed:** whether any Electron wrapper does protocol work beyond PTT/audio capture.
