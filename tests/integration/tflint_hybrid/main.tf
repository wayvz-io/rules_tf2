# Resource with poor naming convention (should trigger tflint naming rules)
resource "aws_instance" "badName" {
  ami           = "ami-12345678"
  instance_type = "t3.micro"

  tags = {
    Name = "test-instance"
  }
}


# Random resource to test multiple providers
resource "random_id" "test" {
  byte_length = 8
}


# Data source
data "aws_availability_zones" "available" {
  state = "available"
}
