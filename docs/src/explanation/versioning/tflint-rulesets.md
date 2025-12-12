# TFLint Ruleset Versioning

The `tflint_plugins` section of `versions.json` specifies versions for TFLint rulesets:

```json
{
  "tflint_plugins": {
    "aws": "0.27.0",
    "azurerm": "0.25.0",
    "google": "0.26.0",
    "opa": "0.9.0"
  }
}
```

## Default Plugins

rules_tf2 downloads these plugins by default when specified:

- `aws` → `tflint-ruleset-aws`
- `azurerm` → `tflint-ruleset-azurerm`
- `google` → `tflint-ruleset-google`
- `opa` → `tflint-ruleset-opa`

Only include plugins you use—they're downloaded on demand.

## Plugin Registry

Plugins are available through `@tflint_plugin_registry`:

```starlark
@tflint_plugin_registry//:aws
@tflint_plugin_registry//:azurerm
```

When a module declares providers, rules_tf2 automatically enables the corresponding plugin in the generated `.tflint.hcl`.

## The tf2 Plugin

rules_tf2 includes `tflint-ruleset-tf2`, a built-in plugin with enhanced rules. Unlike downloaded plugins, this is built from source at `//go/tflint_ruleset:tflint-ruleset-tf2`.

It provides improved versions of standard rules, including `terraform_required_providers` with allowlist support and autofix.

## Adding Other Rulesets

To add a ruleset not in the default list:

1. Add it to `tflint_plugins` in `versions.json`
2. Ensure the plugin follows the `tflint-ruleset-{name}` naming convention on GitHub
3. Rebuild—the extension downloads from `terraform-linters/tflint-ruleset-{name}`

For plugins outside the `terraform-linters` org, you'll need to extend the download configuration.
