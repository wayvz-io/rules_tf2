# Test case: Resources with all required tags should pass
#
# This test verifies that when all AWS resources have the required
# tags (Environment, Owner, Project), the policy passes.

mock "tfplan/v2" {
  module {
    source = "../../mocks/mock-tfplan-pass.sentinel"
  }
}

test {
  rules = {
    main = true
  }
}
