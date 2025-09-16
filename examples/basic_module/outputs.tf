output "instance_id" {
  value       = aws_instance.example.id
  description = "The ID of the EC2 instance"
}

output "instance_public_ip" {
  value       = aws_instance.example.public_ip
  description = "The public IP address of the EC2 instance"
}

output "security_group_id" {
  value       = aws_security_group.instance.id
  description = "The ID of the security group"
}

output "instance_name" {
  value       = random_pet.instance.id
  description = "The randomly generated name for this instance"
}