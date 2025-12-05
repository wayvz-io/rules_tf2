# Example Terraform test demonstrating standalone tf_test usage
#
# This test validates that the basic_module correctly creates
# resources with the expected configuration

mock_provider "aws" {}

# Override random_pet to have predictable values at plan time
override_resource {
  target = random_pet.instance
  override_during = plan
  values = {
    id = "test-pet"
  }
}

run "validate_security_group_configuration" {
  command = plan

  variables {
    ami_id          = "ami-12345678"
    instance_type   = "t3.micro"
    ssh_cidr_blocks = ["10.0.0.0/8"]
    tags = {
      Environment = "test"
    }
  }

  # Verify security group name includes "example-" prefix
  # With the override, the name will be "example-test-pet"
  assert {
    condition     = aws_security_group.instance.name == "example-test-pet"
    error_message = "Security group name should be 'example-test-pet'"
  }

  # Verify security group description is set
  assert {
    condition     = aws_security_group.instance.description == "Security group for example instance"
    error_message = "Security group should have correct description"
  }

  # Verify SSH ingress rule is configured correctly
  assert {
    condition     = aws_vpc_security_group_ingress_rule.ssh.from_port == 22
    error_message = "SSH ingress rule should be on port 22"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.ssh.to_port == 22
    error_message = "SSH ingress rule should end on port 22"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.ssh.ip_protocol == "tcp"
    error_message = "SSH ingress rule should use TCP protocol"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.ssh.cidr_ipv4 == "10.0.0.0/8"
    error_message = "SSH ingress rule should use correct CIDR"
  }
}

run "validate_instance_configuration" {
  command = plan

  variables {
    ami_id          = "ami-12345678"
    instance_type   = "t3.micro"
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

  # Verify AMI is set correctly
  assert {
    condition     = aws_instance.example.ami == "ami-12345678"
    error_message = "Instance AMI should be ami-12345678"
  }

  # Verify tags include Environment
  assert {
    condition     = aws_instance.example.tags["Environment"] == "test"
    error_message = "Instance should have Environment tag set to 'test'"
  }

  # Verify instance name tag uses the pet name
  assert {
    condition     = aws_instance.example.tags["Name"] == "example-test-pet"
    error_message = "Instance Name tag should be 'example-test-pet'"
  }
}

run "validate_egress_rule" {
  command = plan

  variables {
    ami_id          = "ami-12345678"
    instance_type   = "t3.micro"
    ssh_cidr_blocks = ["10.0.0.0/8"]
    tags = {
      Environment = "test"
    }
  }

  # Verify egress rule allows all traffic
  assert {
    condition     = aws_vpc_security_group_egress_rule.all.ip_protocol == "-1"
    error_message = "Egress rule should allow all protocols"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.all.cidr_ipv4 == "0.0.0.0/0"
    error_message = "Egress rule should allow all destinations"
  }
}
