run "test_output" {
  assert {
    condition     = length(output.id) > 0
    error_message = "ID should not be empty"
  }
}
