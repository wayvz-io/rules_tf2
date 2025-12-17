# Development deployment
identity_token "aws" {
  audience = ["aws.workload.identity"]
}

deployment "dev" {
  inputs = {
    environment = "dev"
  }
}
