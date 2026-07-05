# rules_tf2

Bazel rules for managing Terraform infrastructure. `rules_tf2` manages Terraform modules through Bazel, with integrated testing, provider/tool management, external module support, policy testing, and Terraform Cloud/Enterprise integration.

## Background

I built rules_tf2 to simplify and speed up creating large volumes of Terraform
modules across consulting engagements. I'm not currently working in that space,
so the project is **parked**. It's open source because a few people asked how to
run Terraform in a monorepo — this is how I did it.

I may come back to improve it, but for now treat it as **unmaintained** and free
to fork.

> [!NOTE]
> The documentation was a best-effort brain-dump — mostly voice-to-text context
> captured with Claude — so it's uneven in places and not perfect. It's enough
> to get the shape of how things work, not a polished manual.

## Documentation

**📖 [wayvz-io.github.io/rules_tf2](https://wayvz-io.github.io/rules_tf2/)** — start here.

The site is the source of truth for how to use rules_tf2: a getting-started
walkthrough, how-to guides, the full rule/macro reference, and explanations of
the architecture, hermeticity model, and versioning. It follows the
[Diataxis](https://diataxis.fr/) framework.

## Features

- Terraform module management through Bazel (`tf_module`)
- Provider and tool management with automatic downloading, hashing, and caching
- Comprehensive per-module tests (format, lint, validate, docs, versions)
- Run arbitrary terraform commands through Bazel (`tf_runner`)
- Policy testing — OPA (`tf_opa_test`) and Sentinel (`tf_sentinel_test`)
- Terraform Cloud / Enterprise — remote plan/apply, private-registry publish, provider-baked agent images (`tfc_workspace`, `tfc_publish_registry`, `tfc_agent_image`)
- Flux GitOps — publish modules as OCI artifacts (`tf_publish_oci_flux`)

## Status

- **Alpha** — core functionality works; APIs may change.
- **Policy testing** — OPA and Sentinel format/test rules are implemented and tested.
- **Publishing** — OCI and Terraform-registry publishing are implemented but rougher than the rest.

## Roadmap

If I come back to this, the things I'd want to tackle:

- [ ] Publish OCI artifacts via `rules_oci` instead of the current `gh`-based path
- [ ] Move auto-updates to Renovate
- [ ] Review the docs for consistency
- [ ] Add a reference pattern for integrating rules_tf2 with Flux + OpenTofu (GitOps)

## Project structure

```
tf2/
├── agent/             # TFC agent image building
├── gazelle/           # Terraform Gazelle extension (dev tool)
├── internal/          # Internal utilities
├── macros/            # Public API macros (tf_module)
├── modules/           # External module registry management
├── opa/               # OPA policy testing
├── providers/         # Provider management
├── publish/           # OCI / registry publishing
├── sentinel/          # Sentinel policy testing
├── tfcloud/           # Terraform Cloud integration
├── tfcore/            # Core Terraform functionality
├── tfdocs/            # terraform-docs integration
├── tflint/            # tflint integration
├── tools/             # Tool management
└── def.bzl            # Public API exports
```

## Examples

Working, tested configurations live in [`examples/`](examples/) — from a basic
module to nested dependency graphs and policy testing. Run any example's full
suite with `bazel test //examples/<name>:all`.

## Development

Builds run under Bazel 9 (pinned in `.bazelversion`) on stock, downloaded
toolchains — no host compiler, JDK, Go, or nix required. A `.envrc` (direnv)
runs `bazel` inside the `rules_tf2-dev` container (see `tools/dev/bazel` and the
[Hermeticity & toolchains](https://wayvz-io.github.io/rules_tf2/explanation/hermeticity.html)
docs); an optional `flake.nix` dev-shell is available for contributors who use
nix. Run the whole check suite with:

```bash
bazel test //...
```

## Contributing

Issues and pull requests aren't actively monitored and may not get a response.
Fork it and build on it under the terms of the licence — see [Background](#background).

## License

Licensed under the [MIT License](LICENSE).
