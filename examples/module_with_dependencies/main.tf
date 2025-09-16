# Module with Dependencies Example
# This demonstrates how to compose modules together

# Use the basic module to create an instance
module "web_server" {
  # This module gets rewritten to ./modules/basic_module through the build process
  # to ensure that execution through the build agent doesn't run into base path issues, and that modules
  # are all inclusive and pinned.
  source = "../basic_module"

  ami_id          = var.web_ami_id
  instance_type   = var.web_instance_type
  ssh_cidr_blocks = var.admin_cidr_blocks

  tags = merge(
    var.common_tags,
    {
      Role = "web"
    }
  )
}

# Create an application load balancer
resource "aws_lb" "web" {
  name               = "${var.environment}-web-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-web-lb"
    }
  )
}

# Target group for the load balancer
resource "aws_lb_target_group" "web" {
  name     = "${var.environment}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = var.common_tags
}

# Attach the instance from the module to the target group
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = module.web_server.instance_id
  port             = 80
}

# Listener for the load balancer
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
