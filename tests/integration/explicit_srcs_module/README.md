# Explicit Sources Module

Example module demonstrating explicit `srcs` attribute for ibazel file watching.

## Description

This module demonstrates the recommended pattern for tf_module when using ibazel:

```python
tf_module(
    name = "explicit_srcs_module",
    srcs = glob(["*.tf"]) + ["README.md"],
    providers = [...],
)
```

By explicitly declaring source files with `glob()` in the BUILD.bazel file, ibazel can properly track file changes and automatically re-trigger tests.

## Usage

This is a test module that creates a random string resource.

### Inputs

No input variables.

### Outputs

| Name | Description |
|------|-------------|
| result | The generated random string |

## ibazel Testing

To test ibazel file watching with this module:

```bash
# Start ibazel
ibazel test //tests/integration/explicit_srcs_module:all

# In another terminal, modify a .tf file
echo '# test change' >> tests/integration/explicit_srcs_module/main.tf

# Observe that tests automatically re-trigger within 1-2 seconds
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.13.2 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.9.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [random_string.example](https://registry.terraform.io/providers/hashicorp/random/3.9.0/docs/resources/string) | resource |

## Inputs

No inputs.

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_result"></a> [result](#output\_result) | n/a |
<!-- END_TF_DOCS -->