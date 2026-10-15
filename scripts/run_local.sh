#!/usr/bin/env bash
# Host entry point for the local lean4game Docker stack. Nothing but Docker
# (and curl) is required on the host - all commands run inside containers.
#
# Usage:
#   scripts/run_local.sh up       build if stale, start the server, print banner (default)
#   scripts/run_local.sh build    build the image only
#   scripts/run_local.sh logs     tail the app logs
#   scripts/run_local.sh ps       container status
#   scripts/run_local.sh shell    bash inside the running app container
#   scripts/run_local.sh stop     stop the app (containers stay)
#   scripts/run_local.sh restart  restart the app container
#   scripts/run_local.sh down     stop and remove containers
#
# Configuration (environment or .env in the repo root):
#   LEAN4GAME_PORT            host port (default 3000)
#   LEAN4GAME_NODE_ENV        development|production (default development)
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
. "$LIB_DIR/repo_root.sh"
. "$LIB_DIR/docker_compose.sh"

cd "$(repo_root)"

PORT="${LEAN4GAME_PORT:-3000}"

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;s/^#$//'
    echo
    echo "Environment: LEAN4GAME_PORT (${PORT}), LEAN4GAME_NODE_ENV (default development)"
}

banner() {
cat <<EOF

===============================================================
  lean4game is up

  URL:              http://localhost:${PORT}
  Landing page:     lists the bundled TestGame (dev mode)
  Play TestGame:    http://localhost:${PORT}/#/g/local/TestGame

  Tail logs:        scripts/run_local.sh logs
  Open a shell:     scripts/run_local.sh shell
  Stop containers:  scripts/run_local.sh down
===============================================================

EOF
}

wait_for_relay() {
    echo "Waiting for the relay to become healthy..."
    for _ in $(seq 1 120); do
        if curl -fsS "http://localhost:${PORT}/api/games" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "The relay did not become healthy within 120s - check: scripts/run_local.sh logs" >&2
    return 1
}

action="${1:-up}"
case "$action" in
    up)
        echo "Building image (cached layers make this fast when nothing changed)..."
        docker_compose build
        docker_compose up -d app
        wait_for_relay
        banner
        ;;
    build)
        docker_compose build
        ;;
    logs)
        shift
        docker_compose logs -f app "$@"
        ;;
    ps)
        shift
        docker_compose ps "$@"
        ;;
    shell)
        docker_compose exec app bash
        ;;
    stop)
        docker_compose stop app
        ;;
    restart)
        docker_compose restart app
        ;;
    down)
        docker_compose down
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown action: $action (try: scripts/run_local.sh help)" >&2
        exit 1
        ;;
esac