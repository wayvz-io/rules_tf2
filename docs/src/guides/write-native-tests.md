# Write native Terraform tests

Add native Terraform tests (`.tftest.hcl`) to a module and run them hermetically
under Bazel with `tf_test`.

## Prerequisites

- A working `tf_module` — see [Create and test a module](create-and-test-a-module.md).

> **Note:** `tf_module` does **not** auto-generate a native test target. A
> `.tftest.hcl` in `srcs` is just a source file. You declare `tf_test`
> explicitly (or let [Gazelle](generate-build-files.md) generate it when it sees
> `.tftest.hcl` files).

## Steps

1. Write a test file next to the module, e.g. `example_test.tftest.hcl`:

   ```hcl
   mock_provider "aws" {}

   run "validate_security_group" {
     command = plan

     variables {
       ami_id        = "ami-12345678"
       instance_type = "t3.micro"
     }

     assert {
       condition     = aws_security_group.instance.name == "example-test-pet"
       error_message = "Security group name should be 'example-test-pet'"
     }
   }
   ```

   Use `mock_provider` / `override_resource` to keep the test offline (no real
   cloud calls).

2. Declare a `tf_test` in `BUILD.bazel`, pointing `module` at the `tf_module`
   and listing the test files:

   ```starlark
   load("@rules_tf2//tf2:def.bzl", "tf_test")

   tf_test(
       name = "my_module_test",
       module = ":my_module",
       test_files = ["example_test.tftest.hcl"],
       size = "small",
   )
   ```

   `module` and `test_files` are both required.

3. Run it:

   ```bash
   bazel test //path/to:my_module_test
   ```

   It runs `terraform test` offline: `terraform init -backend=false` against the
   provider mirror, no network, no state.

## Verification

The test target passes. It reuses the module's staged sources and generated
lockfile, so it stays consistent with the rest of the suite.

> If you tag a `tf_test` `["manual"]`, it is excluded from `bazel test //...`
> and `:all` — run it by name.

## See also

- [`tf_test` reference](../reference/rules/tf-test.md)
- [Testing](../explanation/tf-modules/testing.md)
- [Test policies (OPA & Sentinel)](test-policies.md) — policy tests, distinct from native tests
