# tflint-ruleset-tf2

Custom TFLint plugin with rules for enforcing Terraform conventions.

> These are **TFLint rules**, not Bazel rules. They ship as a TFLint plugin
> (`tflint-ruleset-tf2`, built on the `tflint-plugin-sdk`) and are configured as
> HCL `rule "..." {}` blocks in a `.tflint.hcl` file — `tf_module`'s lint tests
> run them automatically. See [Linting](../../explanation/tf-modules/linting.md).

## Rules

### tf2_terraform_required_providers

Validates `required_providers` configuration. Enabled by default.

Checks:
- All providers have explicit `required_providers` entries
- `source` attribute is present
- `version` constraint is present
- Provider versions match configured constraints (optional)
- Provider whitelist enforcement (optional)

**Configuration:**

```hcl
rule "tf2_terraform_required_providers" {
  enabled = true

  # Require source/version attributes (default: true)
  source  = true
  version = true

  # Optional: enforce specific provider versions
  providers = {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Optional: only allow providers in the list above
  provider_whitelist = false
}
```

### tf2_terraform_file_organization

Enforces standard file naming conventions. Enabled by default.

| Block Type | Expected File |
|------------|---------------|
| `terraform` | `terraform.tf` |
| `provider` | `providers.tf` |
| `variable` | `variables.tf` |
| `output` | `outputs.tf` |
| `import` | `imports.tf` |

**Configuration:**

```hcl
rule "tf2_terraform_file_organization" {
  enabled = true
}
```

## Installation

The plugin is built as part of `rules_tf2` and automatically included when using `tf_module` targets. To use standalone:

```bash
bazel build //go/tflint_ruleset:tflint-ruleset-tf2
```

Binary output: `bazel-bin/go/tflint_ruleset/tflint-ruleset-tf2_/tflint-ruleset-tf2`
