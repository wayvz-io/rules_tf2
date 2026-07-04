# Hermeticity, CI & CD

rules_tf2 draws a deliberate line between what is **hermetic** (reproducible,
offline, no state, no cloud) and what is **not** (real plans, applies, and
publishing that touch a backend or the network). Understanding where that line
sits is the key to fitting rules_tf2 into a CI/CD pipeline.

The short version:

> **`bazel test` / `bazel build` is hermetic. `bazel run` is where you
> deliberately break hermeticity** — plan, apply, and publish.

## The hermetic side (`bazel test` / `bazel build`)

Everything in the generated test suite runs offline against a Bazel-managed
Terraform toolchain and a **filesystem provider mirror**. There is no network
access, no remote state, and no cloud backend involved. `terraform init` runs
with `-backend=false` against a filesystem mirror wired in through a generated
`.terraformrc` (`provider_installation { filesystem_mirror { … } }`, exported
via `TF_CLI_CONFIG_FILE`), so results are reproducible on any machine (and
cacheable/remote-executable).

Hermetic operations:

- Formatting (`terraform fmt -check`)
- Linting (TFLint, including the built-in `tf2` ruleset)
- Validation (`terraform validate` against the offline mirror)
- Documentation checks (terraform-docs)
- Version/lockfile consistency checks
- Native Terraform tests (`tf_test`)
- **Policy-as-code tests** — Sentinel (`tf_sentinel_test`) and OPA
  (`tf_opa_test`) run against the config as hermetic Bazel tests
- Building the **packaged artifact** that publishing rules push (the module
  sources, nested modules, and docs)

Provider, tool, and (optionally) external-module versions are pinned in
`versions.json` and locked in `MODULE.bazel.lock`, so the hermetic graph is
byte-for-byte reproducible.

## The non-hermetic side (`bazel run`)

Anything that must reach a real backend, real state, or the network is a
`bazel run` target, deliberately kept **out** of the hermetic test graph:

- `tf_runner` — run arbitrary Terraform commands against a real backend
- `tf_cloud_workspace` — `:name_tfc_plan` / `:name_tfc_apply` execute remote
  runs on HCP Terraform / Terraform Enterprise
- `tf_publish_registry` / `tf_publish_oci` — push the packaged module to a
  registry (network)

This split is the answer to "when do you break hermeticity?": you break it on
purpose, at `bazel run`, for the operations that inherently can't be hermetic
(a plan needs real state; an apply changes real infrastructure).

## Toolchains & execution environments

Hermeticity is only as good as the toolchains that build the graph. rules_tf2
supports two toolchain paths, and the choice affects nothing about *what*
`bazel test` checks — only *where the build tools come from* and, for remote
execution, *what a worker must have installed*.

### Default path: stock, hermetic toolchains (no nix)

Out of the box, the build uses toolchains Bazel downloads for itself. No host
compiler, JDK, or Go is required — a plain machine with Bazel is enough:

- **C/C++:** a hermetic downloaded CC toolchain (`toolchains_llvm`), so the
  build doesn't depend on the host's system compiler.
- **Java:** the default remote JDK from `rules_java` — no host Java needed.
- **Go:** the Go SDK is fetched hermetically via `rules_go`
  (`go_sdk.download(...)`), not taken from the host `PATH`. This is what builds
  the ruleset's own Go pieces (e.g. the `tf2` TFLint ruleset).
- **mdbook** (docs generation): a downloaded release binary. Note the download
  is a glibc `linux x86_64` build, so it won't run on a NixOS host — NixOS
  contributors build the book with the `mdbook` from the `flake.nix` dev-shell
  instead.
- **Terraform / TFLint / terraform-docs:** already downloaded hermetically by
  the ruleset's own module extensions. This was **always** the case — these
  tools have never come from nix, and consuming projects get them the same way
  regardless of the toolchain path.

A committed `Dockerfile` (a system `gcc`/JDK on top of the pinned Bazel from
`.bazelversion`) is available if you want a reproducible local dev/CI parity
container, but it is an *option*, not a requirement. CI runs on a bare
`ubuntu-latest` runner using exactly these stock toolchains.

### Opt-in path: nix (`--config=nix`)

nix is fully supported but **optional**. Building with `--config=nix` swaps in
the nixpkgs host platform, a nix-provided Java runtime, and nix CC / Go /
mdbook toolchains instead of the downloaded ones. The `flake.nix` dev-shell
remains for contributors who prefer to work inside a nix environment. Choose
this path when you want your toolchains pinned by nixpkgs rather than by
Bazel's downloads; otherwise the default path needs no extra flags.

### What this means for remote execution (RBE)

The hermetic tests are cacheable and remote-executable, but remote execution
adds one requirement the local case hides: **a remote executor must have the
action's toolchain closure available.** How that closure gets to the worker
depends entirely on which path above you build with:

- **Stock toolchains (default):** the CC, Java, Go, and mdbook toolchains are
  ordinary Bazel external repositories, so Bazel ships them to workers as part
  of the action inputs. No special worker preparation is needed — any generic
  RBE worker can run the actions.
- **nix toolchains (`--config=nix`):** the toolchains live under `/nix/store`,
  which is *not* shipped as action inputs. Each worker must have the matching
  `/nix/store` closure synced ahead of time. This is exactly why the local
  Buildbarn smoke test in `tools/rbe-local` bind-mounts `/nix/store` into the
  worker.

This reconciles the earlier behaviour where "RBE needs the nix store" seemed
inherent: it was never inherent to rules_tf2. Remote execution needed the nix
store *only because the build was using nix toolchains*. On the default stock
path, RBE needs no nix store at all.

## Mapping onto CI and CD

A common pipeline shape — and the one rules_tf2 is designed around:

### CI (hermetic gate + non-hermetic plan)

1. **Hermetic gate:** `bazel test //...` runs fmt, lint, validate, docs,
   version, native-test, and **policy** checks with no network and no cloud.
   This is fast, cacheable, and remote-executable.
2. **Package:** the same run produces the module bundle (sources + nested
   modules + docs). `tf_publish_registry` / `tf_publish_oci` package exactly
   the Bazel-exposed files — no stray files, no build artifacts. (The
   generated lockfile is deliberately *not* bundled — see the
   `*_no_lockfile_test`.)
3. **Non-hermetic plan (optional):** hand the packaged module to a
   plan/policy platform. `tf_cloud_workspace`'s `:name_tfc_plan` drives a
   remote plan on HCP Terraform / TFE via the TFE API; a TACOS platform that
   exposes the TFE-compatible API (e.g. Scalr, Terrakube) is the same shape,
   though rules_tf2 only exercises HCP/TFE directly.

> **Two layers of policy.** rules_tf2 runs Sentinel/OPA as *hermetic tests
> against the configuration* (pre-plan, in `bazel test`). A TACOS platform
> runs policy *against the generated plan* (post-plan). They are
> complementary: the hermetic tests catch problems before you ever reach the
> backend; the platform enforces on the real plan.

### CD (publish artifact → apply)

1. **Publish the hermetic artifact:** `bazel run //…:publish` (registry) or
   `//…:push_oci` (OCI). The OCI path carries Flux-compatible annotations
   (`org.opencontainers.image.source`/`revision`), so a GitOps controller can
   watch for new versions.
2. **Apply centrally:** applies run where your state and credentials live —
   `tf_cloud_workspace`'s `:name_tfc_apply` (remote on HCP/TFE), or your own
   system subscribing to new artifact versions and triggering the apply.

rules_tf2's job ends at producing a **hermetic, versioned, policy-checked
artifact**. Wiring that artifact to your specific CD trigger (an S3 drop, a
Flux `OCIRepository`, a webhook) is your pipeline's glue — rules_tf2 gives you
a reproducible thing to ship, not the delivery bus.

## Execution model: local vs centralized

| Where | What runs | Hermetic? |
|-------|-----------|-----------|
| Local / CI runner | `bazel test` — the whole check suite, against the offline mirror | Yes |
| Local / CI runner | `bazel run …:tfc_plan` — drives a remote plan, streams results | No (talks to the backend) |
| Centralized (HCP/TFE, TACOS) | plan/apply execution against real state | No |
| Centralized agent | `tfc_agent_image` builds a TFC agent with providers **pre-bundled**, so even the remote executor pulls no providers at run time | Provider-hermetic |

The pattern: **checks and packaging run hermetically and locally (or in CI);
plans and applies run centrally**, where the state and credentials are. The
`tfc_agent_image` rule lets you make the centralized executor provider-hermetic
too, by baking the filesystem mirror into the agent image.

## See Also

- [Architecture](architecture.md) — component layout
- [`tf_cloud_workspace`](../reference/cloud/tf-cloud-workspace.md) — remote plan/apply
- [`tfc_agent_image`](../reference/cloud/tfc-agent-image.md) — provider-hermetic agents
- [Publishing](../reference/publishing/README.md) — registry and OCI artifacts
- [Sentinel](sentinel.md) / [OPA](opa.md) — hermetic policy tests
