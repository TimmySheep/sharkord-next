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
  `feat/desktop-discord-ui`), no machine-wide installs, no Electron.
- macOS work remains code-complete-but-Mac-verify-only; mark it clearly.

## Progress

- (to be filled in by the implementing agent)
