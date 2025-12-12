# Test case: Resources missing required tags should fail

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
