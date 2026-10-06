# Contributing to Sharkord Next

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

## Where to start

Small, self-contained work that is ready to pick up:

- **Mobile web / PWA** — the three concrete gaps (no service worker, no `viewport-fit=cover`, no iOS
  standalone meta) are documented with file-level evidence in
  [`docs/ECOSYSTEM_RESEARCH.md` §5.3](docs/ECOSYSTEM_RESEARCH.md). Each is a contained PR.
- **Documentation** — every document in `docs/` is tracked research. If you find a claim that no longer
  matches the code, fixing it is a welcome contribution.
- **Android** — the native Android client is a separate project
  ([`Vigno04/sharkord-android`](https://github.com/Vigno04/sharkord-android), MIT). Protocol-compatibility
  work and a version-pinned compatibility CI are exactly the gaps we care about; see
  [`docs/ECOSYSTEM_RESEARCH.md` §5.1](docs/ECOSYSTEM_RESEARCH.md).
- **Anything upstream would also want** — general bug fixes are best offered upstream first, so both
  projects benefit and our diff stays small.

If you are unsure whether an idea fits, open an issue and ask. "Needs discussion" is a normal state here,
not a rejection.

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

- `development` mirrors upstream. Do not rewrite its history with force pushes.
- Branch off `development`, keep the branch focused, name it after the work
  (`fix/mobile-safe-area`, `feat/p2p-signalling`).
- Commits follow upstream's conventional style, with the issue or PR reference when there is one:

  ```
  fix(552): keep subscriptions alive across device sleep
  feat(105): add apple-mobile-web-app meta tags
  docs: correct the proxy caveat in the test notes
  ```

- Sign nothing special, but **do** use your own git identity. If you are contributing from this machine,
  the identity in use is `TimmySheep <100548146+TimmySheep@users.noreply.github.com>`.

## Pull requests

A good PR here is small and verifiable. Before you open one:

1. `bun run magic` and `bun run test` are clean locally.
2. New behaviour has a test, or the PR body explains why a test is not practical.
3. Documentation under `docs/` is updated when behaviour it describes changes.
4. The PR body says **what changed, why, and what you verified** — including commands and their output.
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
  "an unofficial community project based on Sharkord" — the same wording used in the README.

Upstream's original contribution guide (written for the upstream project, and still worth reading for its
scope and PR philosophy) is preserved verbatim at
[`upstream-notes/UPSTREAM-CONTRIBUTING.md`](upstream-notes/UPSTREAM-CONTRIBUTING.md).
