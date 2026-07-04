# Linting

Each `tf_module` generates linting targets:

- `*_lint_test` - TFLint static analysis
- `*_tflint_fix` - Auto-fix TFLint issues (where supported)
- `*_format_test` - terraform fmt check
- `*_format` - Auto-fix formatting

## TFLint Configuration

rules_tf2 automatically generates a `.tflint.hcl` file for each module by merging rule layers internally:

1. **Base rules** - Always applied
2. **Provider rules** - Added based on declared providers

### How Merging Works

Rules are merged, not replaced. Later layers overlay earlier ones—if a base rule enables `terraform_documented_variables` and a later layer disables it, the final config has it disabled.

This layering happens inside rules_tf2. You don't assemble it yourself; you either accept the auto-generated config or replace it entirely with your own `.tflint.hcl` (see [Custom Configuration](#custom-configuration)).

### Provider-Specific Rules

When you declare providers, rules_tf2 enables the corresponding TFLint plugin:

| Provider | Plugin |
|----------|--------|
| AWS | `tflint-ruleset-aws` |
| Azure | `tflint-ruleset-azurerm` |
| Google | `tflint-ruleset-google` |

Plugin versions come from your `versions.json`.

### Custom Configuration

The `tf_module` macro does not expose knobs for tweaking individual rules. If the auto-generated config isn't what you want, supply your own `.tflint.hcl` with the `tflint_config` attribute—it replaces the generated one for that module:

```starlark
tf_module(
    name = "my_module",
    srcs = ["main.tf", "variables.tf"],
    tflint_config = ".tflint.hcl",
)
```

The `tags` attribute on `tf_module` is forwarded to the generated Bazel test targets as ordinary target tags (for use with `bazel test --test_tag_filters`). It does **not** select or disable TFLint rules.

## The tf2 Plugin

rules_tf2 includes `tflint-ruleset-tf2` with enhanced rules. See [Reference: tflint-ruleset-tf2](../../reference/tflint/README.md) for available rules.

## Formatting

`*_format_test` checks `terraform fmt` compliance. `*_format` fixes issues in place:

```bash
bazel run //path/to:my_module_format
```
