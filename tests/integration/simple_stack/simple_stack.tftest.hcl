# Test for simple_stack

variables {
  # No input variables for this stack
}

run "test_stack_outputs" {
  command = apply

  assert {
    condition     = output.greeting == "Hello World from tf2 stack!"
    error_message = "Greeting output should match expected value"
  }

  assert {
    condition     = endswith(output.hello_world_file, "hello-world.txt")
    error_message = "File output should end with hello-world.txt"
  }

  assert {
    condition     = can(regex("Hello, World from tf2 stack!", local_file.hello_world.content))
    error_message = "File should contain the expected greeting"
  }
}