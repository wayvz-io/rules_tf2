# External Module Integration Test

This module tests the integration of external Terraform modules from the
Terraform Module Registry.

It uses the `cloudposse/label/null` module to generate resource labels.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.13.2 |
| <a name="requirement_null"></a> [null](#requirement\_null) | 3.3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_null"></a> [null](#provider\_null) | 3.3.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_label"></a> [label](#module\_label) | cloudposse/label/null | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [null_resource.example](https://registry.terraform.io/providers/hashicorp/null/3.3.0/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name | `string` | `"dev"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the resource | `string` | `"example"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for resource naming | `string` | `"test"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_label_id"></a> [label\_id](#output\_label\_id) | The generated label ID from the external module |
| <a name="output_label_tags"></a> [label\_tags](#output\_label\_tags) | The generated tags from the external module |
<!-- END_TF_DOCS -->