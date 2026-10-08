# Sharkord Next Architecture

> 中文版: [ARCHITECTURE.zh-CN.md](ARCHITECTURE.zh-CN.md)

A map of the codebase for contributors: **where things live and what rule governs them**.
Written from the source at `c611bb4` (branch `development`) with `file:line` citations. It
complements [`AGENTS.md`](../AGENTS.md): that file is the full rule book, this one is the
orientation map. Where the two disagree, the source wins.

## 1. Monorepo layout and workspace responsibilities

Bun workspaces monorepo. `bun install` at the root; workspaces are declared by glob in
`package.json:5-8` (`apps/*`, `packages/*`). Root scripts coordinate the workspace scripts
(`package.json`: `test`, `check-types`, `lint`, `format`, `magic` = lint:fix + format +
check-types).

| Workspace | Runtime shape | Responsibility |
| --- | --- | --- |
| `apps/server` | Bun + tRPC + Drizzle (SQLite) + mediasoup | HTTP/WS host, all domain logic, voice SFU (`apps/server/package.json` `"module": "src/index.ts"`) |
| `apps/client` | React 19 + Vite + Redux Toolkit + Tailwind 4 | Browser SPA (`apps/client/package.json` scripts `dev`/`build`) |
| `packages/shared` | Types/enums/helpers only | Cross-cutting code both sides import: `Permission`, `ServerEvents`, sanitizers, command parser (`packages/shared/src/index.ts`) |
| `packages/ui` | Presentational React | Styleable, logic-free components on Radix (`packages/ui/src/index.ts`); no app logic |
| `packages/plugin-sdk` | Plugin-facing API | Public plugin surface; `"./client" -> src/client.ts` alongside the main entry (`packages/plugin-sdk/package.json` exports) |
| `packages/e2e` | Playwright | End-to-end tests + own seed (`packages/e2e/package.json` script `test:e2e`) |

`packages/scripts` also exists (housekeeping such as `synci18n`); it is not an app. A
constant/enum/type/regex both sides need belongs in `packages/shared`, declared once.

## 2. Server bootstrap order

The boot sequence is explicit and order-sensitive in `apps/server/src/index.ts`:

| Step | Line | What it does |
| --- | --- | --- |
| `ensureServerDirs()` | `index.ts:3-4` | Creates the data directory layout (`helpers/ensure-server-dirs.ts`) |
| `loadEmbeds()` | `index.ts:6-7` | Loads embedded static assets |
| `loadDb()` | `index.ts:24` | Opens SQLite, applies migrations, seeds on first run (`db/index.ts:9-20`) |
| `pluginManager.init()` | `index.ts:25` | Loads enabled plugins, prunes removed ones, watches the dir (`plugins/index.ts:505-510`) |
| `createServers()` | `index.ts:26` | HTTP server first, then WS server attached to it (`utils/create-servers.ts:4-8`) |
| `loadMediasoup()` | `index.ts:27` | Starts the mediasoup worker (`utils/mediasoup.ts`) |
| `initVoiceRuntimes()` | `index.ts:28` | One `VoiceRuntime` per non-DM voice channel (`runtimes/index.ts:7-23`) |
| `loadCrons()` | `index.ts:29` | Registers scheduled jobs (`crons/index.ts:9-21`) |

Then it prints the banner, debug info, and enqueues a `SERVER_STARTED` activity log entry
(`index.ts:31-47`). The two top imports (`ensureServerDirs`, `loadEmbeds`) are deliberately
placed before the rest and wrapped in `// ---------` markers (`index.ts:1-8`): they must run
before anything that imports config or touches the data dir, so do not reorder them.

## 3. Client <-> server communication

Two channels exist: **tRPC over a single WebSocket**, and a few **plain HTTP routes** for
what cannot be tRPC.

**tRPC (WS-only).** Context and procedure builders are in `utils/trpc.ts`: `Context` carries
the authenticated user, permission helpers, pubsub and WS accessors (`trpc.ts:21-51`);
`protectedProcedure` = timing + auth (`trpc.ts:135-137`), `publicProcedure` is timing only
(`trpc.ts:139`), `rateLimitedProcedure` wraps either with a limiter (`trpc.ts:88-131`). The
WS context reads the JWT from `connectionParams` and builds per-connection helpers
(`utils/wss.ts:78-201`); `applyWSSHandler` wires the router with keep-alive 30s / pong 5s
(`wss.ts:283-292`); presence lives in two maps (`wss.ts:35-37`) and disconnect handling
removes the user from voice and publishes `USER_LEAVE` (`wss.ts:203-253`).

`routers/index.ts:15-28` namespaces the domains (`others`, `messages`, `users`, `channels`,
`dms`, `files`, `emojis`, `roles`, `invites`, `voice`, `categories`, `plugins`). Each domain
is a folder of one-procedure files plus an `index.ts` that only composes; all subscriptions
live in the domain's `events.ts` (e.g. `routers/messages/events.ts:4-33`). Fan-out is
`utils/pubsub.ts`, an in-process `EventEmitter` plus per-user and per-channel listener maps
(`pubsub.ts:137-320`); publishers in `db/publishers.ts` resolve the online users who may see
a channel and publish only to them (e.g. `db/publishers.ts:26-70`).

The **client uses only a WS link** — there is no HTTP tRPC link
(`apps/client/src/lib/trpc.ts:100-102`); the token comes from session storage
(`lib/trpc.ts:88-92`); reconnect/termination handling is in the same file
(`lib/trpc.ts:44-166`). Join is `others.handshake` (`routers/others/handshake.ts:7-22`) then
`others.joinServer` (`routers/others/join.ts:34-182`), which flips `ctx.authenticated`,
registers the socket, and returns the initial world (categories, channels, users, roles,
permissions, read states, plugin data, voice map); subscriptions then start on the client
(`features/server/subscriptions.ts:34-52`).

**Plain HTTP routes** (`apps/server/src/http`). Route table: `http/index.ts:77-101`; handlers
take `(req, res, ctx)` with a pre-parsed URL and client info (`http/index.ts:36-42`); CORS
and security headers apply to every request (`http/index.ts:108-113`).

| Method | Path | Handler | Notes |
| --- | --- | --- | --- |
| GET | `/healthz` | `healthz.ts:3-9` | Liveness JSON, no auth |
| GET | `/info` | `info.ts` | Public server info for the connect screen |
| GET | `/manifest.json` | `manifest.ts:84-107` | PWA manifest, cached 1h |
| GET | `/oidc/login`, `/oidc/callback` | `http/oidc/*` | OIDC redirect flow |
| GET | `/public/<file>` | `public.ts:23-120` | Files under `PUBLIC_PATH`; 404 if orphaned; optional signed-URL check (`public.ts:54-90`) |
| GET | `/plugin-components` | `plugins-components.ts:5-19` | Enabled plugins with UI, fetched before login |
| GET | `/plugin-bundle/<id>/<entry>` | `plugin-bundle.ts:10-83` | Unauthenticated; exposes only the client entry file of an enabled plugin |
| GET | *(fallback)* | `interface.ts:23-60` | Serves the built SPA; in dev 302-redirects to Vite `:5173` (`interface.ts:28-33`) |
| POST | `/login` | `login.ts:64-213` | Local login/registration, returns a JWT (`login.ts:202-211`) |
| POST | `/upload` | `upload.ts:30-143` | Streams a file, returns a temp-file record |
| POST | `/oidc/exchange`, `/oidc/backchannel-logout` | `http/oidc/*` | OIDC token exchange and logout |
| OPTIONS | any | `http/index.ts:176-181` | 204 preflight |

Plugin HTTP routes are matched after the static table: the path is decoded per segment and
looked up in the plugin registry (`http/index.ts:44-67`, `155-173`). Errors are centralised:
`PayloadTooLargeError` -> 413, `ZodError` -> 400 field errors, `HttpValidationError` -> 400,
else 500 (`http/index.ts:200-228`). If a handler throws **after** headers were sent the
socket is destroyed instead of writing a second response (`http/index.ts:187-197`) — this
matters for section 9.

## 4. Data layer: Drizzle + SQLite

### 4.1 Connection

`db/index.ts:9-20`: a strict `bun:sqlite` database with `journal_mode = WAL`,
`synchronous = NORMAL`, `busy_timeout = 5000`, wrapped by Drizzle, then migrate + seed. Data
paths derive from `helpers/paths.ts` (`DB_PATH`, `BACKUPS_PATH`, ...: `paths.ts:40-54`); in
dev the data dir is `apps/server/data`, in tests `./data-test`.

### 4.2 Tables and index design

All tables are declared in `db/schema.ts`. Foreign keys declare their delete behaviour
explicitly and the connection runs with `PRAGMA foreign_keys = ON`, so cascades are the norm.

- **`files`** (`schema.ts:19-40`) — `name` unique, `md5`, `user_id`, nullable `plugin_id`,
  size/mime/extension. Indexes on owner, `md5`, `created_at`, `name` (`schema.ts:34-39`):
  serving looks up by `name`, cleanup/quota by owner.
- **`messages`** (`schema.ts:258-312`) — `content` (HTML), nullable `user_id` (plugin
  messages have none, `schema.ts:263-268`), `channel_id` cascade, self-FK
  `parent_message_id` (thread parent, cascade) and `reply_to_message_id` (set null),
  `editable`, JSON `metadata`, pin/edit audit columns. Composite indexes follow the query
  shapes: `messages_channel_created_idx` for a channel page,
  `messages_channel_parent_created_idx` for a thread page (`schema.ts:299-303`), and
  `messages_parent_channel_id_idx` for reply-count/thread lookups (`schema.ts:306-310`).
- **`channels`** (`schema.ts:148-171`) — `type`, `name`, `topic`, `private`, `is_dm`
  (`is_dm_channel`), `position`, `category_id` cascade. Indexes: `position`, `type`, and
  composite `(category_id, position)` for rendering a category (`schema.ts:166-170`).
- **`users`** (`schema.ts:173-210`) — `identity` unique, argon2 `password`, avatar/banner FK
  `set null`, ban fields, `token_version` (JWT invalidation), `oidc_sub`/`oidc_issuer`,
  `password_set`, `profile_color`, `last_login_at`. Indexes: unique `identity`, `name`,
  `last_login_at` (`schema.ts:205-209`).
- **`roles`** (`schema.ts:120-134`) — `color`, `is_persistent`, `is_default`, storage
  overrides; small table, no secondary indexes, persistent roles cannot be deleted.
- **`role_permissions`** (`schema.ts:333-347`) — primary key `(role_id, permission)` plus an
  index on `permission`.
- **`user_roles`** (`schema.ts:212-227`) — primary key `(user_id, role_id)`, index on `role_id`.
- **`channel_role_permissions`** / **`channel_user_permissions`** (`schema.ts:443-491`) —
  per-channel allow overrides with a boolean `allow`. Primary keys are `(channel_id,
  role_id|user_id, permission)`; composite indexes cover channel-first and permission-first reads.
- Supporting tables: `settings` (single row enforced by `settings_single_row_idx`,
  `schema.ts:116`), `categories`, `message_files`, `message_reactions`, `direct_messages`
  (unique unordered pair, `schema.ts:527`), `channel_read_states`, `invites`, `activity_log`,
  `emojis`, `oidc_transactions`, `oidc_handoffs`, and the plugin tables.

Permission enums are in `packages/shared/src/statics/permissions.ts`: global `Permission`
(`permissions.ts:1-26`), `ChannelPermission` (`permissions.ts:30-42`), default member set
`DEFAULT_ROLE_PERMISSIONS` (`permissions.ts:44-51`).

### 4.3 Migrations and backups

- Location: `apps/server/src/db/migrations` (`0000_*` .. `0035_*` plus `meta/`). Generate
  with `bun run db:gen` in `apps/server` (drizzle-kit); verify with `db:check`
  (`apps/server/package.json` scripts).
- Applied **automatically at startup** by `migrateDatabase` (`db/migrate.ts:140-190`),
  called from `loadDb` (`db/index.ts:18`); there is no manual step. Tests migrate a fresh
  in-memory DB (`__tests__/setup.ts`).
- `migrateDatabase` turns foreign keys **off** for the run and restores them in a `finally`
  (`migrate.ts:159-177`), because the migrator wraps each migration in a transaction where
  `PRAGMA foreign_keys=OFF` is a no-op; getting this wrong historically cascaded message
  files/reactions away (`migrate.ts:132-139`).
- `backupDatabase` (`migrate.ts:96-130`): before applying pending migrations, if
  `config.server.backupDatabase` is on (default `true`, `config.ts:104`), it takes a
  `VACUUM INTO` snapshot under `backups/<db>.before-<firstPendingTag>.sqlite`, skipping an
  identical snapshot if one exists (`migrate.ts:106-120`). After migrating it reports (does
  not throw on) foreign-key violations (`migrate.ts:24-51`, `189`).
- Data migrations are hand-written SQL split by the literal `--> statement-breakpoint` (with
  the space); never edit a committed migration, add a new one.
- Seeding (`db/seed.ts:39-217`) runs only when `settings` is empty (`seed.ts:40-42`): two
  categories, four channels, Owner + Member roles, a `Sharkord` user, a welcome message,
  Owner gets every permission / Member gets `DEFAULT_ROLE_PERMISSIONS` (`seed.ts:171-192`),
  and a one-time access token is printed (`seed.ts:200-216`).

## 5. Server code layering and the security check order

`apps/server/src` boundaries:

- `routers/<domain>/` — one tRPC procedure **per file**, named after what it does; the folder
  `index.ts` only composes the `t.router({...})` map. Subscriptions go in the domain's
  `events.ts`. A new endpoint is a new file.
- `db/queries/` (reads) and `db/mutations/` (writes) — one file per table/domain; anything
  reused by more than one route lives here.
- `db/publishers.ts` — realtime event publishing consumed by subscriptions.
- `helpers/` — domain-aware logic (permissions, paths, file crypto, sanitizing); `utils/` —
  infrastructure with no domain knowledge. If in doubt, it is a helper.
- `queues/` — background work off the request path, drained in tests via
  `queues/drain.ts:7-15`; `crons/` — scheduled jobs (file cleanup every 15 min,
  `crons/index.ts:9-21`, `crons/cleanup-files.ts:6-29`).
- `plugins/` — plugin loading, registries, event bus (section 6).

Conventions: named exports only, declared as `const foo = ...` and exported at the bottom for
server files; `T`-prefixed types; kebab-case file names; no `any`.

### 5.1 Security check order for every request

From `AGENTS.md:120-137`, verified in the routes below. Cheapest and broadest first; nothing
mutates before all of them pass:

1. **Authentication** — build on `protectedProcedure` (`utils/trpc.ts:135-137`).
2. **Rate limiting** — `rateLimitedProcedure` with `config.rateLimiters` (`utils/trpc.ts:88-131`).
3. **Input validation** — `.input(z.object({...}))`, validating shape *and* bounds.
4. **Global permission** — `ctx.needsPermission(Permission.X)` (`utils/wss.ts:143-150`).
5. **Existence** — load the row and `invariant(row, { code: 'NOT_FOUND' })` (`utils/invariant.ts`).
6. **Channel scope** — `assertChannelAccess` (DM membership + `VIEW_CHANNEL`,
   `helpers/assert-channel-access.ts:5-11`) then `ctx.needsChannelPermission(...)`. Never
   trust an input `channelId` over the one on the stored row.
7. **Ownership / elevation** — owner-or-privileged last
   (`helpers/load-message-for-write.ts:19-32`).
8. **Server settings gates** — feature toggles/quotas (uploads enabled, DM file sharing, max
   files per message).
9. **Sanitize** — `sanitizeMessageHtml`, then **re-validate** (non-empty can become empty).

Worked example, `routers/messages/send-message.ts`: rate limit + protected
(`send-message.ts:37-41`), input schema (`:42-50`), permissions (`:52-58`), parent/reply
existence and same-channel (`:60-109`), DM resolution + settings gates (`:113-139`), empty
check + sanitize + re-check (`:141-152`), plugin hooks (`:154-161`), then a **synchronous**
`db.transaction` for the write (`:283-311`). Uploads follow the same HTTP shape: rate limit
-> zod headers -> token -> permission -> settings (`upload.ts:34-102`). Keep the transaction
callback synchronous (`AGENTS.md`; guarded by `__tests__/transactions.test.ts`).

`/login` is the deliberate pre-auth exception: a public, rate-limited route that runs the
`beforeLogin` hook, uses a dummy argon2 verify to keep timing flat for unknown identities
(`login.ts:51-62`, `:115`), and upgrades legacy SHA256 hashes to argon2 on success
(`login.ts:156-185`).

## 6. Plugin system

**Loading.** `plugins/index.ts` is the `PluginManager`. `loadPlugins` runs only when
`settings.enablePlugins` is on, loads persisted state, and scans `PLUGINS_PATH` for
directories (`plugins/index.ts:512-535`). Each plugin is a folder with a required
`manifest.json`, server entry and client entry (`readManifest`, `plugins/index.ts:373-411`).
`load` (`:611-742`) ensures state, skips disabled plugins, validates the SDK version, builds
a context, dynamically imports the server entry, runs `onLoad` under a timeout, and runs
`onUpgrade` when the version changed. Timeouts are centralised in `execution-timeout.ts:1-27`
(30s lifecycle/command/action, 10s event handler). `init` watches the directory and unloads
plugins removed from disk (`plugins/index.ts:483-510`). Enabled state, settings and version
persist in `plugin_data` (`schema.ts:556-564`); per-user storage in `plugin_user_data`
(`schema.ts:566-583`).

**Event bus.** `plugins/event-bus.ts` is separate from the client-facing `pubsub`. Plugins
subscribe with `ctx.events.on(...)` (`plugins/create-context.ts:245-248`). `emit` fans out
with `Promise.allSettled` and a per-handler timeout so one bad plugin cannot block the
others; rejections are logged (`event-bus.ts:55-95`). Core emits e.g. `message:created`
(`routers/messages/send-message.ts:323-330`) and `user:left` (`utils/wss.ts:237-240`).

**Hooks.** `registerBefore*` in `load` (`plugins/index.ts:663-672`) covers `beforeFileSave`,
`beforeMessageSave`, `beforeChannelCreate`, `beforeVoiceJoin`, `beforeLogin`. `runHook`
(`plugins/run-hook.ts:21-62`) runs handlers in order; a handler may **reject** the request
(message capped at 200 chars, `run-hook.ts:50`) or **update** the payload for the next.

**Permissions.** Capabilities are typed `COMMAND`, `ACTION`, `COMPONENT`, `HTTP_ROUTE`
(`packages/shared/src/plugins/capabilities.ts:3-14`). A capability may declare a global
`requires: Permission`; admins can additionally restrict it to roles
(`PluginCapabilityMode.RESTRICTED`) stored in `plugin_capabilities` and
`plugin_capability_roles` (`schema.ts:585-615`). Enforcement: HTTP routes resolve whether a
caller is needed, then capability access, then 401/403 (`http/plugin-route.ts:45-91`);
commands require `USE_PLUGINS` **and** `canUseCapability(...)` (`send-message.ts:177-186`).
The context exposes db-backed actions (messages, channels, roles, users, moderation, push,
user data) and permission helpers (`plugins/create-context.ts:239-327`).

**Why no sandbox.** Plugins run **inside the server process** by design: "Plugins run inside
the server process. There is no sandbox, so nothing here is a security boundary: it is the
supported way to reach the host, not a fence around it" (`packages/plugin-sdk/src/index.ts:388`);
`AGENTS.md:53` repeats it. The trust model is **install-time trust**: enabling a plugin trusts
its code the way the server binary is trusted. The capability system buys *governance* (which
users may reach a command or route), not containment.

## 7. Client structure

- `features/` — Redux Toolkit state, read through hooks/selectors, never by reaching into the
  store shape. The store has four slices: `app`, `server`, `dialog`, `serverScreen`
  (`features/store.ts:7-23`). The `features/server/*` domains have **no slice of their own** —
  their reducers all live in `features/server/slice.ts`, and each domain folder holds
  `actions.ts`, `selectors.ts`, `hooks.ts`, `subscriptions.ts`.
- `components/` — one folder per component with `index.tsx` plus local parts, `helpers.ts`
  and `hooks/`; `screens/` — top-level routes, selected in
  `components/routing/index.tsx:22-67` from connection state.
- `hooks/` — generic reusable `use-*.ts`; `lib/trpc.ts` is the tRPC client (all server calls
  go through `getTRPCClient()`), `lib/utils.ts` generic helpers; `helpers/` pure functions
  (URLs, storage, formatting, audio). Generic, styleable, logic-free components belong in
  `packages/ui`.

Selectors and caching (from `AGENTS.md`, verified in `features/server/selectors.ts`): plain
function for a direct read (`selectors.ts:38-40`); `createSelector` the moment you build an
array/object; `createCachedSelector` (re-reselect) for a parameterised selector keyed by that
parameter (`selectors.ts:80-90`). Return a stable module-level empty value, not a fresh
`?? {}` / `?? []`. Cross-domain selectors live in `features/server/selectors.ts`, never in a
domain file (circular import); derive in a selector, never inline in a component.
`useCan()` / `useChannelCan()` wrap permission checks (`features/server/hooks.ts:69-117`),
with the owner always passing.

Client-side plugins are bootstrapped by `components/plugins-controller/index.tsx:9-37`, which
fetches `/plugin-components` **before** joining (so slots can render on the login screen); the
host store is exposed on `window` in `main.tsx:18,26`. After that, plugin state flows through
tRPC like everything else.

## 8. Runtime state vs persistent state

`src/runtimes` plus the WS/pubsub layers hold **only** live, ephemeral state. Everything that
must survive a restart goes through `db/schema.ts`.

**In memory only:** WS presence (user -> sockets and user -> IP maps, `utils/wss.ts:35-37`;
online status derived from the socket map, `wss.ts:131-133`); pub/sub delivery (the
`EventEmitter` and per-user/per-channel listener maps, `utils/pubsub.ts:137-320`); voice (the
`voiceRuntimes` map and all mediasoup state — routers, transports, producers, consumers,
external streams, `runtimes/voice.ts:25`, consumed in `routers/others/join.ts:141-142`);
plugin runtime (`plugins/index.ts:78-115`); rate-limiter buckets (`utils/rate-limiters`), cron
jobs (`crons/index.ts:12-20`), and the manifest image-size cache (`http/manifest.ts:13-16`).

**Persistent (database):** identities, roles and permissions, channels and categories,
messages/threads/reactions/read states, files, settings, invites, activity log and logins,
OIDC flow rows, and the plugin tables. Voice membership is deliberately **not** persisted: it
exists only while a socket is connected, and on close the user is removed from the runtime
(`wss.ts:223-232`). Background writes reach the DB through the queues
(`queues/activity-log/index.ts:24-44`, `queues/message-metadata/index.ts:12-22`), so a route
can return before its side effect lands; tests drain the queues (`queues/drain.ts:7-15`).

## 9. Known platform issues

### 9.1 `plugin-routes.test.ts` — connection-drop assertion

- Test: `apps/server/src/http/__tests__/plugin-routes.test.ts:467`,
  `drops the connection when a handler throws after writing headers`.
- Mock handler: `apps/server/src/__tests__/mocks/plugins/plugin-http-routes/server/index.js:22-27`
  writes `200` headers and a partial body, then throws.
- Server behaviour: because headers are already sent, the catch block calls `res.destroy()`
  instead of writing an error (`http/index.ts:187-197`).
- Assertion: the test expects `fetch(...).then(r => r.text())` to **reject**
  (`plugin-routes.test.ts:468-475`).

**Cause analysis (verified in this environment).** The off-CI failure is triggered by the
`HTTP_PROXY` / `HTTPS_PROXY` environment, not by macOS as such:

- With no proxy set, the test passes repeatedly and deterministically (43/43 for the whole
  file, filtered runs, and as part of the full server suite).
- With `HTTP_PROXY` and `HTTPS_PROXY` pointing at a local proxy, it
  fails deterministically with `Expected promise that rejects / Received promise that
  resolved`.
- Adding `NO_PROXY=localhost,127.0.0.1` makes it pass again.

Mechanism: with a proxy configured, Bun's `fetch` does not surface the mid-response socket
destroy as a rejection — the headers and partial body were already flushed, so the promise
resolves. Without a proxy the same destroy rejects as the assertion expects. Upstream CI runs
on ubuntu with no proxy, so it is green there; a developer shell that exported the proxy (to
reach GitHub, or via a shell profile) fails it locally.

Note on the historical explanation: this was previously described as an OS-level
Linux-vs-macOS difference. In this verification the trigger is the proxy variable and the
behaviour is OS-independent. Treat the OS framing as **unconfirmed**; the proxy trigger is
reproducible. Whether the same proxy effect breaks other `fetch`-based tests was not
exhaustively checked.

### 9.2 Running the server test suite alongside the dev server

The dev server binds the mediasoup WebRTC UDP port `40000` (`config.ts:124-125`). Running the
server suite while dev is up fails to bind (`uv_udp_bind() ... address already in use ...
createWebRtcServer`); move the test port with `SHARKORD_WEBRTC_PORT=<free port>`. Caveat:
setting any `SHARKORD_*` variable then makes `__tests__/config.test.ts:124-126`
(`should leave the config untouched when no variable is set`) fail, because it compares
`applyEnvOverrides(defaultConfig)` against `zConfig.parse(defaultConfig)` with the live
environment. That failure is expected noise, not a regression.

## Where to look first (contributor quick reference)

- **Endpoint**: new file under `routers/<domain>/`, wire it in the domain `index.ts`, follow
  the check order in 5.1, wrap writes in a synchronous transaction.
- **Database**: edit `db/schema.ts`, run `bun run db:gen`, commit the SQL **and** `meta/`;
  never edit a committed migration.
- **Helper**: `db/queries`/`db/mutations` for data, `helpers/` for domain rules, `utils/` for
  infrastructure. Search first — two copies is the limit.
- **UI state**: reducers in `features/server/slice.ts`, derived state in a selector, access
  via `hooks.ts`. **Strings** go in every locale under `apps/client/src/i18n/locales` (run
  `synci18n`), never hardcoded.
- **Before finishing**: `bun run magic` and `bun run test` from the repo root, with the
  caveats in section 9.
