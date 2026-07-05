# Use an external module

Consume a Terraform module from the Terraform Registry or a Git repository,
pinned and version-managed like providers.

## Prerequisites

- rules_tf2 in `MODULE.bazel`.

## Steps

1. Declare the module in `versions.json` under `modules` — `registry` (namespaced
   by hostname) and/or `git` (tag or short commit):

   ```json
   {
     "modules": {
       "registry": {
         "registry.terraform.io": {
           "terraform-aws-modules/vpc/aws": ["5.0.0"]
         },
         "app.terraform.io": {
           "my-org/my-module/aws": ["1.0.0"]
         }
       },
       "git": {
         "github.com/terraform-aws-modules/terraform-aws-s3-bucket": ["v4.0.0"]
       }
     }
   }
   ```

   `registry.terraform.io` is the public registry; any other host is a private
   registry (authed with `TFE_TOKEN`).

2. Wire the `tf_modules` extension into `MODULE.bazel`:

   ```starlark
   tf_modules = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_modules")
   tf_modules.download(versions_file = "//path/to:versions.json")
   use_repo(tf_modules, "tf_module_registry")
   ```

3. Reference the module by its alias in a `tf_module`'s `modules` attribute. The
   alias is `{name}_{provider}_{major}` for registry modules
   (`terraform-aws-modules/vpc/aws:5.0.0` → `vpc_aws_5`):

   ```starlark
   tf_module(
       name = "my_deployment",
       srcs = ["main.tf", "terraform.tf", "variables.tf", "README.md"],
       providers = ["@tf_provider_registry//:aws_6"],
       modules = [
           "//my/local/module:tf_module",      # local
           "@tf_module_registry//:vpc_aws_5",   # external
       ],
   )
   ```

## Verification

`bazel build //path/to:my_deployment` resolves the external module from
`@tf_module_registry`; the module's tests run against it offline.

## See also

- [External Modules](../explanation/versioning/external-modules.md) — full schema and aliasing rules
- [Module Registry Publishing](../explanation/tf-modules/module-registry.md)
