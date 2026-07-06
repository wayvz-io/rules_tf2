# rules_tf2

Terraform rules for Bazel — hermetic, reproducible infrastructure builds.

rules_tf2 is a Bazel module that wraps your Terraform modules as Bazel targets.
You keep writing plain Terraform; rules_tf2 pins the toolchain and providers,
generates a full test/lint/docs suite for every module, and packages modules for
publishing — all hermetically and offline.

## What rules_tf2 adds on top of Terraform

rules_tf2 does **not** replace the Terraform CLI or change how you write HCL. It
drives the real `terraform` binary under Bazel and draws a clear line between the
reproducible checks it owns and the stateful operations Terraform still owns:

| Terraform still does | rules_tf2 adds |
|----------------------|----------------|
| You author `main.tf`, `variables.tf`, resources, providers | Wraps each module as a Bazel target (`tf_module`) |
| `terraform plan` / `apply` against real state and a backend | Pins Terraform, TFLint, terraform-docs and all providers to exact versions |
| Provider logic and resource behaviour | An offline **provider mirror** — no `terraform init` reaching the internet |
| Native `.tftest.hcl` tests | Auto-generates fmt, lint, validate, version, and docs tests for every module |
| — | Packages modules (sources + nested modules + docs) for registry/OCI publishing |

The dividing line is simple: **`bazel test` / `bazel build` is hermetic**
(offline, no state, no cloud); **`bazel run` is where you deliberately reach a
real backend** — plan, apply, publish. See
[Hermeticity, CI & CD](explanation/hermeticity.md) for the full model.

## How it works

### Providers and tools are declared once, then pinned

You list every provider and tool version in a single `versions.json`:

```json
{
  "providers": {
    "hashicorp/aws": ["6.26.0"],
    "hashicorp/random": ["3.7.2"]
  },
  "tools": {
    "terraform": "1.14.2",
    "tflint": "0.60.0",
    "terraform-docs": "0.20.0"
  }
}
```

A Bazel [module extension](reference/extensions/) reads this file,
downloads each provider and tool, and generates provider hashes into
`MODULE.bazel.lock` — so the whole graph is byte-for-byte reproducible and no
build ever pulls a provider from the network. Providers are aliased by major
version (`aws_6`, `random_3`) and referenced as `@tf_provider_registry//:aws_6`.
See [Provider versioning](explanation/versioning/providers.md).

### You write HCL; rules_tf2 keeps the boilerplate in sync

You author the module's real content; a few files are **generated** and kept in
sync by run targets, with a matching test that fails if they drift:

| You write | Generated / checked |
|-----------|---------------------|
| `main.tf`, `variables.tf`, `outputs.tf` | — |
| `terraform.tf` (`required_providers` block) | `bazel run :name_generate_versions` regenerates it; `*_versions_check_test` enforces it |
| `README.md` (prose) | `bazel run :name_generate_docs` regenerates the inputs/outputs tables via terraform-docs; `*_doc_test` enforces it |
| — | Provider hashes in `MODULE.bazel.lock`, generated automatically during `bazel build` |

### Every module gets a hermetic test suite

A single `tf_module` auto-generates a suite of tests — this is where formatting,
linting, and validation come in. All of them run **offline** against the pinned
toolchain and the provider mirror:

| Generated test | Checks |
|----------------|--------|
| `*_format_test` | `terraform fmt` — code is formatted |
| `*_lint_test` | TFLint, including the built-in `tf2` ruleset |
| `*_tflint_validate_test` | TFLint's own config is valid |
| `*_validate_test` | `terraform validate` against the offline mirror |
| `*_versions_check_test` | `terraform.tf` matches the declared providers |
| `*_doc_test` | `README.md` tables are up to date |
| `*_deps_test` | Declared module dependencies resolve |
| `*_untracked_files_test` | No stray files in the module |
| `*_no_lockfile_test` | No committed `terraform.lock.hcl` (lockfile is Bazel-managed) |

See [Linting](explanation/tf-modules/linting.md) and
[Testing](explanation/tf-modules/testing.md) for details.

## Quick Start

### 1. Depend on rules_tf2

rules_tf2 is not on the Bazel Central Registry, so add it with a `git_override`
in your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_tf2", version = "0.1.0")

git_override(
    module_name = "rules_tf2",
    remote = "https://github.com/wayvz-io/rules_tf2.git",
    tag = "v0.1.0",
)
```

### 2. Configure providers and tools

Point the module extensions at your `versions.json` (see above):

```starlark
tf_providers = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_providers")
tf_providers.download(versions_file = "//:versions.json")
use_repo(tf_providers, "tf_provider_registry")

tf_tools = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_tools")
tf_tools.from_versions_json(versions_file = "//:versions.json")
use_repo(tf_tools, "tf_tool_registry", "tflint_plugin_registry")
```

### 3. Declare a module

In your module's `BUILD.bazel`, list every source file explicitly — never use
`glob()`:

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_module")

tf_module(
    name = "my_module",
    srcs = [
        "main.tf",
        "outputs.tf",
        "terraform.tf",
        "variables.tf",
        "README.md",
    ],
    providers = ["@tf_provider_registry//:aws_6"],
)
```

### 4. Run the checks

```bash
bazel test //path/to:all      # fmt, lint, validate, versions, docs — all offline
```

If a `*_versions_check_test` or `*_doc_test` fails, regenerate the boilerplate
and re-run:

```bash
bazel run //path/to:my_module_generate_versions
bazel run //path/to:my_module_generate_docs
```

Plans, applies, and publishing are deliberately **not** in the test suite — they
run as `bazel run` targets against a real backend. See
[`tf_runner`](reference/rules/tf-runner.md),
[`tfc_workspace`](reference/cloud/tfc-workspace.md), and
[Flux publishing](reference/flux/).

## Learn from the examples

The [`examples/`](https://github.com/wayvz-io/rules_tf2/tree/main/examples)
directory contains working, tested configurations you can copy and run:

| Example | What it shows |
|---------|---------------|
| `basic_module/` | A minimal `tf_module` with providers and the auto-generated test suite |
| `module_with_dependencies/` | Composing modules, provider inheritance, and outputs |
| `parent_module/` / `child_with_nested_dep/` | Nested module dependency graphs |
| `opa_policy/` | Policy testing with `tf_opa_test` |
| `sentinel_policy/` | Policy testing with `tf_sentinel_test` |

Run an example's full test suite with:

```bash
bazel test //examples/basic_module:all
```

## Documentation structure

This documentation follows the [Diataxis](https://diataxis.fr/) framework:

- **[How-to Guides](guides/)**: Task-oriented instructions for specific goals
- **[Reference](reference/rules/)**: Technical descriptions of rules, macros, and APIs
- **[Explanation](explanation/architecture.md)**: Understanding-oriented discussions of concepts

## Status

**Alpha** — Core functionality works but APIs may change.
