# Development deployment configuration

deployment "development" {
  inputs = {
    environment = "dev"
    region      = "us-west-2"
  }
}

# Auto-approve development deployments
orchestrate "default" {
  check {
    condition = context.plan.changes.total < 100
    message   = "Development deployment has too many changes"
  }
}
