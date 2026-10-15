#!/usr/bin/env bash
# Runs the cypress e2e suite against a production-mode relay inside this
# container. Mirrors the "Run Cypress tests (Production mode)" step of
# .github/workflows/test.yml (npm run test:prod) without re-running the
# build: the image already ships prebuilt artifacts.
#
# Extra arguments are forwarded to `cypress run`, e.g.
#   bash docker/run-tests.sh --spec cypress/e2e/01-basic-interface.cy.ts
set -uo pipefail

cd "$(dirname "$0")/.."   # repo root inside the container (/srv/lean4game)

export NODE_ENV=production
export PORT=3000
export API_PORT=8010
export NO_BWRAP=true

node relay/dist/src/index.js &
server_pid=$!

kill_server() {
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
}
trap kill_server EXIT

echo "Waiting for the relay to come up..."
ok=0
for _ in $(seq 1 90); do
    if node -e "fetch('http://127.0.0.1:3000/api/games').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
        ok=1
        break
    fi
    sleep 1
done
if [ "$ok" != "1" ]; then
    echo "The relay did not become ready - see the log output above." >&2
    exit 1
fi

# Electron (cypress' default browser) needs a virtual display in a container.
set +u
xvfb-run -a npx cypress run "$@"
status=$?
exit "$status"