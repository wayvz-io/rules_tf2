# This should trigger organization validation - variables should be in variables.tf
variable "test_variable" {
  type        = string
  description = "A test variable that should be in variables.tf"
  default     = "test"
}
