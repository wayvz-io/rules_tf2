# Example Terraform test demonstrating standalone tf_test usage
#
# This test validates that the basic_module correctly creates
# resources with the expected configuration

run "validate_security_group_name" {
  command = plan

  variables {
    ami_id        = "ami-12345678"
    instance_type = "t3.micro"
    ssh_cidr_blocks = ["10.0.0.0/8"]
    tags = {
      Environment = "test"
    }
  }

  # Verify security group name includes random pet
  assert {
    condition     = length(regexall("^example-", aws_security_group.instance.name)) > 0
    error_message = "Security group name should start with 'example-'"
  }

  # Verify security group has SSH ingress rule
  assert {
    condition     = contains([for rule in aws_security_group.instance.ingress : rule.from_port], 22)
    error_message = "Security group should allow SSH on port 22"
  }
}

run "validate_instance_configuration" {
  command = plan

  variables {
    ami_id        = "ami-12345678"
    instance_type = "t3.micro"
    ssh_cidr_blocks = ["10.0.0.0/8"]
    tags = {
      Environment = "test"
    }
  }

  # Verify instance type
  assert {
    condition     = aws_instance.example.instance_type == "t3.micro"
    error_message = "Instance type should be t3.micro"
  }

  # Verify instance has security group attached
  assert {
    condition     = length(aws_instance.example.vpc_security_group_ids) > 0
    error_message = "Instance should have at least one security group"
  }

  # Verify tags include Environment
  assert {
    condition     = contains(keys(aws_instance.example.tags), "Environment")
    error_message = "Instance should have Environment tag"
  }
}
