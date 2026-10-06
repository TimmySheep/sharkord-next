# Sharkord Next 系统架构
> 本文是 [`ARCHITECTURE.md`](ARCHITECTURE.md) 的中文翻译。英文版为权威版本，如有歧义以英文版为准。

一份为贡献者准备的代码库地图：**东西都在哪里，以及什么规则管辖它们**。
基于 `c611bb4`（分支 `development`）的源码撰写，并带有 `file:line` 引用。它
是对 [`AGENTS.md`](../AGENTS.md) 的补充：那个文件是完整的规则手册，这个文件是
定位地图。两者不一致时，以源码为准。

## 1. Monorepo 布局与各工作区职责

Bun workspaces monorepo。在根目录运行 `bun install`；工作区通过 glob 在
`package.json:5-8` 中声明（`apps/*`、`packages/*`）。根脚本协调各工作区脚本
（`package.json`：`test`、`check-types`、`lint`、`format`、`magic` = lint:fix + format +
check-types）。

| 工作区 | 运行时形态 | 职责 |
| --- | --- | --- |
| `apps/server` | Bun + tRPC + Drizzle (SQLite) + mediasoup | HTTP/WS 宿主、全部领域逻辑、语音 SFU（`apps/server/package.json` `"module": "src/index.ts"`） |
| `apps/client` | React 19 + Vite + Redux Toolkit + Tailwind 4 | 浏览器 SPA（`apps/client/package.json` 脚本 `dev`/`build`） |
| `packages/shared` | 仅类型/枚举/辅助函数 | 两端共同导入的横切代码：`Permission`、`ServerEvents`、sanitizers、command parser（`packages/shared/src/index.ts`） |
| `packages/ui` | 展示型 React | 基于 Radix 的可样式化、无逻辑组件（`packages/ui/src/index.ts`）；不含应用逻辑 |
| `packages/plugin-sdk` | 面向插件的 API | 公开的插件接口面；在与主入口并列处有 `"./client" -> src/client.ts`（`packages/plugin-sdk/package.json` exports） |
| `packages/e2e` | Playwright | 端到端测试 + 自有 seed（`packages/e2e/package.json` 脚本 `test:e2e`） |

`packages/scripts` 也存在（诸如 `synci18n` 之类的杂务）；它不是应用。两端都需要的
常量/枚举/类型/正则属于 `packages/shared`，只声明一次。

## 2. 服务端启动顺序

启动序列在 `apps/server/src/index.ts` 中是显式且对顺序敏感的：

| 步骤 | 行 | 作用 |
| --- | --- | --- |
| `ensureServerDirs()` | `index.ts:3-4` | 创建数据目录布局（`helpers/ensure-server-dirs.ts`） |
| `loadEmbeds()` | `index.ts:6-7` | 加载内嵌静态资源 |
| `loadDb()` | `index.ts:24` | 打开 SQLite、应用迁移、首次运行时 seed（`db/index.ts:9-20`） |
| `pluginManager.init()` | `index.ts:25` | 加载已启用插件、清理已移除的插件、监听目录（`plugins/index.ts:505-510`） |
| `createServers()` | `index.ts:26` | 先建 HTTP 服务器，再挂载 WS 服务器到其上（`utils/create-servers.ts:4-8`） |
| `loadMediasoup()` | `index.ts:27` | 启动 mediasoup worker（`utils/mediasoup.ts`） |
| `initVoiceRuntimes()` | `index.ts:28` | 每个非 DM 语音频道一个 `VoiceRuntime`（`runtimes/index.ts:7-23`） |
| `loadCrons()` | `index.ts:29` | 注册定时任务（`crons/index.ts:9-21`） |

随后它打印 banner、debug 信息，并排队一条 `SERVER_STARTED` activity log 条目
（`index.ts:31-47`）。最上面的两个 import（`ensureServerDirs`、`loadEmbeds`）被刻意
放在其余之前并用 `// ---------` 标记包裹（`index.ts:1-8`）：它们必须在任何 import
config 或触碰数据目录的东西之前运行，所以不要重排它们。

## 3. 客户端 <-> 服务端通信

存在两条通道：**单一 WebSocket 之上承载的 tRPC**，以及少量用于无法走 tRPC 之场景的
**普通 HTTP 路由**。

**tRPC（仅 WS）。** Context 与 procedure 构建器在 `utils/trpc.ts`：`Context` 携带
已认证用户、权限辅助函数、pubsub 与 WS 访问器（`trpc.ts:21-51`）；
`protectedProcedure` = timing + auth（`trpc.ts:135-137`），`publicProcedure` 仅 timing
（`trpc.ts:139`），`rateLimitedProcedure` 用限流器包裹二者之一（`trpc.ts:88-131`）。WS
context 从 `connectionParams` 读取 JWT 并构建每连接的辅助函数
（`utils/wss.ts:78-201`）；`applyWSSHandler` 用 keep-alive 30s / pong 5s 接线路由器
（`wss.ts:283-292`）；presence 存在于两个 map 中（`wss.ts:35-37`），断连处理会把用户
从语音中移除并发布 `USER_LEAVE`（`wss.ts:203-253`）。

`routers/index.ts:15-28` 为各领域命名空间（`others`、`messages`、`users`、`channels`、
`dms`、`files`、`emojis`、`roles`、`invites`、`voice`、`categories`、`plugins`）。每个
领域是一个由单 procedure 文件组成的文件夹，外加一个只做组合的 `index.ts`；所有
subscription 都位于该领域的 `events.ts`（例如 `routers/messages/events.ts:4-33`）。
扇出由 `utils/pubsub.ts` 负责，它是在进程内的 `EventEmitter` 加上每用户与每频道的
监听器 map（`pubsub.ts:137-320`）；`db/publishers.ts` 中的发布者会解析出可能看到某
频道的在线用户，并只向他们发布（例如 `db/publishers.ts:26-70`）。

**客户端只用一个 WS link**——不存在 HTTP tRPC link
（`apps/client/src/lib/trpc.ts:100-102`）；token 来自 session storage
（`lib/trpc.ts:88-92`）；重连/终止处理在同一文件中
（`lib/trpc.ts:44-166`）。加入流程是 `others.handshake`
（`routers/others/handshake.ts:7-22`）然后是 `others.joinServer`
（`routers/others/join.ts:34-182`），后者翻转 `ctx.authenticated`、注册 socket，并
返回初始世界（categories、channels、users、roles、permissions、read states、plugin
data、voice map）；随后 subscription 在客户端启动
（`features/server/subscriptions.ts:34-52`）。

**普通 HTTP 路由**（`apps/server/src/http`）。路由表：`http/index.ts:77-101`；处理器
签名为 `(req, res, ctx)`，URL 与客户端信息已预先解析（`http/index.ts:36-42`）；
CORS 与安全响应头应用于每个请求（`http/index.ts:108-113`）。

| 方法 | 路径 | 处理器 | 备注 |
| --- | --- | --- | --- |
| GET | `/healthz` | `healthz.ts:3-9` | 存活探针 JSON，无需认证 |
| GET | `/info` | `info.ts` | 供连接界面使用的公开服务器信息 |
| GET | `/manifest.json` | `manifest.ts:84-107` | PWA manifest，缓存 1h |
| GET | `/oidc/login`、`/oidc/callback` | `http/oidc/*` | OIDC 重定向流程 |
| GET | `/public/<file>` | `public.ts:23-120` | `PUBLIC_PATH` 下的文件；孤立则 404；可选签名 URL 校验（`public.ts:54-90`） |
| GET | `/plugin-components` | `plugins-components.ts:5-19` | 带 UI 的已启用插件，在登录前获取 |
| GET | `/plugin-bundle/<id>/<entry>` | `plugin-bundle.ts:10-83` | 未认证；仅暴露已启用插件的客户端入口文件 |
| GET | *（fallback）* | `interface.ts:23-60` | 提供构建后的 SPA；dev 下 302 重定向到 Vite `:5173`（`interface.ts:28-33`） |
| POST | `/login` | `login.ts:64-213` | 本地登录/注册，返回 JWT（`login.ts:202-211`） |
| POST | `/upload` | `upload.ts:30-143` | 流式接收文件，返回临时文件记录 |
| POST | `/oidc/exchange`、`/oidc/backchannel-logout` | `http/oidc/*` | OIDC token 交换与登出 |
| OPTIONS | any | `http/index.ts:176-181` | 204 预检 |

插件 HTTP 路由在静态表之后匹配：路径按段解码并在插件注册表中查找
（`http/index.ts:44-67`、`155-173`）。错误被集中处理：
`PayloadTooLargeError` -> 413，`ZodError` -> 400 字段错误，`HttpValidationError` -> 400，
否则 500（`http/index.ts:200-228`）。若处理器在响应头已发送**之后**抛出，socket 会被
销毁而不是写入第二个响应（`http/index.ts:187-197`）——这对第 9 节很重要。

## 4. 数据层：Drizzle + SQLite

### 4.1 连接

`db/index.ts:9-20`：严格模式的 `bun:sqlite` 数据库，`journal_mode = WAL`、
`synchronous = NORMAL`、`busy_timeout = 5000`，由 Drizzle 包裹，然后 migrate + seed。
数据路径派生自 `helpers/paths.ts`（`DB_PATH`、`BACKUPS_PATH` 等：`paths.ts:40-54`）；
dev 下数据目录是 `apps/server/data`，测试下是 `./data-test`。

### 4.2 表与索引设计

所有表都在 `db/schema.ts` 中声明。外键显式声明其删除行为，连接以
`PRAGMA foreign_keys = ON` 运行，因此级联是常态。

- **`files`**（`schema.ts:19-40`）——`name` 唯一、`md5`、`user_id`、可空 `plugin_id`、
  size/mime/extension。在 owner、`md5`、`created_at`、`name` 上建索引
  （`schema.ts:34-39`）：提供文件时按 `name` 查找，清理/配额按 owner。
- **`messages`**（`schema.ts:258-312`）——`content`（HTML）、可空 `user_id`（插件
  消息没有，`schema.ts:263-268`）、`channel_id` 级联、自引用外键
  `parent_message_id`（thread 父级，级联）与 `reply_to_message_id`（置 null）、
  `editable`、JSON `metadata`、置顶/编辑审计列。复合索引遵循查询形态：
  `messages_channel_created_idx` 用于频道分页，
  `messages_channel_parent_created_idx` 用于 thread 分页（`schema.ts:299-303`），以及
  `messages_parent_channel_id_idx` 用于回复计数/thread 查找（`schema.ts:306-310`）。
- **`channels`**（`schema.ts:148-171`）——`type`、`name`、`topic`、`private`、`is_dm`
  （`is_dm_channel`）、`position`、`category_id` 级联。索引：`position`、`type`，以及
  用于渲染某分类的复合 `(category_id, position)`（`schema.ts:166-170`）。
- **`users`**（`schema.ts:173-210`）——`identity` 唯一、argon2 `password`、头像/banner
  外键 `set null`、封禁字段、`token_version`（JWT 失效）、`oidc_sub`/`oidc_issuer`、
  `password_set`、`profile_color`、`last_login_at`。索引：唯一 `identity`、`name`、
  `last_login_at`（`schema.ts:205-209`）。
- **`roles`**（`schema.ts:120-134`）——`color`、`is_persistent`、`is_default`、存储
  覆盖；小表，无二级索引，持久角色不可删除。
- **`role_permissions`**（`schema.ts:333-347`）——主键 `(role_id, permission)` 外加
  一个 `permission` 上的索引。
- **`user_roles`**（`schema.ts:212-227`）——主键 `(user_id, role_id)`，`role_id` 上
  的索引。
- **`channel_role_permissions`** / **`channel_user_permissions`**（`schema.ts:443-491`）——
  按频道的允许覆盖，带布尔 `allow`。主键为 `(channel_id,
  role_id|user_id, permission)`；复合索引覆盖频道优先与权限优先的读取。
- 支撑表：`settings`（通过 `settings_single_row_idx` 强制单行，
  `schema.ts:116`）、`categories`、`message_files`、`message_reactions`、`direct_messages`
  （唯一无序对，`schema.ts:527`）、`channel_read_states`、`invites`、`activity_log`、
  `emojis`、`oidc_transactions`、`oidc_handoffs`，以及各插件表。

权限枚举在 `packages/shared/src/statics/permissions.ts`：全局 `Permission`
（`permissions.ts:1-26`）、`ChannelPermission`（`permissions.ts:30-42`）、默认成员集
`DEFAULT_ROLE_PERMISSIONS`（`permissions.ts:44-51`）。

### 4.3 迁移与备份

- 位置：`apps/server/src/db/migrations`（`0000_*` .. `0035_*` 外加 `meta/`）。在
  `apps/server` 中用 `bun run db:gen` 生成（drizzle-kit）；用 `db:check` 校验
  （`apps/server/package.json` scripts）。
- 由 `migrateDatabase`（`db/migrate.ts:140-190`）在启动时**自动应用**，调用自
  `loadDb`（`db/index.ts:18`）；没有手动步骤。测试迁移一个全新的内存 DB
  （`__tests__/setup.ts`）。
- `migrateDatabase` 在该次运行中把外键**关闭**，并在 `finally` 中恢复
  （`migrate.ts:159-177`），因为迁移器会把每个迁移包在事务里，而事务中
  `PRAGMA foreign_keys=OFF` 是空操作；历史上搞错这一点会把 message
  files/reactions 级联删掉（`migrate.ts:132-139`）。
- `backupDatabase`（`migrate.ts:96-130`）：在应用待处理迁移之前，若
  `config.server.backupDatabase` 开启（默认 `true`，`config.ts:104`），它会在
  `backups/<db>.before-<firstPendingTag>.sqlite` 下取一份 `VACUUM INTO` 快照，若已存在
  相同快照则跳过（`migrate.ts:106-120`）。迁移之后它报告（而非抛出）外键违规
  （`migrate.ts:24-51`、`189`）。
- 数据迁移是按字面 `--> statement-breakpoint`（带空格）拆分手写的 SQL；绝不要编辑
  已提交的迁移，而是新增一个。
- Seeding（`db/seed.ts:39-217`）仅在 `settings` 为空时运行（`seed.ts:40-42`）：两个
  分类、四个频道、Owner + Member 角色、一个 `Sharkord` 用户、一条欢迎消息，
  Owner 获得全部权限 / Member 获得 `DEFAULT_ROLE_PERMISSIONS`（`seed.ts:171-192`），
  并打印一个一次性访问 token（`seed.ts:200-216`）。

## 5. 服务端代码分层与安全检查顺序

`apps/server/src` 的边界：

- `routers/<domain>/`——**每个文件一个** tRPC procedure，按其所做之事命名；文件夹的
  `index.ts` 只组合 `t.router({...})` map。订阅放在该领域的 `events.ts`。新端点是新
  文件。
- `db/queries/`（读）与 `db/mutations/`（写）——每表/每领域一个文件；任何被多于一个
  路由复用的东西都放在这里。
- `db/publishers.ts`——由 subscription 消费的实时事件发布。
- `helpers/`——领域感知的逻辑（permissions、paths、file crypto、sanitizing）；`utils/`——
  无领域知识的基础设施。若有疑问，它是 helper。
- `queues/`——脱离请求路径的后台工作，测试中经 `queues/drain.ts:7-15` 排空；`crons/`——
  定时任务（每 15 分钟的文件清理，`crons/index.ts:9-21`、`crons/cleanup-files.ts:6-29`）。
- `plugins/`——插件加载、注册表、事件总线（第 6 节）。

约定：仅具名导出，服务端文件声明为 `const foo = ...` 并在底部导出；`T` 前缀类型；
kebab-case 文件名；不用 `any`。

### 5.1 每个请求的安全检查顺序

源自 `AGENTS.md:120-137`，在下列各处路由中被验证。最廉价、最宽泛的优先；在所有检查
通过之前不会有任何变更：

1. **认证（Authentication）**——基于 `protectedProcedure` 构建（`utils/trpc.ts:135-137`）。
2. **限流（Rate limiting）**——`rateLimitedProcedure` 搭配 `config.rateLimiters`（`utils/trpc.ts:88-131`）。
3. **输入校验（Input validation）**——`.input(z.object({...}))`，校验形状*与*边界。
4. **全局权限（Global permission）**——`ctx.needsPermission(Permission.X)`（`utils/wss.ts:143-150`）。
5. **存在性（Existence）**——加载该行并 `invariant(row, { code: 'NOT_FOUND' })`（`utils/invariant.ts`）。
6. **频道作用域（Channel scope）**——先 `assertChannelAccess`（DM membership + `VIEW_CHANNEL`，
   `helpers/assert-channel-access.ts:5-11`）再 `ctx.needsChannelPermission(...)`。绝不要
   信任输入里的 `channelId` 胜过已存储行上的那个。
7. **归属/提权（Ownership / elevation）**——owner-or-privileged 放在最后
   （`helpers/load-message-for-write.ts:19-32`）。
8. **服务器设置门（Server settings gates）**——功能开关/配额（uploads enabled、DM file
   sharing、max files per message）。
9. **净化（Sanitize）**——`sanitizeMessageHtml`，然后**重新校验**（非空可能变为空）。

完整示例，`routers/messages/send-message.ts`：rate limit + protected
（`send-message.ts:37-41`）、input schema（`:42-50`）、permissions（`:52-58`）、
parent/reply 存在性与同频道（`:60-109`）、DM 解析 + settings 门（`:113-139`）、非空
检查 + sanitize + 复查（`:141-152`）、plugin hooks（`:154-161`），然后一个**同步的**
`db.transaction` 完成写入（`:283-311`）。上传遵循同样的 HTTP 形态：rate limit
-> zod headers -> token -> permission -> settings（`upload.ts:34-102`）。保持事务回调
同步（`AGENTS.md`；由 `__tests__/transactions.test.ts` 守护）。

`/login` 是刻意的 pre-auth 例外：一个公开、限流的路由，运行 `beforeLogin` hook，
对未知身份使用 dummy argon2 校验以保持 timing 平稳（`login.ts:51-62`、`:115`），并在
成功时把遗留的 SHA256 hash 升级为 argon2（`login.ts:156-185`）。

## 6. 插件系统

**加载。** `plugins/index.ts` 是 `PluginManager`。`loadPlugins` 仅在
`settings.enablePlugins` 开启时运行，加载持久化状态，并扫描 `PLUGINS_PATH` 下的目录
（`plugins/index.ts:512-535`）。每个插件是一个文件夹，含必需的 `manifest.json`、
服务端入口与客户端入口（`readManifest`，`plugins/index.ts:373-411`）。`load`
（`:611-742`）确保状态、跳过已禁用插件、校验 SDK 版本、构建 context、动态 import 服务端
入口、在超时下运行 `onLoad`，并在版本变化时运行 `onUpgrade`。超时集中在
`execution-timeout.ts:1-27`（生命周期/命令/动作 30s，事件处理器 10s）。`init` 监听目录并
卸载从磁盘移除的插件（`plugins/index.ts:483-510`）。启用状态、设置与版本持久化于
`plugin_data`（`schema.ts:556-564`）；每用户存储于 `plugin_user_data`
（`schema.ts:566-583`）。

**事件总线。** `plugins/event-bus.ts` 与面向客户端的 `pubsub` 分开。插件用
`ctx.events.on(...)` 订阅（`plugins/create-context.ts:245-248`）。`emit` 用
`Promise.allSettled` 加每处理器超时进行扇出，使一个坏插件无法阻塞其他插件；拒绝会被
记录（`event-bus.ts:55-95`）。核心会发出例如 `message:created`
（`routers/messages/send-message.ts:323-330`）与 `user:left`（`utils/wss.ts:237-240`）。

**Hooks。** `load` 中的 `registerBefore*`（`plugins/index.ts:663-672`）覆盖
`beforeFileSave`、`beforeMessageSave`、`beforeChannelCreate`、`beforeVoiceJoin`、
`beforeLogin`。`runHook`（`plugins/run-hook.ts:21-62`）按顺序运行处理器；处理器可以
**拒绝**请求（消息上限 200 字符，`run-hook.ts:50`）或**更新**载荷传给下一个。

**权限。** 能力类型分为 `COMMAND`、`ACTION`、`COMPONENT`、`HTTP_ROUTE`
（`packages/shared/src/plugins/capabilities.ts:3-14`）。一个能力可声明全局
`requires: Permission`；管理员还可以把它额外限制到角色
（`PluginCapabilityMode.RESTRICTED`），存于 `plugin_capabilities` 与
`plugin_capability_roles`（`schema.ts:585-615`）。执行：HTTP 路由先解析调用者是否
需要认证，再判断能力访问，然后 401/403（`http/plugin-route.ts:45-91`）；命令要求
`USE_PLUGINS` **且** `canUseCapability(...)`（`send-message.ts:177-186`）。context 暴露
基于 db 的动作（messages、channels、roles、users、moderation、push、user data）与
权限辅助函数（`plugins/create-context.ts:239-327`）。

**为什么不设沙箱。** 插件按设计**运行在服务器进程内部**："Plugins run inside
the server process. There is no sandbox, so nothing here is a security boundary: it is the
supported way to reach the host, not a fence around it"（`packages/plugin-sdk/src/index.ts:388`）；
`AGENTS.md:53` 也重复了这一点。信任模型是**安装时信任（install-time trust）**：启用一个
插件即像信任服务器二进制一样信任其代码。能力系统买到的是*治理（governance）*（哪些
用户可以触及某个命令或路由），而不是隔离（containment）。

## 7. 客户端结构

- `features/`——Redux Toolkit 状态，通过 hooks/selectors 读取，绝不直接伸进
  store 形状。store 有四个 slice：`app`、`server`、`dialog`、`serverScreen`
  （`features/store.ts:7-23`）。`features/server/*` 各领域**没有自己的 slice**——
  它们的 reducer 全部位于 `features/server/slice.ts`，每个领域文件夹持有
  `actions.ts`、`selectors.ts`、`hooks.ts`、`subscriptions.ts`。
- `components/`——每个组件一个文件夹，含 `index.tsx` 加本地部件、`helpers.ts`
  与 `hooks/`；`screens/`——顶层路由，在
  `components/routing/index.tsx:22-67` 中根据连接状态选中。
- `hooks/`——通用可复用的 `use-*.ts`；`lib/trpc.ts` 是 tRPC 客户端（所有服务端调用
  都经过 `getTRPCClient()`），`lib/utils.ts` 通用辅助函数；`helpers/` 纯函数
  （URLs、storage、formatting、audio）。通用、可样式化、无逻辑的组件属于
  `packages/ui`。

Selector 与缓存（源自 `AGENTS.md`，在 `features/server/selectors.ts` 中验证）：直接读取用
普通函数（`selectors.ts:38-40`）；一构建数组/对象就用 `createSelector`；由该参数作键的
参数化 selector 用 `createCachedSelector`（re-reselect）（`selectors.ts:80-90`）。返回一个
稳定的模块级空值，而不是新鲜的 `?? {}` / `?? []`。跨领域 selector 位于
`features/server/selectors.ts`，绝不在领域文件里（循环导入）；在 selector 中派生，绝不
在组件里内联。`useCan()` / `useChannelCan()` 包裹权限检查
（`features/server/hooks.ts:69-117`），owner 总是通过。

客户端插件由 `components/plugins-controller/index.tsx:9-37` 引导，它在加入**之前**获取
`/plugin-components`（以便 slot 能在登录界面渲染）；宿主 store 在 `main.tsx:18,26` 中
暴露到 `window`。此后，插件状态像其他一切一样经 tRPC 流动。

## 8. 运行时态（runtime state）与持久化状态

`src/runtimes` 加上 WS/pubsub 层**只**持有活的、短暂的状态。任何必须跨重启存活的
东西都经 `db/schema.ts`。

**仅在内存中：** WS presence（user -> sockets 与 user -> IP 两个 map，`utils/wss.ts:35-37`；
在线状态派生自 socket map，`wss.ts:131-133`）；pub/sub 投递（`EventEmitter` 与
每用户/每频道监听器 map，`utils/pubsub.ts:137-320`）；语音（`voiceRuntimes` map 与所有
mediasoup 状态——routers、transports、producers、consumers、external streams，
`runtimes/voice.ts:25`，在 `routers/others/join.ts:141-142` 中被消费）；插件运行时
（`plugins/index.ts:78-115`）；限流器桶（`utils/rate-limiters`）、cron
任务（`crons/index.ts:12-20`），以及 manifest 图片尺寸缓存（`http/manifest.ts:13-16`）。

**持久化（数据库）：** identities、roles and permissions、channels and categories、
messages/threads/reactions/read states、files、settings、invites、activity log and logins、
OIDC flow rows，以及各插件表。语音成员资格（voice membership）被刻意**不**持久化：它
只在 socket 连接期间存在，关闭时用户被从运行时中移除
（`wss.ts:223-232`）。后台写入经队列到达 DB
（`queues/activity-log/index.ts:24-44`、`queues/message-metadata/index.ts:12-22`），因此
一个路由可以在其副作用落地之前返回；测试会排空队列（`queues/drain.ts:7-15`）。

## 9. 已知平台问题（Known platform issues）

### 9.1 `plugin-routes.test.ts` —— 连接中断断言

- 测试：`apps/server/src/http/__tests__/plugin-routes.test.ts:467`，
  `drops the connection when a handler throws after writing headers`。
- Mock 处理器：`apps/server/src/__tests__/mocks/plugins/plugin-http-routes/server/index.js:22-27`
  写入 `200` 响应头与部分 body，然后抛出。
- 服务器行为：因为响应头已经发送，catch 块调用 `res.destroy()`
  而不是写入错误（`http/index.ts:187-197`）。
- 断言：测试期望 `fetch(...).then(r => r.text())` **被拒绝（reject）**
  （`plugin-routes.test.ts:468-475`）。

**成因分析（已在本环境验证）。** CI 之外的这个失败是由
`HTTP_PROXY` / `HTTPS_PROXY` 环境变量触发的，而**不是** macOS 本身：

- 未设置代理时，测试反复且确定性地通过（整个文件 43/43，过滤运行，以及作为完整
  server 套件的一部分）。
- 设置 `HTTP_PROXY=http://127.0.0.1:7890` 与 `HTTPS_PROXY=http://127.0.0.1:7890` 后，
  它确定性地失败，报 `Expected promise that rejects / Received promise that
  resolved`。
- 加上 `NO_PROXY=localhost,127.0.0.1` 后它再次通过。

机制：配置了代理时，Bun 的 `fetch` 不会把响应中途的 socket
销毁呈现为拒绝——响应头与部分 body 已刷出，因此 promise 解析（resolve）。没有代理时，
同样的销毁会如断言所期望的那样拒绝。上游 CI 在
ubuntu 上运行且无代理，因此在那里通过；而一个导出了代理（为了
访问 GitHub，或经由 shell profile）的开发者 shell 会在本地失败。

关于历史解释的说明：这一点此前被描述为 OS 层面的
Linux 与 macOS 差异。在本次验证中，触发因素是代理变量，且
行为与 OS 无关。把 OS 的说法视为**未确认（unconfirmed）**；代理触发因素是可复现的。
同样的代理效应是否会破坏其他基于 `fetch` 的测试尚未
穷尽检查。

### 9.2 在 dev 服务器运行时同时跑 server 测试套件

dev 服务器绑定 mediasoup WebRTC UDP 端口 `40000`（`config.ts:124-125`）。在 dev 运行时跑
server 套件会绑定失败（`uv_udp_bind() ... address already in use ...
createWebRtcServer`）；用 `SHARKORD_WEBRTC_PORT=<free port>` 移动测试端口。注意：
设置任何 `SHARKORD_*` 变量随后会使 `__tests__/config.test.ts:124-126`
（`should leave the config untouched when no variable is set`）失败，因为它用活的
环境对比 `applyEnvOverrides(defaultConfig)` 与 `zConfig.parse(defaultConfig)`。那个失败
是预期内的噪声，不是回归。

## 最先看哪里（贡献者速查）

- **端点**：在 `routers/<domain>/` 下新建文件，在领域 `index.ts` 中接线，遵循
  5.1 的检查顺序，把写入包在同步事务中。
- **数据库**：编辑 `db/schema.ts`，运行 `bun run db:gen`，提交 SQL **以及** `meta/`；
  绝不要编辑已提交的迁移。
- **Helper**：数据用 `db/queries`/`db/mutations`，领域规则用 `helpers/`，基础设施用
  `utils/`。先搜索——两份拷贝是上限。
- **UI 状态**：reducer 在 `features/server/slice.ts`，派生状态在 selector 中，经
  `hooks.ts` 访问。**字符串** 放到 `apps/client/src/i18n/locales` 下的每个 locale（运行
  `synci18n`），绝不硬编码。
- **收尾之前**：在仓库根运行 `bun run magic` 与 `bun run test`，留意第 9 节的
  注意事项。
