# tf_module

Main macro for creating Terraform modules with comprehensive testing.

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_module")

tf_module(
    name = "my_module",
    srcs = glob(["*.tf"]) + ["README.md"],
    providers = ["@tf_provider_registry//:aws_5"],
)
```

## Generated Targets

Each `tf_module` automatically creates these targets:

| Target | Description |
|--------|-------------|
| `*_validate_test` | Runs `terraform validate` |
| `*_format_test` | Checks `terraform fmt` compliance |
| `*_format` | Auto-fixes formatting |
| `*_lint_test` | Runs TFLint |
| `*_tflint_fix` | Auto-fixes TFLint issues |
| `*_tflint_validate_test` | Validates TFLint config |
| `*_doc_test` | Checks README matches terraform-docs |
| `*_generate_docs` | Regenerates README |
| `*_versions_check_test` | Validates provider version constraints |
| `*_deps_test` | Validates module dependencies are declared |
| `*_organization_check_test` | Checks file organization conventions |
| `*_untracked_files_test` | Checks all .tf files are in srcs |
| `*_no_lockfile_test` | Checks no committed .terraform.lock.hcl |

Run all tests:
```bash
bazel test //path/to:my_module_all
```

See [Rules Overview](README.md) for more information.
