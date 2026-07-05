#!/usr/bin/env bash
# Bring up (or tear down) a local Buildbarn cluster with podman for RBE.
#
#   ./run.sh up      # create volume dirs and start the cluster (foreground)
#   ./run.sh up -d   # ... detached (used by CI)
#   ./run.sh down    # stop and remove the cluster
#
# Requires: podman + podman-compose (or docker + docker compose).
set -eu

cd "$(dirname "$0")"

worker="worker-hardlinking-ubuntu22-04"

# Prefer podman-compose; fall back to `docker compose`.
if command -v podman-compose >/dev/null 2>&1; then
    COMPOSE="podman-compose"
elif command -v docker >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    echo "error: need podman-compose or docker compose" >&2
    exit 1
fi

setup_volumes() {
    rm -rf "volumes/bb" "volumes/${worker}"
    mkdir -p "volumes/${worker}"/{build,cache,cas/persistent_state}
    chmod -R 0777 "volumes/${worker}"
    mkdir -p volumes/storage-{ac,cas,fsac}-{0,1}/persistent_state
    chmod -R 0777 volumes/storage-{ac,cas,fsac}-{0,1}
}

case "${1:-up}" in
    up)
        setup_volumes
        if [ "${2:-}" = "-d" ]; then
            exec ${COMPOSE} up -d
        else
            exec ${COMPOSE} up
        fi
        ;;
    down)
        ${COMPOSE} down || true
        ;;
    *)
        echo "usage: $0 [up|down]" >&2
        exit 1
        ;;
esac
