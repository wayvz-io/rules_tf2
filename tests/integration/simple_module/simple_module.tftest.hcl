# Test for simple_module

variables {
  # No input variables for this module
}

run "test_random_string_configuration" {
  command = plan

  assert {
    condition     = random_string.test.length == 16
    error_message = "Random string should be configured for 16 characters"
  }

  assert {
    condition     = random_string.test.special == false
    error_message = "Random string should not contain special characters"
  }
}

run "test_outputs" {
  command = apply

  assert {
    condition     = output.greeting == "Hello from tf2 module!"
    error_message = "Greeting output should match expected value"
  }

  assert {
    condition     = length(output.random_value) == 16
    error_message = "Random value output should be 16 characters long"
  }

  assert {
    condition     = can(regex("^[a-zA-Z0-9]+$", output.random_value))
    error_message = "Random value should only contain alphanumeric characters"
  }
}