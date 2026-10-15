# Running lean4game with Docker

Everything (Lean toolchain, Node.js, dependencies, builds, tests) runs inside
containers. On the host you only need **Docker with the compose plugin**
(tested with Docker 29 / Compose v5; OrbStack and Docker Desktop both work) —
plus `curl`, which macOS and most Linux setups ship with.

## Quick start

```bash
./scripts/run_local.sh up
```

This builds the image (Docker layer caching makes repeat runs fast when
nothing changed), starts the container and prints a banner with the URL:

- App: `http://localhost:3000` (override with `LEAN4GAME_PORT`)
- The bundled `TestGame` is listed on the landing page, because the container
  runs the relay in `NODE_ENV=development`. Play it directly at
  `http://localhost:3000/#/g/local/TestGame`.

Useful commands:

| Command | Purpose |
|---------|---------|
| `./scripts/run_local.sh up` | start the server (default action) |
| `./scripts/run_local.sh logs` | tail the app logs |
| `./scripts/run_local.sh ps` | container status (incl. health) |
| `./scripts/run_local.sh shell` | bash inside the running container |
| `./scripts/run_local.sh stop` / `restart` / `down` | lifecycle |
| `./scripts/run_local.sh build` | build the image only |

## Configuration

Set environment variables before running, or put them in a `.env` file in the
repo root (see `.gitignore`):

| Variable | Default | Meaning |
|----------|---------|---------|
| `LEAN4GAME_PORT` | `3000` | host port published for the app |
| `LEAN4GAME_NODE_ENV` | `development` | `development` serves and lists local games; `production` matches the hosted behaviour |

In `production` mode local games are disabled. Remote games are served from
`games/<owner>/<repo>` inside the container and played at
`/#/g/<owner>/<repo>`: either import them through the regular import API
(needs `LEAN4GAME_GITHUB_USER` / `LEAN4GAME_GITHUB_TOKEN`, see
`relay/src/import.ts`) via a compose override, or mount a previously built
game directory there.

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

   Then run `./scripts/run_local.sh up` (or `restart`) — the landing page will
   list it. Your game's game server is spawned with its own `lean-toolchain`;
   elan is preinstalled and can download other toolchains on demand (this
   needs network access inside the container).

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

## Running tests

```bash
./scripts/run_tests.sh
```

Builds the image if needed, then runs the cypress e2e suite in the `test`
compose service: a production-mode relay (`NODE_ENV=production`), cypress
running headless with Electron under `xvfb` inside the same container. This is
the Docker equivalent of the "Run Cypress tests (Production mode)" step in
[.github/workflows/test.yml](../.github/workflows/test.yml) (`npm run
test:prod`), without re-running the builds at test time.

Extra arguments are forwarded to `cypress run`:

```bash
./scripts/run_tests.sh --spec cypress/e2e/01-basic-interface.cy.ts
```

### Known upstream test failures

As of this branch, running the full suite gives **19/26 passing** (the whole
`01-basic-interface.cy.ts` and 13 of 20 in `game-features.cy.ts`). The 7
failures are not caused by the Docker setup: upstream's own CI has been red
on `main` since 2026-10-02 with all matrix entries (`Linux/macOS/Windows -
electron`) failing at the "Run Cypress tests" step before this branch existed.
The failing tests all type into the Monaco editor and trip cypress'
"requires a valid typeable element" check on `.view-line`; a test-run
screenshot shows the game server itself working (level LSP serves the goal,
editor and hints render).

## How the image is built

- `ubuntu:24.04` + Node.js 26 (same major version as CI) + elan with every
  toolchain pinned by a `lean-toolchain` file in the repo (currently
  `v4.33.1`, used by both `server/` and `cypress/TestGame`).
- Build stage mirrors CI: `npm ci` → `lake build` (GameServer and its pinned
  git deps) → `tsc -b` (relay) → `vite build` (client) → `lake build`
  (TestGame), then a sanity check that the artifacts exist.
- Runtime stage ships the prebuilt artifacts, full `node_modules` (the relay
  resolves transitive dependencies such as `vscode-ws-jsonrpc` from the hoisted
  root `node_modules`), the cypress binary cache and elan.
- The bundled TestGame is exposed twice: as `/#/g/test/TestGame` (from
  `cypress/TestGame`, how the e2e suite reaches it) and as a hardlinked local
  game at `/srv/TestGame` for the landing page in development mode.
- Expect a multi-GB image: it contains a Lean toolchain (~2 GB) plus
  `node_modules` with the cypress binary and Electron libraries.

## Security note

The hosted server sandboxes every game session with
[bubblewrap](../../README.md#security); inside this container that is disabled
(`NO_BWRAP=true`), because nested namespaces in a plain container would need
extra privileges. Isolation therefore relies on the container itself — treat
this as a **local, single-user** deployment and do not expose it to untrusted
users.