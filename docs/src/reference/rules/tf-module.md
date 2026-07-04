# tf_module

Main macro for creating Terraform modules with comprehensive testing.

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_module")

tf_module(
    name = "my_module",
    srcs = [
        "main.tf",
        "variables.tf",
        "outputs.tf",
        "terraform.tf",
        "README.md",
    ],
    providers = ["@tf_provider_registry//:aws_6"],
)
```

> **Note**: Always list `srcs` explicitly - never use `glob()`. This keeps the
> source set auditable and is enforced by the generated `*_untracked_files_test`.

## Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | yes | Target name for the module |
| `srcs` | label_list | yes | Source files (`.tf` files and `README.md`), listed explicitly |
| `providers` | label_list | yes* | Provider mirror targets like `@tf_provider_registry//:aws_6` (*required unless `modules` provide them) |
| `deps` | label_list | no | Dependencies on other `tf_module` targets |
| `modules` | label_list | no | Nested modules for complex deployments (local or `@tf_module_registry//:...`) |
| `tflint_config` | label | no | TFLint configuration file |
| `tfdoc_config` | label | no | terraform-docs configuration file |
| `skip_validation` | bool | no | Skip the `terraform validate` test (for template modules). Default `False` |
| `terraform_version` | string | no | Terraform version constraint (defaults to `1.13.2`) |
| `testonly` | bool | no | Whether this is a test-only module. Default `False` |
| `tags` | string_list | no | Tags to apply to the generated test targets |

## Generated Targets

Each `tf_module` automatically creates these targets:

| Target | Description |
|--------|-------------|
| `*_validate_test` | Runs `terraform validate` (unless `skip_validation`) |
| `*_format_test` | Checks `terraform fmt` compliance |
| `*_format` | Auto-fixes formatting (`bazel run`) |
| `*_lint_test` | Runs TFLint |
| `*_tflint_fix` | Auto-fixes TFLint issues (`bazel run`) |
| `*_tflint_validate_test` | Validates against TFLint with providers |
| `*_doc_test` | Checks README matches terraform-docs (if `README.md` present) |
| `*_generate_docs` | Regenerates README (`bazel run`) |
| `*_versions_check_test` | Validates provider version constraints |
| `*_generate_versions` | Regenerates `terraform.tf` versions (`bazel run`) |
| `*_deps_test` | Validates module dependencies are declared |
| `*_reorganize` | Reorganizes files into conventional structure (`bazel run`, not a test) |
| `*_untracked_files_test` | Checks all `.tf` files are listed in `srcs` |
| `*_no_lockfile_test` | Checks no committed `.terraform.lock.hcl` |

Run all tests in a package:
```bash
bazel test //path/to:all
```

See [Rules Overview](README.md) for more information.
