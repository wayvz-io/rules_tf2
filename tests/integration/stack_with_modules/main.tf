# Stack that uses local modules
# This should copy the modules into the stack directory

module "simple" {
  source = "../simple_module"

  # Pass any required variables
}

module "another" {
  source = "../another_module"
}

# Also use remote modules (should not be copied)
module "null" {
  source  = "vancluever/module/null"
  version = "2.0.2"
}
