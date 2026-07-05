# Module that imports another local module
module "simple" {
  source = "../simple_module"

  # Pass through any required variables
}

# External registry module (version pinned in versions.json)
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "test-vpc"
  cidr = "10.0.0.0/16"
}

# External git submodule (//subpath)
module "git_module" {
  source        = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-account"
  account_alias = "example-account-alias"
}

# External git module with a real root module
module "git_root" {
  source = "github.com/cloudposse/terraform-null-label"
}

# Another relative module
module "another" {
  source = "../another_module"
}