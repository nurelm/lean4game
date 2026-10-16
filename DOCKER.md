# Running lean4game with Docker

Everything (Lean toolchain, Node.js, dependencies, builds, tests) runs inside
containers. On the host you only need **Docker with the compose plugin**
(tested with Docker 29 / Compose v5; OrbStack and Docker Desktop both work) —
plus `curl`, which macOS and most Linux setups ship with.

## Scripts

All Docker workflows go through two scripts in `scripts/` — you never need to
type a raw `docker compose` command (but you can: `docker-compose.yml` lives
in the repo root).

### `scripts/run_local.sh` — run the server

```bash
./scripts/run_local.sh up       # build if stale, start the server, print banner (default)
./scripts/run_local.sh logs     # tail the app logs
./scripts/run_local.sh ps       # container status (incl. health)
./scripts/run_local.sh shell    # bash inside the running container
./scripts/run_local.sh stop     # stop the app (containers stay)
./scripts/run_local.sh restart  # restart the app container
./scripts/run_local.sh down     # stop and remove containers
./scripts/run_local.sh build    # build the image only
./scripts/run_local.sh help
```

`up` is idempotent — running it again just rebuilds if sources changed (Docker
layer caching makes this fast) and confirms the stack. It waits until the
relay is healthy before printing the banner.

### `scripts/run_tests.sh` — run the test suite

```bash
./scripts/run_tests.sh                       # whole suite
./scripts/run_tests.sh --spec cypress/e2e/01-basic-interface.cy.ts
```

Builds the image if needed, then runs the cypress e2e suite in the `test`
compose service: a production-mode relay (`NODE_ENV=production`), cypress
running headless with Electron under `xvfb`, all in one container. This is the
Docker equivalent of the "Run Cypress tests (Production mode)" step in
[.github/workflows/test.yml](.github/workflows/test.yml) (`npm run
test:prod`), without re-running the builds at test time. Extra arguments are
forwarded to `cypress run`.

### `scripts/run_terminal.sh` — run commands in the app container

```bash
./scripts/run_terminal.sh                  # interactive bash in the app container
./scripts/run_terminal.sh <command...>     # bash -c "<command>" in the app container
```

Execs into the running `app` container if it is up; otherwise starts an
ephemeral one from the same image (built on demand) which removes itself when
the command exits — useful for inspecting the image artifacts or running
one-off commands without keeping a stack around.

## Quick start

```bash
./scripts/run_local.sh up
```

The banner prints, among others:

- App: `http://localhost:3000` (override with `LEAN4GAME_PORT`)
- The bundled `TestGame` is listed on the landing page, because the container
  runs the relay in `NODE_ENV=development`. Play it directly at
  `http://localhost:3000/#/g/local/TestGame`.

## Configuration

Set environment variables before running, or put them in a `.env` file in the
repo root (both are gitignored):

| Variable | Default | Meaning |
|----------|---------|---------|
| `LEAN4GAME_PORT` | `3000` | host port published for the app |
| `LEAN4GAME_NODE_ENV` | `development` | `development` serves and lists local games; `production` matches the hosted behaviour |

In `production` mode local games are disabled. Remote games are served from
`games/<owner>/<repo>` inside the container and played at
`/#/g/<owner>/<repo>`: either import them through the regular import API
(needs `LEAN4GAME_GITHUB_USER` / `LEAN4GAME_GITHUB_TOKEN`, see
[relay/src/import.ts](relay/src/import.ts)) via a compose override, or mount a
previously built game directory there.

## Playing your own game

Local games are directories under `/srv` inside the container that contain
`.lake/gamedata/game.json` (built with `lake build`). Two ways to get there:

1. **Mount a game directory** built inside any Linux/amd64 or linux/arm64
   container. Add an override file `docker-compose.override.yml` (do not
   commit it):

   ```yaml
   services:
     app:
       volumes:
         - /path/to/YourGame:/srv/YourGame
   ```

   Then run `./scripts/run_local.sh restart` — the landing page will list it.
   Your game's game server is spawned with its own `lean-toolchain`; elan is
   preinstalled and can download other toolchains on demand (this needs
   network access inside the container).

2. **Build inside the container** so the artifacts match the image:

   ```bash
   ./scripts/run_local.sh shell
   git clone https://github.com/hhu-adam/GameSkeleton.git   # or your game
   cd GameSkeleton
   lake update -R && lake build
   ```

Remember: local games only exist in `LEAN4GAME_NODE_ENV=development` (the
default); oleans and binaries built by other toolchains or architectures are
not portable, so a game's `.lake` folder should be built inside a container.

## Test results

Running the full suite gives **26/26 passing** (the whole `01-basic-interface.cy.ts`
and all 20 tests in `game-features.cy.ts`). Note that it took a set of client-side
fixes to get there: the infoview panel rendered by `GameInfoview.tsx`, robust
typewriter/editor focusing, and plain-text rendering of Lean's tagged diagnostic
messages. Upstream CI may still be red if it does not include these fixes.

## How the image is built

- `ubuntu:24.04` + Node.js 26 (same major version as CI) + elan with every
  toolchain pinned by a `lean-toolchain` file in the repo (currently
  `v4.33.1`, used by both `server/` and `cypress/TestGame`).
- Build stage mirrors CI: `npm ci` → `lake build` (GameServer and its pinned
  git deps) → `tsc -b` (relay) → `vite build` (client) → `lake build`
  (TestGame), then a sanity check that the artifacts exist.
- Runtime stage ships the prebuilt artifacts, full `node_modules` (the relay
  resolves transitive dependencies such as `vscode-ws-jsonrpc` from the
  hoisted root `node_modules`), the cypress binary cache and elan.
- The bundled TestGame is exposed twice: as `/#/g/test/TestGame` (from
  `cypress/TestGame`, how the e2e suite reaches it) and as a hardlinked local
  game at `/srv/TestGame` for the landing page in development mode.
- Expect a multi-GB image: it contains a Lean toolchain (~2 GB) plus
  `node_modules` with the cypress binary and Electron libraries.

## Security note

The hosted server sandboxes every game session with
[bubblewrap](README.md#security); inside this container that is disabled
(`NO_BWRAP=true`), because nested namespaces in a plain container would need
extra privileges. Isolation therefore relies on the container itself — treat
this as a **local, single-user** deployment and do not expose it to untrusted
users.