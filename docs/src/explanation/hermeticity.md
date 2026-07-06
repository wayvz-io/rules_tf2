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
`versions.json`, and every artifact they resolve to is checksum-verified on
download (see [Download integrity](#download-integrity) below), so the hermetic
graph is byte-for-byte reproducible.

## Download integrity

Pinning a *version* is not the same as pinning the *bytes*: a moved tag or a
tampered mirror can serve different content for the same version string. So
every artifact rules_tf2 fetches is verified against a sha256, and the resolved
checksums are cached in `MODULE.bazel.lock` facts (Bazel 8.5+) so later builds
reuse them instead of re-resolving.

How the sha256 is obtained depends on what the publisher offers:

- **Providers** — `terraform providers lock` generates the `h1:`/`zh:` hashes
  for every platform; downloads are verified against the `zh:` (sha256) entries.
- **Tools** (Terraform, Sentinel, TFLint + plugins, terraform-docs, OPA) — the
  publisher's checksums file is fetched and every platform's hash is locked from
  it: HashiCorp `*_SHA256SUMS`, GitHub-release `checksums.txt`, terraform-docs'
  `*.sha256sum`, or OPA's per-asset `*.sha256`. This verifies against the
  *publisher*, and locking all platforms at once keeps the lockfile portable.
- **External modules** — registries and Git hosts publish no checksums file, so
  the sha256 is recorded on first download (trust-on-first-use) and enforced
  thereafter. Git modules on GitHub are fetched as a checksum-verified
  `archive/<ref>.tar.gz` tarball rather than an unverifiable `git clone`. If a
  tag is later moved, the next fetch fails the checksum instead of silently
  changing the build.

Because the checksums live in the lockfile's `facts`, the module extensions that
resolve them are marked `reproducible`, which also makes their repositories
eligible for Bazel's repository-contents cache.

> `MODULE.bazel.lock` is committed, so these facts are a single reviewed pin
> shared across the team and CI: a fresh checkout reuses the resolved checksums
> instead of re-resolving them, and any change to a pinned hash shows up in code
> review.

## The non-hermetic side (`bazel run`)

Anything that must reach a real backend, real state, or the network is a
`bazel run` target, deliberately kept **out** of the hermetic test graph:

- `tf_runner` — run arbitrary Terraform commands against a real backend
- `tfc_workspace` — `:name_tfc_plan` / `:name_tfc_apply` execute remote
  runs on HCP Terraform / Terraform Enterprise
- `tfc_publish_registry` / `tf_publish_oci_flux` — push the packaged module to a
  registry (network)

This split is the answer to "when do you break hermeticity?": you break it on
purpose, at `bazel run`, for the operations that inherently can't be hermetic
(a plan needs real state; an apply changes real infrastructure).

## Toolchains & execution environments

Hermeticity is only as good as the toolchains that build the graph. rules_tf2
builds entirely from **stock, downloaded toolchains** — no host compiler, JDK,
Go, or nix is required. A plain machine with Bazel is enough:

- **C/C++:** a hermetic downloaded LLVM CC toolchain (`toolchains_llvm`) with a
  pinned sysroot, so the build never touches the host's system compiler.
- **Java:** the default remote JDK from `rules_java` — no host Java needed.
- **Go:** the Go SDK is fetched hermetically via `rules_go`
  (`go_sdk.download(...)`), not from the host `PATH`. This builds the ruleset's
  own Go pieces (e.g. the `tf2` TFLint ruleset).
- **mdbook** (docs generation): a downloaded release binary (`@mdbook`).
- **Terraform / TFLint / terraform-docs:** downloaded hermetically by the
  ruleset's own module extensions. Consuming projects get them the same way.

> A `flake.nix` dev-shell is available for contributors who prefer to work
> inside nix (it provides `terraform`, `tflint`, `terraform-docs`, and a pinned
> Bazel), but it is a convenience only — nothing in the build depends on nix,
> and CI runs on a bare `ubuntu-latest` runner using exactly these stock
> toolchains.

### What this means for remote execution (RBE)

The hermetic tests are cacheable and remote-executable. Because the CC, Java,
Go, and mdbook toolchains are ordinary Bazel external repositories, Bazel ships
them to workers as part of the action inputs — so any generic RBE worker can run
the actions with **no special preparation**: no host toolchains, and no
`/nix/store` closure to sync. The local Buildbarn smoke test in
`tools/rbe-local` runs on a vanilla container for exactly this reason.

## Mapping onto CI and CD

A common pipeline shape — and the one rules_tf2 is designed around:

### CI (hermetic gate + non-hermetic plan)

1. **Hermetic gate:** `bazel test //...` runs fmt, lint, validate, docs,
   version, native-test, and **policy** checks with no network and no cloud.
   This is fast, cacheable, and remote-executable.
2. **Package:** the same run produces the module bundle (sources + nested
   modules + docs). `tfc_publish_registry` / `tf_publish_oci_flux` package exactly
   the Bazel-exposed files — no stray files, no build artifacts. (The
   generated lockfile is deliberately *not* bundled — see the
   `*_no_lockfile_test`.)
3. **Non-hermetic plan (optional):** hand the packaged module to a
   plan/policy platform. `tfc_workspace`'s `:name_tfc_plan` drives a
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
   `tfc_workspace`'s `:name_tfc_apply` (remote on HCP/TFE), or your own
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
- [`tfc_workspace`](../reference/cloud/tfc-workspace.md) — remote plan/apply
- [`tfc_agent_image`](../reference/cloud/tfc-agent-image.md) — provider-hermetic agents
- [Flux publishing](../reference/flux/README.md) — module OCI artifacts for GitOps
- [Sentinel](sentinel.md) / [OPA](opa.md) — hermetic policy tests
