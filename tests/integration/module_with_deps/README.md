<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.12.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 5.100.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | 2.5.3 |
| <a name="requirement_null"></a> [null](#requirement\_null) | 3.2.4 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.7.2 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_another"></a> [another](#module\_another) | ../another_module | n/a |
| <a name="module_git_module"></a> [git\_module](#module\_git\_module) | git::https://github.com/terraform-aws-modules/terraform-aws-iam.git | v5.0.0 |
| <a name="module_simple"></a> [simple](#module\_simple) | ../simple_module | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0 |

## Resources

No resources.

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_simple_module_output"></a> [simple\_module\_output](#output\_simple\_module\_output) | Output from the simple module |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID from remote module |
<!-- END_TF_DOCS -->