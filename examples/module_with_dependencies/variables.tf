variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, staging, prod)"
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID where resources will be created"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs for the load balancer"
}

variable "web_ami_id" {
  type        = string
  description = "AMI ID for the web server instance"
}

variable "web_instance_type" {
  type        = string
  description = "Instance type for the web server"
  default     = "t3.small"
}

variable "admin_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed for administrative SSH access"
  default     = []
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}