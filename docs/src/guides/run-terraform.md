# Run Terraform through Bazel

Run `terraform init` / `plan` / `apply` (or any subcommand) against a module,
using the Bazel-pinned Terraform binary.

> This is a **non-hermetic** `bazel run` target — it talks to a real backend and
> real state, deliberately kept out of the hermetic test suite.

## Prerequisites

- A working `tf_module` — see [Create and test a module](create-and-test-a-module.md).

## Steps

1. Declare a `tf_runner`, pointing `stack` at the module:

   ```starlark
   load("@rules_tf2//tf2:def.bzl", "tf_runner")

   tf_runner(
       name = "runner",
       stack = ":my_module",
   )
   ```

   `stack` is required. For a real backend, set `backend_type` (`local`,
   `remote`, or `cloud`) with `backend_organization` / `backend_workspace`;
   optionally pass a `tf_variables` target via `variables`. See
   [`tf_runner`](../reference/rules/tf-runner.md) for all attributes.

2. Run any subcommand after `--`:

   ```bash
   bazel run //path/to:runner -- init
   bazel run //path/to:runner -- plan
   bazel run //path/to:runner -- apply
   bazel run //path/to:runner -- state list
   ```

   `plan`, `apply`, and `validate` run `terraform init` automatically first;
   other subcommands are passed straight through.

## Verification

`bazel run //path/to:runner -- plan` produces a plan against your backend. The
runner sets automation env vars (`TF_IN_AUTOMATION`, `TF_INPUT=false`) so it
won't block on prompts.

## See also

- [`tf_runner` reference](../reference/rules/tf-runner.md)
- [Run against Terraform Cloud](terraform-cloud.md) — `tfc_workspace` wraps `tf_runner` for TFC/TFE
- [Hermeticity, CI & CD](../explanation/hermeticity.md) — why this is a `bazel run`, not a test
