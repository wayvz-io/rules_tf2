# Basic Module Example
# This demonstrates a simple AWS EC2 instance with associated resources
# This module uses null provider to demonstrate provider inheritance

# Random pet name for unique naming
resource "random_pet" "instance" {
  length = 2
}

resource "null_resource" "example_provisioner" {
  triggers = {
    instance_id = aws_instance.example.id
  }

  provisioner "local-exec" {
    command = "echo Instance ${aws_instance.example.id} created"
  }
}

# Security group for the instance
resource "aws_security_group" "instance" {
  name        = "example-${random_pet.instance.id}"
  description = "Security group for example instance"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "example-${random_pet.instance.id}"
    }
  )
}

# EC2 Instance
resource "aws_instance" "example" {
  ami           = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.instance.id]

  tags = merge(
    var.tags,
    {
      Name = "example-${random_pet.instance.id}"
    }
  )
}