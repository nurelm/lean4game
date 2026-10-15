#!/usr/bin/env bash
# Runs the cypress e2e suite inside Docker: builds the image if stale, starts a
# production-mode relay in a container and runs cypress (Electron under xvfb)
# against it - the Docker equivalent of `npm run test:prod`.
#
# Usage:
#   scripts/run_tests.sh                       run the whole suite
#   scripts/run_tests.sh --spec cypress/e2e/01-basic-interface.cy.ts
#                                              forward extra args to `cypress run`
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
. "$LIB_DIR/docker_compose.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "Building image (cached layers make this fast when nothing changed)..."
docker_compose --profile test build

echo "Running cypress in Docker..."
docker_compose --profile test run --rm test bash docker/run-tests.sh "$@"
status=$?

if [ "$status" = 0 ]; then
    echo "All tests passed."
else
    echo "Tests failed (exit ${status}). Cypress screenshots are inside the test container; run it with --entrypoint bash for inspection:" >&2
    echo "  scripts/run_local.sh shell  (once the app stack is up) or:" >&2
    echo "  docker compose --project-name lean4game --profile test run --rm --entrypoint bash test" >&2
fi
exit "$status"