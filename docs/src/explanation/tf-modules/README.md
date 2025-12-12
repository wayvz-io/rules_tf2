# About Terraform Modules

The `tf_module` macro is the primary way to declare Terraform modules in Bazel. A single declaration generates multiple targets for linting, testing, documentation, and publishing.

```starlark
tf_module(
    name = "vpc",
    srcs = [
        "main.tf",
        "outputs.tf",
        "README.md",
        "terraform.tf",
        "variables.tf",
    ],
    providers = ["@tf_provider_registry//:aws_5"],
)
```

This creates:
- `vpc` - The module itself
- `vpc_lint_test` - TFLint static analysis
- `vpc_validate_test` - terraform validate
- `vpc_format_test` - terraform fmt check
- `vpc_doc_test` - README documentation check
- `vpc_generate_docs` - Regenerate README
- And more...

## Workflow

Modules flow through a pipeline:

1. **Structure** - Define module sources and dependencies
2. **Linting** - Static analysis catches issues early
3. **Testing** - Validation and Terraform tests verify correctness
4. **Documentation** - Generated docs stay in sync with code
5. **Publishing** - Ship to registries when ready

Each stage has dedicated targets. Run individually during development, or run all tests with `bazel test //path/to:all`.

## Generated Targets

| Target | Purpose |
|--------|---------|
| `*_validate_test` | terraform validate |
| `*_format_test` | terraform fmt check |
| `*_format` | Auto-fix formatting |
| `*_lint_test` | TFLint analysis |
| `*_tflint_fix` | Auto-fix lint issues |
| `*_doc_test` | README matches generated |
| `*_generate_docs` | Regenerate README |

See individual pages for details on each stage.
