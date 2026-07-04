# Local Buildbarn (RBE) smoke test

A minimal [Buildbarn](https://github.com/buildbarn/bb-deployments) cluster you can
run locally with **podman** to smoke-test Bazel Remote Build Execution against
`rules_tf2`. Adapted from the upstream
[`bb-deployments/docker-compose`](https://github.com/buildbarn/bb-deployments/tree/main/docker-compose)
example, trimmed to the non-privileged hardlinking worker (friendlier to rootless
podman than the FUSE worker).

## Why this exists

`rules_tf2` was developed against an internal Buildbarn cluster whose workers were
built from the **same Nix images** as the dev shell. Action toolchains resolve to
`/nix/store` paths, so a worker must have those paths to execute builds. This local
cluster uses a **stock Ubuntu worker**, and the runner container **bind-mounts the
host `/nix/store` read-only** (see `docker-compose.yml`) — the local equivalent of
"sync the Nix images onto the RBE workers". That is what lets a Nix-toolchain action
actually run on a generic Ubuntu worker; without it the action fails with
`fork/exec /nix/store/...-bash: no such file or directory`. On a non-Nix host you
would instead bake the required store paths into the worker image.

Verified locally: `bazel build --config=rbe_local //tools/rbe-local:remote_smoke`
reports `1 remote` — the action is dispatched to and executed by the podman worker.

## Usage

```bash
# Terminal 1 - start the cluster (foreground)
tools/rbe-local/run.sh up

# Terminal 2 - run the smoke test
tools/rbe-local/smoke_test.sh

# When done
tools/rbe-local/run.sh down
```

`smoke_test.sh` builds `//tools/rbe-local:remote_smoke` (a trivial genrule) with
`--config=rbe_local`, which points Bazel at `grpc://localhost:8980`, instance name
`hardlinking`, and the matching execution platform
`//tools/remote-toolchains:rbe_local_platform`.

## Requirements

- `podman` + `podman-compose` (or `docker` + `docker compose`)
- The Bazel config `--config=rbe_local` (defined in `//.bazelrc`)

## Files

- `docker-compose.yml` — the cluster (frontend, 2× storage, scheduler, worker + runner)
- `config/` — Buildbarn jsonnet config, vendored from bb-deployments
- `run.sh` — create volumes and bring the cluster up/down
- `smoke_test.sh` — run a remote build and check it executed
- `BUILD.bazel` — the trivial `remote_smoke` genrule
