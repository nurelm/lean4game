#!/usr/bin/env bash
# Runs the cypress e2e suite in development mode inside Docker: builds the
# image if stale, starts a vite dev server + development relay in a container
# and runs cypress (Electron under xvfb) against them - the Docker equivalent
# of the "Run Cypress tests (Development mode)" CI step (`npm run test`).
#
# For the production-mode suite (npm run test:prod equivalent), use
# scripts/run_tests.sh.
#
# Usage:
#   scripts/run_tests_dev.sh                    run the whole suite
#   scripts/run_tests_dev.sh --spec cypress/e2e/game-features.cy.ts
#                                               forward extra args to `cypress run`
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
. "$LIB_DIR/docker_compose.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "Building image (cached layers make this fast when nothing changed)..."
docker_compose --profile test build

echo "Running cypress in Docker (development mode)..."
docker_compose --profile test run --rm test bash docker/run-tests-dev.sh "$@"
status=$?

if [ "$status" = 0 ]; then
    echo "All tests passed."
else
    echo "Tests failed (exit ${status})." >&2
fi
exit "$status"