output "load_balancer_dns" {
  value       = aws_lb.web.dns_name
  description = "DNS name of the load balancer"
}

output "load_balancer_arn" {
  value       = aws_lb.web.arn
  description = "ARN of the load balancer"
}

output "web_instance_id" {
  value       = module.web_server.instance_id
  description = "ID of the web server instance"
}

output "web_instance_ip" {
  value       = module.web_server.instance_public_ip
  description = "Public IP of the web server instance"
}

output "web_security_group_id" {
  value       = module.web_server.security_group_id
  description = "Security group ID of the web server"
}