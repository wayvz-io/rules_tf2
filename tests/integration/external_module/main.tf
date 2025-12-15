# Use the external label module from the Terraform Registry
module "label" {
  source = "./modules/label_null_0"

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
