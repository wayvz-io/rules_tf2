# Local Buildbarn (RBE) cluster

A minimal [Buildbarn](https://github.com/buildbarn/bb-deployments) cluster you can
run locally with **podman** (or docker) to run Bazel Remote Build Execution against
`rules_tf2`. Adapted from the upstream
[`bb-deployments/docker-compose`](https://github.com/buildbarn/bb-deployments/tree/main/docker-compose)
example, trimmed to the non-privileged hardlinking worker (friendlier to rootless
podman than the FUSE worker).

The topology is a small set of pods the Bazel CLI connects to:

```
bazel (CLI)  ──grpc:8980──▶  frontend ──▶ storage-0/1 (CAS + action cache)
                                      └──▶ scheduler ──▶ worker ──▶ runner (Ubuntu)
```

## Why this exists

It lets you run — and CI validate — the **whole build remotely** on a **vanilla
Ubuntu worker**. The stock toolchains (LLVM CC, remote JDK, Go, mdbook) are all
downloaded and shipped to the worker as ordinary action inputs, so the runner needs
no special preparation: no `/nix/store`, no custom toolchain image. (Earlier the
ruleset resolved toolchains to `/nix/store` paths and this cluster had to bind-mount
the host store into the worker; dropping the Nix toolchains removed that entirely.)

Verified: `bazel build --config=rbe_local //go/tflint_ruleset:tflint-ruleset-tf2`
reports `181 remote` — the Go toolchain and the whole ruleset compile on the podman
worker with no `/nix/store`.

## Usage

```bash
# Terminal 1 — start the cluster (foreground)
tools/rbe-local/run.sh up

# Terminal 2 — run a build/test remotely
bazel test //... --config=rbe_local          # full suite on the worker
tools/rbe-local/smoke_test.sh                # or just the quick plumbing check

# When done
tools/rbe-local/run.sh down
```

`--config=rbe_local` points Bazel at `grpc://localhost:8980`, instance name
`hardlinking`, and the matching execution platform
`//tools/remote-toolchains:rbe_local_platform`. That platform's `exec_properties`
(`OSFamily`, `container-image`) must match the properties the worker advertises in
`config/worker-hardlinking-ubuntu22-04.jsonnet`, or the scheduler will not dispatch.

If the runner stays in `Created` under podman-compose (it has no `depends_on`):

```bash
podman start rbe-local_runner-hardlinking-ubuntu22-04_1
```

## Requirements

- `podman` + `podman-compose` (or `docker` + `docker compose`)
- The Bazel config `--config=rbe_local` (defined in `//.bazelrc`)

## Files

- `docker-compose.yml` — the cluster (frontend, 2× storage, scheduler, worker + runner)
- `config/` — Buildbarn jsonnet config, vendored from bb-deployments
- `run.sh` — create volumes and bring the cluster up/down
- `smoke_test.sh` — run a remote build and check it executed
- `BUILD.bazel` — the trivial `remote_smoke` genrule
