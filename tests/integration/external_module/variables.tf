variable "namespace" {
  type        = string
  description = "Namespace for resource naming"
  default     = "test"
}


variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}


variable "name" {
  type        = string
  description = "Name for the resource"
  default     = "example"
}
