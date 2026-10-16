# AGENTS.md

Notes for coding agents (and humans who don't want to re-explain everything).

## What this is

`lean4game` — the web platform behind [lean4game.com](https://live.lean-lang.org/):
players open a game, solve Lean 4 proof exercises in a browser, and their progress
is stored. Three parts:

| Part | What it is |
|------|------------|
| `server/` | Lean 4 library `GameServer` (lake package). Implements the game RPC methods used by the client (e.g. `Game.getProofState` in `GameServer/RpcHandlers.lean`) and the game DSL (`Statement`, `Hint`, `TacticDoc`, ...). Games depend on this package, they don't get patched here for tests. |
| `relay/` | Node/TypeScript express + websockets backend. Serves the built client, spawns one Lean game-server process per websocket (`relay/src/serverProcess.ts`, `websocket.ts`), and translates messages: the level file content the client edits is wrapped into a `Runner ... := by` snippet (client lines shift by `PROOF_START_LINE = 2`!). |
| `client/` | React app (React 18 + jotai + `lean4monaco`). Two input modes for each level: **typewriter** (one-line command input, proof steps shown as a chain with hints) and **editor** (full Monaco editor with a goal panel next to it). |

## Hard rule: nothing runs on the host

Everything (Lean toolchain, node_modules, builds, servers, cypress) runs inside
Docker containers. On the host you need **Docker with the compose plugin** and
`curl`, nothing else. See [DOCKER.md](DOCKER.md) for the full Docker documentation.

This matters doubly for coding agents: the agent terminal sandbox usually cannot
reach the docker socket; if your environment allows it, request unsandboxed
execution (or an equivalent grant) for `docker`/`./scripts/*` commands.

## Scripts (all live in `scripts/`)

| Script | Purpose |
|--------|---------|
| `scripts/run_local.sh` | Run the app: `up` (build if stale + start + banner), `build`, `logs`, `ps`, `shell`, `stop`, `restart`, `down`. |
| `scripts/run_tests.sh` | Full cypress e2e suite in **production mode** (relay with built bundles; Docker equivalent of CI's `npm run test:prod`). Extra args are forwarded to `cypress run`. |
| `scripts/run_tests_dev.sh` | Same suite in **development mode** (vite dev server + development relay; Docker equivalent of CI's `npm run test`). React StrictMode double-mounting applies. |
| `scripts/run_terminal.sh` | `exec` into the running `app` container (interactive bash if no args, `bash -c "<args>"` otherwise); if the app container is not running, starts an ephemeral one from the same image and removes it when done. |

`scripts/lib/docker_compose.sh` pins the compose invocation (`--project-name
lean4game`, root `docker-compose.yml`) so all scripts agree no matter the cwd.
`scripts/lib/repo_root.sh` resolves the repo root.

Services in `docker-compose.yml`: `app` (the server; dev-mode serves local games
from `/srv`) and `test` (profile `test`; runs `docker/run-tests.sh` or
`docker/run-tests-dev.sh`).

## Running the tests

```bash
./scripts/run_tests.sh                  # 26 tests in production mode
./scripts/run_tests_dev.sh              # 26 tests in development mode
./scripts/run_tests.sh --spec cypress/e2e/game-features.cy.ts   # one spec
```

Current state (after the fixes described below): **26/26 passing** in both modes,
stably.

Test structure:

- `cypress/e2e/01-basic-interface.cy.ts` — landing page, popups.
- `cypress/e2e/game-features.cy.ts` — the meat: navigation, typewriter input,
  hints, inventory/documentation, level completion, editor mode (`Current Goal`,
  cursor-position goals, `unsolved goals` notices), preferences/languages.
- `cypress/TestGame/` — a minimal game (`TestWorld`, 3 levels) built via
  `npm run build:test` (baked into the image); the suite plays it as
  `/#/g/test/TestGame`. Don't change it without expecting test fallout.

**Do not modify the test files to make them pass.** Fixes belong in the client
(or server); the tests describe the intended UX.

## Debugging loop inside containers

- Rebuild is cached: `./scripts/run_local.sh build` after changing client code
  only re-runs the vite build layer (~1–2 min); the Lean server build is cached.
- To inspect the container: `./scripts/run_terminal.sh 'ls /srv/lean4game'` etc.
- To *see* a failure: run cypress with a bind-mounted out dir for screenshots:
  `docker compose --project-name lean4game --project-directory . --file docker-compose.yml --profile test run --rm -v /tmp/out:/out test bash docker/run-tests.sh --spec cypress/e2e/game-features.cy.ts --config screenshotsFolder=/out`
  (screenshots are written per failing test; look at them, don't guess).
- For experiments, bind-mount a throwaway spec into the container instead of
  editing the real ones:
  `-v /tmp/probe.cy.ts:/srv/lean4game/cypress/e2e/zz-probe.cy.ts` with
  `--spec cypress/e2e/zz-probe.cy.ts`. Delete it once done.
- `cy.intercept` does not capture the LSP traffic (websocket). For server-side
  messages run the relay with `NODE_ENV=development`: it logs every message
  (`CLIENT:` / `SERVER:` lines).

## Client architecture notes (the parts tests touch)

- The whole app shares one `LeanMonaco` instance (`lean4monaco`), started in
  `client/src/app.tsx`; per-level editors are `LeanMonacoEditor` (`PlayableLevel.tsx`)
  into `GameEditor`'s `.codeview`, plus the one-line typewriter editor
  (`TypewriterCommandline.tsx`, bare `monaco.editor.create`).
- State flows through jotai atoms in `client/src/store/editor-atoms.ts`:
  `proofQueryAtom` fetches `Game.getProofState` (whole proof = steps with goals
  + game hints + diagnostics); `codeAtom` setters write into the Monaco model;
  `typewriterModeAtom` is persisted via progress.
- Hints render in `ChatPanel` (typewriter mode) and `GameInfoview` (editor mode)
  using `filterHints` (only *new* hints per step).
- Diagnostics/messages render via `client/src/components/editor/messages/Error.tsx`.

## Known sharp edges (fixed recently — keep intact)

1. `TaggedText_stripTags` (from `@leanprover/infoview-api`) only follows
   `t.tag[1]`, but the game server puts the readable text inside *expression
   embeds* (`t.tag[0] = {expr: ...}`), so tagged messages strip to `''`.
   `messages/Error.tsx` has a local `messageToString` handling both shapes —
   don't "simplify" it back to the library function (that bug made all error
   messages invisible).
2. The proof state must be refetched when the server publishes diagnostics
   (effect in `PlayableLevel.tsx`); a refresh 1s after a code change alone is
   not enough for late-arriving diagnostics.
3. Clicking into either Monaco editor re-asserts focus on `mousedown`
   (capture) plus a `setTimeout(0)` re-assertion. That's deliberate: synthetic
   mouse events (cypress, and evidently also some real-world paths) blur the
   focused editor again when the click target has no focusable ancestor — bare
   Monaco's `.view-lines` has none. Removing this reintroduces flaky
   `cy.type()` failures ("requires a valid typeable element").
4. The game's goal panel is `GameInfoview.tsx` (client-rendered in the
   `.infoview` div); lean4monaco's VS Code-style webview iframe inside `.infoview`
   is `display: none` (kept for lean4monaco's RPC session bookkeeping only) —
   same as the pre-refactor app.

## Environment

`.env` in the repo root (gitignored) or env vars, see DOCKER.md:
`LEAN4GAME_PORT` (default 3000), `LEAN4GAME_NODE_ENV` (default `development`;
`production` disables local games), `LEAN4GAME_GITHUB_USER`/`LEAN4GAME_GITHUB_TOKEN`
for importing remote games. Inside the container: `PORT` (relay listener),
`API_PORT` (observer API), `NO_BWRAP` (bubblewrap sandboxing is disabled, the
container is the sandbox — never expose such a deployment to untrusted users).

## Git

The working branch at the time of writing is `feature/dockerize-it` (Docker
work layered on upstream `main`). Commits welcome; no pushing without asking.