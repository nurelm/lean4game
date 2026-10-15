# docker_compose.sh - single entry point for docker compose in this repo.
# Sources repo_root.sh for the fallback, then exposes docker_compose() so every
# script and subcommand uses the same project name and compose file no matter
# where the caller's working directory is.
#
# Usage:
#   . this/script
#   docker_compose up -d app

COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

docker_compose() {
    docker compose \
        --project-name lean4game \
        --project-directory "$COMPOSE_DIR" \
        --file "$COMPOSE_DIR/docker-compose.yml" \
        "$@"
}