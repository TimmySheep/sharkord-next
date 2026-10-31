# Desktop native clients: web feature parity and real-server acceptance

## Goal

Make the native Windows client (`apps/windows`) feature-complete against the web client
(`apps/client`): every feature the web client offers today must exist in the Windows client.
The macOS client (`apps/macos`) should reach the same parity where the platform allows it.
Acceptance is demonstrated with automated tests plus end-to-end exercise against a real,
publicly reachable Sharkord server.

This builds on `2026-10-desktop-native-discord-ui.md` (build health, Discord-style UI, wire
compatibility). Do not regress anything that task established.

## Feature parity definition

"Feature-complete" means: for each user-visible capability of the web client, the native
client has an equivalent path. Audit `apps/client` (routers, components, features) and produce
a parity table in this file's Progress section: capability | web reference | Windows status |
macOS status. At minimum cover:

- Connect/login (password; OIDC only if the web client exposes it to this server).
- Server navigation: categories, channels, DMs, group DMs, unread indicators, jump-to-channel.
- Messaging: send, edit, delete, replies/threads, reactions, typing indicators, read states,
  message search (messages + files), pagination and load-older.
- Attachments: pick, upload with progress, image preview, open other file types.
- Members: roster, roles, user profile card, permissions-aware UI.
- Voice: join/leave voice channels, mute/deafen, speaking indicators, receive-quality controls.
- Camera publish and screen sharing (MediaProjection path already exists — keep it working).
- Settings: user settings, language picker (existing 10 locales), server settings surfaces
  where the web client exposes them to a normal user.
- Emoji: rendering, picker, custom emojis from the server.
- Reconnect/recovery: offline handling, backoff, state resync after reconnect.

Where a gap is found, implement it following `AGENTS.md` patterns. If a capability genuinely
cannot be replicated natively (document with evidence, e.g. platform API limits), list it in
the parity table as DEFERRED with the reason — do not silently skip.

## Real-server acceptance

- Target server: `https://voice.timhuang.net` (verified reachable, `/info` reports
  `allowNewUsers: true`).
- Account: create a fresh throwaway test account via the normal registration/login flow the
  web client uses. Username must be `测试` (or `测试2`/`测试3`… if taken). Choose a strong
  random password yourself. Store credentials ONLY in `C:\Users\YY\codex-task\server-creds.txt`
  (outside the repo); never commit credentials, tokens, or the creds file to git.
- Do not disturb existing users or data on that server: use your own test channel(s)/DMs for
  destructive tests (edit/delete/react). Do not delete or modify content you did not create.
- Automated end-to-end tests: extend the existing gated integration suites
  (`SHARKORD_IT_HOST` pattern, `--filter` gating) so they can run against the real server with
  the creds file. Cover at minimum: login → handshake → join → send/receive → edit → delete →
  reaction → reply/thread → typing → read state → upload → fetch `/public` URL → reconnect
  resync. Tests must stay no-op when no target/creds are configured so CI remains green.
- Run the full local suite (`dotnet build -p:Platform=x64`, `dotnet test`) plus the real-server
  run; record actual output in the Progress section.

## GUI acceptance with Computer Use

- Where a feature can only be proven through the UI (visual layout, voice join feedback,
  attachment preview), use the Codex Computer Use / CUA capability on this Windows machine to
  drive the built app: launch `cove.exe`, log in with the test account, exercise the flow,
  and capture what you observe. Screenshot evidence may be saved under
  `C:\Users\YY\codex-task\evidence\` (outside the repo).
- If CUA is unavailable or unstable in this environment, say so explicitly and fall back to
  precise manual acceptance steps for the user — do not claim UI acceptance you did not
  perform.

## Constraints

- Same as before: no server changes, no pushes to origin (local commits only on
  `feat/desktop-parity`), no machine-wide installs, no Electron.
- macOS work remains code-complete-but-Mac-verify-only; mark it clearly.

## Progress

### Initial parity audit, 2026-10-31 (before implementation)

The current user instruction selects `feat/desktop-parity`, superseding the earlier branch
name above. Baseline commit: `fa67ffd`. The checkout was clean. Read both taskbooks,
`AGENTS.md`, `CONTRIBUTING.md`, both native READMEs, and audited the web screens,
components, features, matching server routes and both native implementations.
PRESENT means an implemented path found in source, not completed runtime acceptance.
PARTIAL and MISSING are implementation work, not platform deferrals. All macOS statuses
are source-only until `swift build && swift test` runs on a Mac.

Web paths below are relative to `apps/client/src/`. Native paths are relative to each
platform's source directory. The initial findings are retained so later results can be
compared with this audit.

| Capability | Web reference | Windows initial status | macOS initial status |
| --- | --- | --- | --- |
| Server preview, registration/password login, server password | `screens/connect`, `features/server/actions.ts` | PRESENT, HTTP login and handshake/join | PRESENT |
| Invite registration, automatic login | `screens/connect/index.tsx` | PARTIAL, HTTP supports invite, no invite/remember-login UI | PARTIAL, Keychain automatic login, invite path incomplete |
| OIDC | `screens/connect/hooks/use-oidc-login.ts` | NOT APPLICABLE to acceptance server: `/info` reports disabled | Same |
| Categories, collapsible channel tree, topics, last selected channel | `components/left-sidebar`, `channel-view/text/text-top-bar.tsx` | PRESENT | PRESENT |
| Channel/category create, rename, delete, reorder and access overrides | `context-menus`, `server-screens/channel-settings`, `category-settings` | MISSING native navigation management paths | PRESENT |
| Existing DMs and starting a DM from member/search | `left-sidebar/direct-messages`, `user-popover` | PARTIAL, list and Core open exist; no new-DM UI; VOICE-typed DM disables text path | PRESENT |
| Group DMs | `left-sidebar/direct-messages`; server `routers/dms` | NOT AVAILABLE upstream: only `open({ userId })` and two-member conversation model | Same; cannot add without prohibited server changes |
| Unread counts, mark read, new-message divider | `features/server/messages`, `channels`, `channel-view/text` | PRESENT; reconnect resync needs correction | PRESENT |
| Jump to channel/message, return to present | `dialogs/search`, `channel-view/text/hooks` | MISSING target-window/jump UI | PRESENT, thread result navigation needs review |
| Send, edit, delete, edit keyboard shortcuts | `channel-view/text`, `message-compose` | PRESENT for own messages; moderator action missing | PRESENT |
| Inline replies | `message-compose`, `channel-view/text` | PRESENT | PRESENT |
| Threads, counts, thread pagination and typing | `thread-sidebar` | MISSING thread UI/send path; channel typing includes thread events | PARTIAL, thread view exists but drops next cursor and typing |
| Pins browse, pin/unpin | `channel-view/text/pinned-messages-popover.tsx`, `message-actions.tsx` | MISSING | PARTIAL, browse incorrectly gated on pin permission |
| Reactions and live updates | `channel-view/text/message-actions.tsx`, `message-reactions.tsx` | PARTIAL, quick built-in set only; custom emoji image ignored | PRESENT |
| Message/file search and result navigation | `dialogs/search` | MISSING | PRESENT, stale response protection missing |
| Older message pagination | `features/server/messages/hooks.ts` | PRESENT | PRESENT |
| Typing expiry and channel/thread isolation | `hooks/use-typing-signal.ts`, `features/server/messages` | PARTIAL, channel-only | PARTIAL, thread indicator missing |
| File picker, upload, remove pending attachment, limits | `hooks/use-upload-files.ts`, `message-compose` | PRESENT picker/limits; temporary-file cleanup missing | PARTIAL, picker/paste, upload settings/count gates incomplete |
| Upload progress, cancellation, drag/drop, paste | `hooks/use-upload-files.ts` | MISSING byte progress/cancel/drop/paste | PARTIAL, paste; progress/drop/cancel missing |
| Image attachment preview and native viewer | `channel-view/text/message-files.tsx`, `fullscreen-image` | MISSING, external links only | PRESENT |
| Audio/video attachments and external file opening | `channel-view/text/message-files.tsx`, `message-renderer.tsx` | PARTIAL, external file links only | PRESENT via AVPlayer/external opener |
| Rich text, code, links, mentions, channel references | `tiptap-input`, `channel-view/text/message-renderer.tsx` | PARTIAL, plain-text fallback loses semantic navigation/formatting | PARTIAL, rich parser exists; whitespace/long-span handling differs |
| Built-in emoji catalog, picker, custom server emoji | `emoji-picker`, `emoji`, `tiptap-input/helpers.ts` | PARTIAL, small Unicode set; custom emoji not rendered/pickable | PARTIAL, custom emoji present; built-in spans may lose glyph |
| Member roster/status, profile, avatar/banner/bio/roles | `right-sidebar`, `user-popover`, `role-badge` | PARTIAL, roster/avatar/status only | PRESENT |
| Permission-aware actions and live permission changes | `protect`, `features/server/channels/subscriptions.ts` | PARTIAL, permission checks exist; permission-change subscription missing | PRESENT, individual UI gates need review |
| Voice join/leave, mute/deafen, push to talk | `voice-provider`, `left-sidebar/voice-control` | PRESENT through bundled media worker, untested live | PRESENT, untested on Mac |
| Voice roster/state, speaking indicators | `channel-view/voice`, `features/server/voice/subscriptions.ts` | PARTIAL, missing roster/state subscriptions and speaking display | PARTIAL, state exists; speaking display absent |
| Receive quality, per-user audio/share volume | `voice-provider`, `channel-view/voice` | MISSING native controls | PARTIAL, volumes exist; quality route has no UI |
| Camera and screen publish, remote media | `voice-provider/hooks/use-local-streams.ts` | PRESENT worker paths; runtime acceptance pending | PRESENT worker paths; runtime acceptance pending |
| Device selection, microphone/camera preview, capture quality | `server-screens/user-settings/devices` | PARTIAL, noise suppression mix only | PARTIAL, noise suppression mix only |
| Voice reactions, moderator moves, external streams | `features/server/voice`, `channel-view/voice` | MISSING native state/action surfaces | PARTIAL, routes/events exist, reaction display incomplete |
| Profile, avatar/banner, password settings | `server-screens/user-settings` | PRESENT | PRESENT |
| Language picker, ten locales | `language-switcher`, `i18n` | PRESENT, locale tests | PRESENT, tests pending Mac |
| Notification preferences, desktop notifications, shortcuts | `server-screens/user-settings/notifications`, `hotkeys-controller` | PRESENT native paths; runtime acceptance pending | PRESENT native paths; runtime acceptance pending |
| General, storage, users, roles, emoji, invite administration | `server-screens/server-settings` | PARTIAL, branding, role assignment and structured moderation detail missing | PARTIAL, branding, invite role/custom-code and moderation detail missing |
| Plugin marketplace/management, commands/logs, server updates | `server-screens/server-settings/plugins`, `plugin-view`, `updates` | PARTIAL, only installed list/toggle and server updates; marketplace/settings/commands/logs/capabilities missing | PRESENT native management paths |
| Plugin-provided React slots/fullscreen/settings UI | `plugin-slot-renderer`, `plugins-controller` | DEFERRED: plugin API supplies React components and browser globals; native-only UI/media-only WebView constraint prevents hosting them | Same constraint |
| Disconnect/retry/backoff, state resync | `reconnecting-overlay`, `features/server/actions.ts` | PARTIAL, backoff exists; cached messages are not reloaded after reconnect | PARTIAL, reconnect exists; failed WebSocket upgrade can leave open pending |
| Virtualized/lazy rows, drafts and phase-1 interactions | `channel-view/text`, `message-compose` | PRESENT, retain ListView/reconciliation and per-channel drafts | PRESENT, retain lazy rows/drafts |
| Disconnect/logout and welcome profile onboarding | `left-sidebar/server-dropdown.tsx`, `dialogs/welcome-profile-setup` | MISSING reachable controls; Core disconnect/profile methods exist | PRESENT |
| Text conversation in a voice channel | `voice-chat-sidebar` | MISSING, voice-only selection suppresses history | PRESENT |
| Interactive reply, mention and channel references | `channel-view/text/overrides`, `message-reply-preview-wrapper.tsx` | MISSING jump/profile controls | PARTIAL, static chips/reply summary |
| Full emoji catalog, search, recents and skin tones | `emoji-picker` | MISSING beyond quick set | PARTIAL, 32 standard entries plus custom search |
| Stream fullscreen, pin, picture-in-picture, zoom and statistics | `channel-view/voice` | MISSING | MISSING |
| Sound events and configurable sound preferences | `dialogs/sound-settings`, `helpers/sounds.ts` | MISSING | MISSING |
| OpenGraph/YouTube/plugin-command result rendering | `channel-view/text/renderer`, `overrides` | MISSING rich presentation | PARTIAL, external links/audio/video only |

Audit refinement: native invite fields exist on both platforms. macOS channel creation is
text-only and lacks reachable topic/private/permission forms despite Core methods; its
initial channel-administration PRESENT classification above is PARTIAL. Native source
coverage is judged by reachable controls, not generic RPC helpers or README claims.

### Execution and verification ledger

- [x] Initial audit recorded before implementation. Baseline Windows build: 0 warnings,
  0 errors. Baseline offline tests: 141 passed, 0 failed (including two gated no-op bodies).
- [ ] Windows messaging/navigation/session parity, with behavioral regression tests.
- [ ] Windows attachments/rendering/emoji and voice controls, retaining media isolation.
- [ ] Conservative macOS gap fixes and authored tests; Mac execution remains pending.
- [x] Safe real-server suite using the external credentials file and only owned fixtures.
- [ ] Windows Computer Use acceptance and saved evidence.
- [ ] Final build/tests, review, local logical commits, final audit status and remaining gaps.

Implementation follows the existing Core/session and native partial-window/domain view
patterns, without new dependencies or server changes. Regression tests precede behavioral
changes; native UI wiring is checked by the build, existing source-contract tests and CUA.
The initial real-server read of `https://voice.timhuang.net/info` reported
`allowNewUsers=true`, `oidcEnabled=false`, `oidcDisableLocalLogin=false` on 2026-10-31.
No production-user mutation has been made. Existing live tests are unsafe for this target
(first shared channel, arbitrary DM recipient, ownership-token attempt), so they must be
replaced or explicitly isolated before a live run.

Computer Use initialized successfully and enumerated Windows apps. This proves tool
availability only; it is not GUI acceptance. Evidence will be outside git under
`C:\Users\YY\codex-task\evidence\`. Only SDK 10.0.202 is installed. Bun checks will be
skipped because Bun is absent; no machine-wide toolchains will be installed.

### Real-server checkpoint, 2026-10-31

Created fresh primary and peer test accounts through normal registration. Credentials are
stored only in the requested external file. The primary account has normal user permissions,
so all acceptance mutations use the DM between these two owned accounts. Each cleanup loads
the message and verifies both owner and channel before deleting only IDs created by that run.

Replaced the unsafe integration bodies with origin-checked external credentials and serialized,
gated tests. Unconfigured runs still return without network access. The deployed server includes
optional `join.directMessages` snapshots and `dms.onConversationUpdate`; the local repository's
older API uses `dms.get` and `dms.onConversationOpen`. Windows supports both based on snapshot
presence, with regression coverage. No server changes were made.

Actual command from `apps/windows` (credentials are read from the external file):

```powershell
$env:SHARKORD_IT_HOST = 'https://voice.timhuang.net'
dotnet test tests/Sharkord.Core.Tests/Sharkord.Core.Tests.csproj --no-build --filter FullyQualifiedName~IntegrationTests --logger 'console;verbosity=detailed'
Remove-Item Env:SHARKORD_IT_HOST
```

Actual successful output summary: `Test Run Successful. Total tests: 2. Passed: 2.`
The first test took 2 seconds; the reconnect test took 1 minute 2 seconds. Detailed output is
saved at `C:\Users\YY\codex-task\evidence\live-integration-fourth.txt`. Verified HTTPS login,
handshake, join, owned DM open, peer live receipt, persisted send/edit/reaction, inline reply,
thread fetch/typing, read-state event, Unicode-named raw upload, exact `/public` download bytes,
delete event and absence, actual socket abort and automatic selected-DM history resync after
missed new/edit/delete events. All created messages were cleaned up.

Earlier runs exposed the deployed DM schema difference and server login/join rate limits.
The suite now avoids redundant sessions/joins and passes within those limits. Reconnect
currently takes roughly a minute after a local socket abort; transport cancellation handling
is being reviewed. This checkpoint does not establish voice, camera, screen capture or GUI
acceptance, and the successful suite will be rerun after the final implementation.
