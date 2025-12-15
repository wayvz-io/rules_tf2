run "test_contract" {
  assert {
    condition     = jsondecode(file("//path/to/contracts:schema.json")).valid == true
    error_message = "Contract validation failed"
  }
}

run "test_local" {
  assert {
    condition     = file("local_data.txt") != ""
    error_message = "Local file is empty"
  }
}
