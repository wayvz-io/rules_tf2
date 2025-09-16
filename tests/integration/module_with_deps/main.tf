# Module that imports another local module
module "simple" {
  source = "../simple_module"

  # Pass through any required variables
}

# Also test remote module (should not require dependency)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "test-vpc"
  cidr = "10.0.0.0/16"
}

# Git module (should not require dependency)
module "git_module" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git?ref=v5.0.0"
}

# Another relative module
module "another" {
  source = "../another_module"
}