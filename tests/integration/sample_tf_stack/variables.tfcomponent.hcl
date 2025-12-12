# Variables for the sample stack

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, staging, prod)"
}

variable "region" {
  type        = string
  description = "Deployment region"
  default     = "us-west-2"
}
