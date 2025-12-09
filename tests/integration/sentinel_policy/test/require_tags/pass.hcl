# Test case: Resources with all required tags should pass

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
