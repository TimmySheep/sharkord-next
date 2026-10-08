# Contributing to Covy

**Languages:** English | [中文](CONTRIBUTING.zh-CN.md)

Thanks for considering it. This project is a community fork — see the [README](README.md) for what it is
and why it exists, and [`ROADMAP.md`](ROADMAP.md) for the plan and the things we have decided **not** to do.

## The two rules that matter most

1. **Stay mergeable with upstream.** We keep working in upstream's shape. Changes that make
   `git merge upstream/development` painful need a very good reason, and the reasoning belongs in the PR.
2. **No over-engineering.** This is upstream's own core principle and we keep it: add the smallest thing
   that works, avoid new abstractions until a second call site exists, and prefer deleting code over
   adding configuration.

[`AGENTS.md`](AGENTS.md) is the authoritative style guide for anything under version control. Read it
before your first PR. The short version: kebab-case file names, named exports over default exports,
arrow functions, immutability, no em dashes in code or commit messages, and user-facing strings go
through i18n (never hardcoded).

## Welcome: identify the problem before changing code

Covy is an unofficial compatible client for Sharkord, not an independent server project. We welcome **Android, iOS and Apple Watch** implementation, testing, UI, accessibility, compatibility research and documentation. Native desktop work is deferred; general server and web / PWA improvements belong upstream first.

1. Search existing Issues. Every PR must reference a new or existing Issue in this repository.
2. Explain the problem / use case, affected platform, Covy version or commit and Sharkord server version. Bugs need reproduction steps, expected and actual behaviour; features need a reason users need them.
3. Identify the modules, intended scope and verification plan. Comment on an existing Issue if you want to contribute rather than opening a duplicate.
4. Agree on direction with the maintainer before implementing new features, architecture or protocol changes, dependencies, or deferred desktop work. Small fixes and documentation corrections still link an Issue but do not need a lengthy design discussion.
5. Keep each PR focused on one problem. Avoid unrelated refactors or formatting changes. The maintainer may request a smaller scope or decline a merge.

Redact tokens, private messages and personal information from logs and screenshots. AI assistance is welcome, but contributors must understand and take responsibility for their changes; generated code without execution evidence is not sufficient.

## Development setup

```bash
git clone https://github.com/TimmySheep/sharkord-next.git
cd sharkord-next
bun install                      # Bun 1.3.14 is the pinned, tested version
bun run test
cd apps/server && bun run dev     # :4991
cd apps/client && bun run dev     # :5173  (Vite; needs Node 20.19+/22.12+)
```

Useful scripts (all from the repository root):

| Command | Does |
| --- | --- |
| `bun run test` | Unit tests in every workspace (1458 server / 84 client / 209 shared) |
| `bun run test:e2e` | Playwright end-to-end suite |
| `bun run magic` | `format` + `check-types` + `lint` — run this before pushing |
| `bun run format:check` | Formatting only, no writes |
| `bun run check-types` | TypeScript only |
| `bun run lint` | Lint only |
| `bun run knip` | Unused files/exports/dependencies |

### Two environment traps

- **Never run the test suite with `HTTP_PROXY` / `HTTPS_PROXY` set.** Bun's `fetch` sends the test
  client's localhost requests through the proxy and one connection-drop assertion fails deterministically.
  Unset the variables, or export `NO_PROXY=localhost,127.0.0.1`. Analysis:
  [`docs/ARCHITECTURE.md` §9](docs/ARCHITECTURE.md).
- **Stop your dev server before running the full suite.** The dev server holds the WebRTC port, and the
  test harness needs it. Also note that setting *any* `SHARKORD_*` variable makes the config-defaults test
  fail by design (`apps/server/src/config.test.ts`).

## Branch and commit conventions

- `development` is the integration branch and tracks upstream compatibility. Do not rewrite its history with force pushes.
- Branch off `development`, keep the branch focused, name it after the work
  (`fix/mobile-safe-area`, `feat/p2p-signalling`).
- Commits follow upstream's conventional style, with the issue or PR reference when there is one:

  ```
  fix(552): keep subscriptions alive across device sleep
  feat(105): add apple-mobile-web-app meta tags
  docs: correct the proxy caveat in the test notes
  ```

- Sign nothing special, but **do** use your own git identity. If you are contributing from this machine,
  use your own name and email, not the maintainer's identity.

## Pull requests

A good PR here is small and verifiable. Before you open one:

1. Link the Issue (`Fixes #123` for a resolved issue, `Refs #123` for related work) and target `development`. State the affected platform, modules and compatibility impact.
2. Run the relevant platform build and tests and report exact commands and results. For TypeScript / shared / server changes, run `bun run magic` and `bun run test`. For documentation-only changes, check links and formatting; explain non-applicable checks rather than claiming they passed.
3. New behaviour has a test, or the PR body explains why a test is not practical.
4. Documentation under `docs/` is updated when behaviour it describes changes.
5. The PR body says **what changed, why, and what you verified** — including commands and their output.
   Claims that were not actually verified should be labelled as such; this project documents verified
   versus unverified explicitly and expects the same in PRs.

Expect review to focus on scope and mergeability with upstream first, style second. If a change is useful
to upstream too, we may ask you to send it there as well.

## Syncing with upstream

```bash
git remote add upstream https://github.com/Sharkord/sharkord.git   # once
git fetch upstream
git checkout development
git merge upstream/development
```

Resolve conflicts in favour of upstream unless the change is one of ours. If a conflict is ours, document
the resolution in the merge commit message.

## Licensing and brand

- Contributions are accepted under the **MIT license**, matching upstream (`inbound = outbound`).
- Keep upstream copyright notices intact.
- Do not use the Sharkord name or logo in a way that suggests this fork is official. Describe it as
  "an unofficial compatible client for Sharkord" — the same wording used in the README.

Upstream's original contribution guide (written for the upstream project, and still worth reading for its
scope and PR philosophy) is preserved verbatim at
[`upstream-notes/UPSTREAM-CONTRIBUTING.md`](upstream-notes/UPSTREAM-CONTRIBUTING.md).
