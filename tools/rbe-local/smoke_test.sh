#!/usr/bin/env bash
# Basic RBE smoke test against the local podman Buildbarn cluster.
#
# Prereq: in another terminal, start the cluster:  ./run.sh up
#         (if the runner stays in "Created" under podman-compose, start it:
#          podman start rbe-local_runner-hardlinking-ubuntu22-04_1)
# Then:                                            ./smoke_test.sh
#
# Builds a trivial genrule remotely via --config=rbe_local and asserts the action
# was executed remotely (Bazel reports "N remote"). This proves the RBE plumbing -
# scheduler, CAS, worker dispatch - works end to end.
set -euo pipefail

cd "$(dirname "$0")/../.."   # repo root

echo ">> checking Buildbarn frontend on localhost:8980"
if ! (exec 3<>/dev/tcp/localhost/8980) 2>/dev/null; then
    echo "error: nothing listening on localhost:8980. Start the cluster first:" >&2
    echo "       tools/rbe-local/run.sh up" >&2
    exit 1
fi

echo ">> building //tools/rbe-local:remote_smoke with --config=rbe_local"
out=$(nix develop . --command bazel build --config=rbe_local //tools/rbe-local:remote_smoke 2>&1)
echo "$out" | tail -5

if echo "$out" | grep -qE '[0-9]+ remote'; then
    echo "PASS: action executed remotely via Buildbarn"
else
    echo "FAIL: build did not report a remote action - check the cluster and worker logs" >&2
    exit 1
fi
