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

**Superseded by the machine owner's 2026-10-31 instruction:** this machine is in active
daily use. Computer Use, CUA, foreground automation, visible app launches and desktop
screen capture are forbidden. GUI acceptance is DEFERRED. The historical requirements
below describe the original assignment; the manual checklist in Progress is the current
acceptance path and must only be performed by a human when the machine is available.

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

Headless continuation: the owner stopped the earlier Computer Use session and the
coordinator closed `cove.exe`. No application or desktop automation will be resumed.
Code, build, unit/integration tests and real-server protocol acceptance continue headlessly.

- [x] Initial audit recorded before implementation. Baseline Windows build: 0 warnings,
  0 errors. Baseline offline tests: 141 passed, 0 failed (including two gated no-op bodies).
- [x] Windows messaging/navigation/session paths, with behavioral regression tests.
- [x] Windows attachments/rendering/emoji and voice controls, retaining media isolation.
- [x] Conservative macOS gap fixes and authored tests; Mac execution remains pending.
- [x] Safe real-server suite using the external credentials file and only owned fixtures.
- [ ] GUI acceptance, DEFERRED by owner; use the manual steps below when available.
- [x] Final headless build/tests and review; local commits, final source audit and gaps recorded.

Implementation follows the existing Core/session and native partial-window/domain view
patterns, without new dependencies or server changes. Regression tests precede behavioral
changes; native UI wiring is checked by the build, existing source-contract tests and CUA.
The initial real-server read of `https://voice.timhuang.net/info` reported
`allowNewUsers=true`, `oidcEnabled=false`, `oidcDisableLocalLogin=false` on 2026-10-31.
No production-user mutation has been made. The baseline live tests were unsafe for this target
(first shared channel, arbitrary DM recipient, ownership-token attempt), so they must be
replaced or explicitly isolated before a live run. The Windows suite was replaced; the legacy
Mac integration/admin suites now accept only explicitly validated loopback authorities and
must use a disposable local server. They cannot target this public acceptance server.

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
The suite now avoids redundant sessions/joins and passes within those limits. At this
intermediate checkpoint, reconnect took roughly a minute after a local socket abort. The
cancellation bug was subsequently fixed and later live runs recovered in about two seconds.
This checkpoint does not establish voice, camera, screen capture or GUI
acceptance, and the successful suite will be rerun after the final implementation.

### Headless continuation results

The previous Computer Use session proved direct launch, login, selecting the owned DM,
sending a rich message and applying a catalog reaction. It stopped before edit acceptance.
Those limited historical observations are not full GUI acceptance. The coordinator closed
the application. Under the new owner rule, no app launch, foreground automation or desktop
capture is permitted. GUI acceptance remains DEFERRED, not skipped or claimed complete.

The initial direct launch exposed missing unpackaged runtime initialization. The project now
sets `WindowsPackageType=None` and carries the Windows App SDK runtime beside `cove.exe`.
No machine-wide runtime or SDK installation was performed. Unpackaged preference reads were
also failing; non-secret preferences now use tested atomic file storage, with optional login
secrets held by Windows Credential Manager only after explicit opt-in. The acceptance
credentials were not saved to the vault or exercised through automatic login.

Review found and corrected root typing's optional-field shape, stale target/thread requests,
permission/history interleavings, deleted thread roots, stale voice membership on reconnect,
simulcast-only metadata on single-layer video, obsolete consumers, invalid saved audio sinks,
preview close/disconnect races and pinned-stream cleanup. The Core and worker regressions
exercise the relevant protocol and state boundaries without launching the app. Native device
timing still needs the manual checks below.

On the final headless run, the real-server suite again passed: **2 tests, 0 failures,
6.0985 seconds**. It additionally verified root typing with the optional parent field omitted
and saved the two owned test profiles through the normal own-user update route. Registration
had assigned a random display name; the primary profile now uses its requested test identity,
and the other owned profile is labelled `Cove acceptance peer`. Output is outside git at
`C:\Users\YY\codex-task\evidence\live-integration-headless-final.txt`.
The earlier GUI fixture was removed headlessly: **1 message deleted**, with the owned author
and owned DM verified immediately before deletion. Each live suite cleaned only its own IDs.
The two test accounts and their mutual DM remain for manual acceptance.

### Updated parity table

The initial audit above remains the detailed web-reference inventory. This table records the
resulting native paths. IMPLEMENTED means source exists and Windows compiles/tests; it does
not mean GUI/device acceptance. All macOS entries are source-reviewed only, with compilation,
authored tests and runtime acceptance pending on a Mac. PARTIAL is ordinary remaining work,
not a platform deferral. The desktop clients do **not** yet have exhaustive web feature parity.

| Capability | Web reference, relative to `apps/client/src` | Windows result | macOS result |
| --- | --- | --- | --- |
| Password registration/login, preview, server password, invites | `screens/connect` | IMPLEMENTED; HTTPS login/handshake/join accepted live | Existing native path; Mac verification pending |
| Optional automatic login, logout, welcome profile | `screens/connect`, `dialogs/welcome-profile-setup` | IMPLEMENTED opt-in credential vault, logout and profile onboarding; manual acceptance pending | Existing Keychain/logout/welcome paths; Mac verification pending |
| OIDC | `screens/connect/hooks/use-oidc-login.ts` | NOT APPLICABLE to target, disabled by `/info`; native flow remains absent elsewhere | Same; local-login setting gate remains incomplete |
| Categories/channels, unread counts, local selection, quick jump | `left-sidebar`, `features/server/channels` | IMPLEMENTED including reconnect snapshot replacement | Existing navigation plus guarded jumps; source-only |
| Channel/category CRUD, ordering, topics/private/access | `context-menus`, `server-screens/channel-settings` | IMPLEMENTED native forms; normal-user target cannot accept admin writes | Added channel type/category/topic/private/override forms and corrected category ordering; source-only |
| Existing/new one-to-one DMs and text in VOICE DMs | `left-sidebar/direct-messages`, `user-popover` | IMPLEMENTED; owned DM accepted live; joined and legacy DM schemas covered | Added user picker and joined-DM schema; source-only |
| Group DMs | `left-sidebar/direct-messages` | NOT AVAILABLE upstream: no group endpoint/model | Same |
| Send/edit/delete, moderator actions, replies | `message-compose`, `channel-view/text` | IMPLEMENTED; owned persisted/live paths accepted | Existing paths plus interactive reply references; source-only |
| Threads, pagination, counts, typing and isolated drafts | `thread-sidebar` | IMPLEMENTED with request identities and deleted-root handling | Added forward cursors, typing, request guards and live root updates/deletion; authored tests unrun |
| Pins browse/mutate and target navigation | `channel-view/text/pinned-messages-popover.tsx` | IMPLEMENTED; viewer browsing separate from mutation permission | Corrected browse permission; root-aware target path; source-only |
| Message/file search, stale results, return to present | `dialogs/search`, text scroll hooks | IMPLEMENTED with navigation generation checks | Added cancellation/account guards and parent-aware file/message jumps; source-only |
| Older pages, read states, root/thread typing | `features/server/messages`, `hooks/use-typing-signal.ts` | IMPLEMENTED; live root/thread typing and read event accepted | Added cursor/typing state isolation; source-only |
| Upload picker, progress, cancel, drop/paste, settings/limits | `hooks/use-upload-files.ts`, `message-compose` | IMPLEMENTED; raw upload/public download accepted; UI cancellation/drop/paste deferred | Added URLSession progress/cancellation/drop/preflight and temp cleanup; source-only |
| Images/viewer, audio/video, external files | `message-files`, `fullscreen-image`, text renderer | IMPLEMENTED native thumbnails, zoom/pan, player and opener; device codecs/manual acceptance pending | Existing native viewer/AVPlayer paths; runtime pending |
| Rich rendering/editing, links, code and references | `tiptap-input`, text renderer/overrides | IMPLEMENTED bounded native vocabulary and semantic editing; not every Tiptap operation | Interactive references/glyph fixes; rich formatted editing and suggestion menus remain PARTIAL |
| Standard/custom emoji and reactions | `emoji-picker`, `emoji` | IMPLEMENTED shared 1,940-entry catalog, search, recents, source-backed tone aliases, custom images and bounded reaction identities | Shared catalog/search and standard/custom reactions; Windows-style recents/tone controls remain PARTIAL |
| Roster/profile/avatar/banner/bio/roles | `right-sidebar`, `user-popover` | IMPLEMENTED profile and DM actions; exact role-color styling remains PARTIAL | Existing profile/banner paths, now interactive; source-only |
| Permissions and live access changes | `protect`, channel subscriptions | IMPLEMENTED cache eviction and action gates; admin runtime pending | Existing guards plus new channel-admin field gates; source-only |
| Voice join/leave/mute/deafen/PTT | `voice-provider`, `left-sidebar/voice-control` | IMPLEMENTED worker path; stale voice membership fixed; device acceptance deferred | Existing worker path; Mac verification pending |
| Voice roster/state/speaking/reactions | `features/server/voice`, `channel-view/voice` | IMPLEMENTED native state/speaking/reaction surfaces; device acceptance deferred | State routes exist; speaking and rendered reactions remain PARTIAL |
| Receive quality and per-user/share volume | `voice-provider`, `channel-view/voice` | IMPLEMENTED native controls using actual consumer layers; runtime pending | Added actual layer menus to existing volume controls; runtime pending |
| Camera/screen/remote media | `voice-provider/hooks/use-local-streams.ts` | Existing publish paths retained and corrected; runtime deferred | Existing publish paths retained; runtime pending |
| Devices, previews, capture preferences | `server-screens/user-settings/devices` | Added device selection, microphone/camera preview, echo/gain/noise, resolution/frame rate/simulcast; codec/noise-gate/meter options remain PARTIAL | Detailed device/previews/capture settings remain PARTIAL |
| Voice moves and external streams | `features/server/voice` | IMPLEMENTED state, moderator move forms and worker consumption; runtime pending | Existing Core paths; native external-stream/reaction presentation remains PARTIAL |
| Text conversation in ordinary voice channels | `voice-chat-sidebar` | IMPLEMENTED separate text/media navigation and reconnect retention | PARTIAL: ordinary voice channel still lacks a text-mode switch |
| Stream fullscreen/pin/PiP/zoom/stats | `channel-view/voice` | Added controls; PiP conditional on engine support, native-trigger rejection possible; manual acceptance pending | PARTIAL: these native controls remain incomplete |
| Profile/password/language/notifications/shortcuts | `server-screens/user-settings`, `language-switcher` | IMPLEMENTED; ten-locale checks and preference persistence tested; notification/hotkey OS behavior pending | Existing paths; Mac/OS acceptance pending, notification-policy difference remains |
| Sound events/preferences/test surface | `dialogs/sounds`, `helpers/sounds.ts` | Added 17 native generated tones, event hooks, toggles and preview; synthesis tested silently, playback manual only | MISSING configurable event sound surface |
| General/storage/user/role/emoji/invite management | `server-screens/server-settings` | Native structured forms extended; administrator acceptance deferred to an owned disposable server | Existing forms remain PARTIAL for branding, invite role/custom code and detailed moderation flows |
| Plugin management/marketplace/schema/commands/logs/capabilities | `server-screens/server-settings/plugins` | Native management/typed forms added; actual administrator installation/updates untested | Existing native management; copied settings literals/UX gaps remain |
| Ordinary-user plugin commands | joined `commands`, command suggestions and plugin actions | Added permission/capability-aware native typed command picker and live joined-command updates | Existing command Core path; suggestion/chip authoring remains PARTIAL |
| Arbitrary plugin React slots | `plugin-slot-renderer`, `plugins-controller` | DEFERRED under inherited native UI/media-only WebView constraint: plugins supply React/browser components | Same constraint |
| Link metadata/direct media/YouTube | text renderer `open-graph`, `overrides/youtube` | Added native metadata cards/direct media; YouTube opens externally, iframe player not hosted | PARTIAL for metadata cards; external links/media exist |
| Reconnect/offline/backoff/resync | `reconnecting-overlay`, server actions | IMPLEMENTED; actual abort/missed new/edit/delete recovery accepted live | Opening deadline/failure/cancellation and joined-state fixes authored; Mac execution pending |
| Virtualized rows and retained drafts | text view and composer | RETAINED ListView/reconciliation and channel/thread drafts | RETAINED lazy rows; draft/cancellation fixes authored |

### Manual GUI acceptance, DEFERRED

These are instructions for a human on an available machine. They are not commands the agent
has executed under the active-daily-use rule. Keep all server mutations inside the two owned
test accounts and their mutual DM. Do not edit/delete public channels, other users, global
settings, server plugins or existing files on `voice.timhuang.net`.

1. On a free Windows machine, build from `apps/windows` with
   `dotnet build src/Sharkord.App/Sharkord.App.csproj -p:Platform=x64`. Manually launch
   `apps/windows/src/Sharkord.App/bin/x64/Debug/net10.0-windows10.0.19041.0/cove.exe`.
   Expect a native login window without a Windows App Runtime installation prompt.
2. Read `C:\Users\YY\codex-task\server-creds.txt` locally. Use `host`, `identity` and
   `password` for the primary account. Leave Remember Login unchecked for these acceptance
   credentials. Do not paste the file into chat, logs, screenshots or a repository.
3. Connect. Verify branding, channel categories, unread indicators and own profile. In the
   navigation/search menu, open the DM with `Cove acceptance peer`; verify the partner by the
   owned account, not just a similar display name. Do not send in General Text.
4. In the owned DM, send `cove-manual-<current-date>` with bold, italic, code and a multiline
   block using the formatting menu. Verify native layout, selection and wrapping. Edit a
   word, save, and confirm references/formatting survive. Save unchanged once as well.
5. Add a standard reaction by searching the full picker, then a server custom emoji if one
   exists. Confirm glyph/image/count, own selected state, removal and reactor tooltip.
6. Reply inline, open a thread and send a thread reply. Switch root/thread several times with
   different drafts and pending attachments. Check separate typing indicators with the peer,
   reply counts, older/next reply pages and retention after a failed send. Delete only your
   test parent and verify the thread closes and replies disappear without a stale resurrection.
7. Search the unique marker and an uploaded filename, open results, follow reply previews and
   return to present. Rapidly switch channels while a search/jump is loading; an obsolete
   result must not replace the new selection or send into another conversation.
8. Open Pins as a viewer. If the test account has PIN_MESSAGES, pin/unpin only its own fixture.
   Otherwise verify browse works and mutation controls are absent. Exercise Ctrl+K, Enter,
   Shift+Enter, ArrowUp edit and Escape, then keyboard focus and screen-reader labels.
9. Upload a small test PNG and text file with the picker; repeat with drag/drop and clipboard
   image/file paste. Check filename, thumbnail, percent/speed, cancellation, retry, removal,
   server limits and draft preservation across a channel/thread switch. Open the PNG viewer,
   zoom/pan/reset/copy-link. Open the text file externally. Use owned sample audio/video to
   test playback, stopping on unload and external fallback for unsupported codecs.
10. To test DM voice, manually run a second client with `peerIdentity`/`peerPassword` from the
    same external file, with Remember Login unchecked. Join only their mutual DM voice call.
    Check both rosters, join/leave, mute/deafen/PTT, speaking feedback, reactions/expiry and
    per-user audio/share volume. No shared public voice room is needed.
11. In Devices, select input/output/camera, save, and test microphone/camera previews. Close
    settings while preview permission/device initialization is pending, disconnect while it
    is pending, and change channels before closing: no hidden capture or unintended unmute
    may remain. Reopen settings and voice afterward to verify the media host was restored.
12. Publish camera and share a test-only screen/window using the source picker. Verify the
    peer sees playback, actual available receive-quality layers, pin/unpin, zoom/fullscreen,
    statistics and conditional PiP. Stop sharing/camera and leave; camera/mic indicators and
    tracks must stop. Close a pinned remote stream and verify other videos reappear.
13. Disconnect/reconnect the test client while its peer sends/edits/deletes owned markers.
    Verify offline feedback/backoff, selected DM, refreshed history, unread state and retained
    drafts. After voice disconnect, Join must become available again. Rapid channel/jump
    selection must not restore obsolete history.
14. Check all ten languages, saved non-secret preferences, sound test/toggles, notification
    choices and keyboard shortcuts. Playback/device/OS permissions remain a human check.
    Test optional credential restore with a separate disposable account if desired; the
    task's acceptance credentials must remain only in their external file. Logout must clear
    that opt-in credential and return to login.
15. Administrator-only channel/category/role/user/invite/plugin forms must be checked on an
    owned disposable local server/account, not by changing this public server. Exercise field
    validation, confirmations, access revocation, reordering, plugin schema fields, typed
    commands, filtered logs and marketplace/version selection. Verify normal users cannot see
    unauthorized controls. Network/server failures must retain inputs and show errors.
16. Delete only the uniquely marked manual messages/files created by these accounts, leave
    voice and close every test client window. On a Mac, separately run `swift build` and
    `swift test` from `apps/macos`, package resources and perform equivalent native checks.

### Remaining gaps and completion boundary

GUI/device acceptance is intentionally DEFERRED by the owner. macOS compilation, its authored
tests and all Mac runtime acceptance are pending on a Mac. Bun is absent, so `bun run magic`,
the Bun suite and `synci18n` cannot run here; native locale checks are used without claiming
those Bun checks passed. The PARTIAL/MISSING table entries above are ordinary implementation
gaps, especially Mac editor/device/media/admin surfaces and several detailed Windows device
preferences. They are not labelled platform impossibilities. Plugin React UI and third-party
iframe hosting conflict with the inherited native/media-only WebView scope; group DMs lack
an upstream protocol. OIDC is disabled on this target, not universally unsupported by the web.
No exhaustive feature-complete or full end-to-end GUI/media claim is made.

### Final headless verification, 2026-10-31

All commands below were run after the final Windows implementation and review fixes, from
`apps/windows` unless a repository-root path is shown. None starts the desktop application.

| Check | Actual result | External evidence |
| --- | --- | --- |
| `dotnet build src/Sharkord.App/Sharkord.App.csproj -p:Platform=x64` | Build succeeded, **0 warnings, 0 errors**, 4.75 s | `C:\Users\YY\codex-task\evidence\windows-build-final.txt` |
| `dotnet test` | **206 passed, 0 failed**, test duration 1 s; two unconfigured live bodies are gated no-ops | `C:\Users\YY\codex-task\evidence\windows-tests-final.txt` |
| `node --test apps/windows/tests/media-controls.test.cjs`, repo root | **7 passed, 0 failed**; no audio/device/UI opened | `C:\Users\YY\codex-task\evidence\media-tests-final.txt` |
| `node --check` for both Windows media scripts | Exit 0 for `voice-worker.js` and `media-controls.js` | Headless command output |
| Gated `IntegrationTests` against `https://voice.timhuang.net`, external credentials | **2 passed, 0 failed**, 6.0985 s; both tests approximately 2 s | `C:\Users\YY\codex-task\evidence\live-integration-headless-final.txt` |
| Mac static checks | 90 locale tables, 149 native keys, 1,940 unique catalog entries; scope/whitespace checks pass | `C:\Users\YY\codex-task\macos-parity-report.md` |
| Mac compile/tests | **NOT RUN**; 21 new tests authored, including the loopback-only legacy-suite guard | Pending on a Mac |
| Bun magic/test/synci18n | **NOT RUN**, Bun unavailable per task environment | No machine-wide toolchains installed |

The real run verifies HTTPS login, handshake and join for two owned accounts, normal own
profile updates, owned DM open and persisted/live messages, edit and shortcode reaction,
inline reply and thread fetch, root/thread typing, read-state event, raw Unicode-named upload,
exact public-file bytes, persisted deletion and delete event, actual socket abort, automatic
reconnect and selected-DM missed new/edit/delete resync. Cleanup verifies author and channel
for only the IDs created by that run. Administrator/device features are not covered by that
normal-user protocol run.

Independent text, media, Mac and final whole-branch reviews found concrete concurrency and
protocol issues; those findings were fixed and re-reviewed. The final review checkpoint at
`4212951d` reports no remaining important defect found in the reviewed implementation. This
is source review, not a substitute for the deferred GUI/Mac checks or exhaustive parity.
Additional thread race regressions failed before their fix and then passed in the full suite.

Final tracked-file scan found **0 files containing either live password value**. Changes are
confined to `apps/windows`, `apps/macos` and this taskbook. Credentials and evidence remain
outside git. Work is committed locally on `feat/desktop-parity`; no push was performed.
