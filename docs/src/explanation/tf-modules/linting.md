# Linting

Each `tf_module` generates linting targets:

- `*_lint_test` - TFLint static analysis
- `*_tflint_fix` - Auto-fix TFLint issues (where supported)
- `*_format_test` - terraform fmt check
- `*_format` - Auto-fix formatting

## TFLint Configuration

rules_tf2 generates `.tflint.hcl` files by merging rule layers:

1. **Base rules** - Always applied
2. **Provider rules** - Added based on declared providers
3. **Tagged overrides** - Applied if module has matching tags
4. **Manual overrides** - Your explicit overrides win

### How Merging Works

Rules are merged, not replaced. If base rules enable `terraform_documented_variables` and a tagged override disables it, the final config has it disabled.

Override what you need—don't redefine everything.

### Provider-Specific Rules

When you declare providers, rules_tf2 enables the corresponding TFLint plugin:

| Provider | Plugin |
|----------|--------|
| AWS | `tflint-ruleset-aws` |
| Azure | `tflint-ruleset-azurerm` |
| Google | `tflint-ruleset-google` |

Plugin versions come from your `versions.json`.

### Tagged Overrides

Tags apply preset rule changes:

- `standalone_module` - Disables documentation rules
- `consumer_module` - Enables strict documentation rules
- `test_module` - Disables documentation and naming rules

```starlark
tf_module(
    name = "my_module",
    srcs = ["main.tf", "variables.tf"],
    tags = ["standalone_module"],
)
```

### Manual Overrides

Override specific rules:

```starlark
tf_module(
    name = "my_module",
    srcs = ["main.tf", "variables.tf"],
    rule_overrides = {
        "terraform_naming_convention.enabled": "false",
    },
)
```

Or provide your own `.tflint.hcl`:

```starlark
tf_module(
    name = "my_module",
    srcs = ["main.tf", "variables.tf"],
    tflint_config = ".tflint.hcl",
)
```

## The tf2 Plugin

rules_tf2 includes `tflint-ruleset-tf2` with enhanced rules. See [Reference: tflint-ruleset-tf2](../../reference/tflint/README.md) for available rules.

## Formatting

`*_format_test` checks `terraform fmt` compliance. `*_format` fixes issues in place:

```bash
bazel run //path/to:my_module_format
```
