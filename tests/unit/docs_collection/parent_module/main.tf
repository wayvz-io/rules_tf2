resource "random_pet" "parent" {
  length = 2
}

module "child" {
  source = "../child_module"
}
