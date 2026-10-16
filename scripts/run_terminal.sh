#!/bin/bash

# Run a shell or a single command inside the app container.
#
# Behavior mirrors scripts/run_terminal.sh of the polymath-backend projects:
#   - if the app container is running, exec into it
#   - otherwise, start an ephemeral container from the app image (nothing is
#     left running: `run --rm --no-deps` removes it when the command exits)
#
# Usage:
#   scripts/run_terminal.sh                    # interactive bash shell
#   scripts/run_terminal.sh <command...>       # bash -c "<command>" inside the container
#
# The image is built on demand if it does not exist yet (see docker-compose.yml;
# the app service image is lean4game-local).

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
. "$LIB_DIR/repo_root.sh"
. "$LIB_DIR/docker_compose.sh"

cd "$(repo_root)"

SERVICE=app

# docker compose run/exec allocate a TTY by default, which fails when stdin
# isn't a terminal (non-interactive callers). Only request a TTY when stdin
# actually is one.
TTY_FLAG=""
if ! [ -t 0 ]; then
    TTY_FLAG="-T"
fi

if [ -n "$(docker_compose ps -q "$SERVICE")" ]; then
    # App container is running: exec into it.
    if [ $# -eq 0 ]; then
        docker_compose exec $TTY_FLAG "$SERVICE" bash
    else
        docker_compose exec $TTY_FLAG "$SERVICE" bash -c "$*"
    fi
else
    # No app container running: ephemeral container from the app image.
    if [ $# -eq 0 ]; then
        docker_compose run --rm --no-deps --entrypoint=/bin/bash "$SERVICE"
    else
        docker_compose run --rm --no-deps --entrypoint= "$SERVICE" bash -c "$*"
    fi
fi