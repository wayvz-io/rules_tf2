variable "ami_id" {
  type        = string
  description = "The AMI ID for the EC2 instance"
}

variable "instance_type" {
  type        = string
  description = "The EC2 instance type"
  default     = "t3.micro"
}

variable "ssh_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed for SSH access"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}