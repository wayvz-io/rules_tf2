# Create and test a module

Declare a Terraform module as a Bazel target and get the full hermetic test
suite (format, lint, validate, versions, docs) for free.

## Prerequisites

- rules_tf2 wired into your `MODULE.bazel` with the `tf_providers` and `tf_tools`
  extensions — see [Add or update a provider](add-a-provider.md).

## Steps

1. Write your Terraform files as usual — `main.tf`, `variables.tf`,
   `outputs.tf`, `terraform.tf`, and a `README.md`.

2. Add a `tf_module` to the package's `BUILD.bazel`, listing every source file
   explicitly (never `glob()`):

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

   `srcs` is required. `providers` is required unless nested `modules` supply
   them. See [`tf_module`](../reference/rules/tf-module.md) for all attributes.

3. Run the generated test suite:

   ```bash
   bazel test //path/to:all
   ```

   A single `tf_module` generates: `*_format_test`, `*_lint_test`,
   `*_tflint_validate_test`, `*_validate_test`, `*_versions_check_test`,
   `*_doc_test`, `*_deps_test`, `*_untracked_files_test`, and
   `*_no_lockfile_test` — all run offline against the pinned toolchain and the
   provider mirror.

## Fixing failures

Two checks are backed by generators — if they fail, regenerate and re-run:

```bash
# terraform.tf's required_providers drifted from `providers`:
bazel run //path/to:my_module_generate_versions

# README's input/output tables are stale:
bazel run //path/to:my_module_generate_docs
```

If `*_format_test` fails, `bazel run //path/to:my_module_format`. If
`*_untracked_files_test` fails, add the missing `.tf` file to `srcs`.

## Verification

`bazel test //path/to:all` is green. The module is now consumable by other
`tf_module`s via `deps`/`modules`, by [`tf_runner`](run-terraform.md), and by the
[publish](publish-a-module.md) rules.

## See also

- [Write native Terraform tests](write-native-tests.md) — add `.tftest.hcl` tests
- [`tf_module` reference](../reference/rules/tf-module.md)
- [Module Structure](../explanation/tf-modules/structure.md) · [Linting](../explanation/tf-modules/linting.md)
