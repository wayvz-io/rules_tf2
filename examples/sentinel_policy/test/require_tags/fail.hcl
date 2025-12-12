# Test case: Resources missing required tags should fail
#
# This test verifies that when AWS resources are missing required
# tags (Environment, Owner, Project), the policy fails.

mock "tfplan/v2" {
  module {
    source = "../../mocks/mock-tfplan-fail.sentinel"
  }
}

test {
  rules = {
    main = false
  }
}
