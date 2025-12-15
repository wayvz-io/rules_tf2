# Use the external label module from the Terraform Registry
# The source path will be rewritten from "cloudposse/label/null" to "./modules/label_null_0"
# Note: Don't use "version" here - the version is pinned in versions.json
module "label" {
  source = "cloudposse/label/null"

  namespace   = var.namespace
  environment = var.environment
  name        = var.name
}


# Use the label outputs
resource "null_resource" "example" {
  triggers = {
    id = module.label.id
  }
}
