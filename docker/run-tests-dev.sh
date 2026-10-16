#!/usr/bin/env bash
# Runs the cypress e2e suite in development mode, mirroring the "Run Cypress
# tests (Development mode)" step of .github/workflows/test.yml (`npm run test`):
#
#   relay (development mode) on :8080  - like `npm --workspace relay run dev`
#   vite dev server        on :3000    - like `npm --workspace client run dev`,
#     proxying /api, /websocket, /data, /i18n, /import to :8080
#   cypress (Electron under xvfb) against http://localhost:3000
#
# Unlike docker/run-tests.sh (production bundles), this serves the client
# through vite in dev mode, so React StrictMode double-mounting applies.
#
# Extra arguments are forwarded to `cypress run`, e.g.
#   bash docker/run-tests-dev.sh --spec cypress/e2e/game-features.cy.ts
set -uo pipefail

cd "$(dirname "$0")/.."   # repo root inside the container (/srv/lean4game)

export NODE_ENV=development
# the relay listens on `PORT`; the vite dev server uses 3000 and proxies to it
export PORT=8080
export API_PORT=8010
export NO_BWRAP=true

node relay/dist/src/index.js &
server_pid=$!

kill_server() {
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    kill "$vite_pid" 2>/dev/null || true
    wait "$vite_pid" 2>/dev/null || true
}
trap kill_server EXIT

echo "Waiting for the relay to come up..."
ok=0
for _ in $(seq 1 90); do
    if node -e "fetch('http://127.0.0.1:8080/api/games').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
        ok=1
        break
    fi
    sleep 1
done
if [ "$ok" != "1" ]; then
    echo "The relay did not become ready - see the log output above." >&2
    exit 1
fi

echo "Starting the vite dev server..."
npm --workspace client run dev &
vite_pid=$!

echo "Waiting for the vite dev server..."
ok=0
for _ in $(seq 1 90); do
    if node -e "fetch('http://127.0.0.1:3000/').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
        ok=1
        break
    fi
    sleep 1
done
if [ "$ok" != "1" ]; then
    echo "The vite dev server did not become ready - see the log output above." >&2
    exit 1
fi

# Electron (cypress' default browser) needs a virtual display in a container.
set +u
xvfb-run -a npx cypress run "$@"
status=$?
exit "$status"