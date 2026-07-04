# External Module Versioning

rules_tf2 can pin and download external Terraform modules from Git repositories
and the Terraform Module Registry so that they become Bazel dependencies with
hashed, reproducible sources. Modules are declared in `versions.json` and exposed
through the `tf_modules` module extension as the `@tf_module_registry` repository.

## Declaring modules

Add a `modules` block to `versions.json`:

```json
{
  "modules": {
    "registry": {
      "registry.terraform.io": {
        "terraform-aws-modules/vpc/aws": ["5.0.0", "5.1.0"]
      },
      "app.terraform.io": {
        "my-org/my-module/aws": ["1.0.0"]
      }
    },
    "git": {
      "github.com/terraform-aws-modules/terraform-aws-s3-bucket": ["v4.0.0"],
      "git::https://github.com/example/repo.git": ["abc1234"]
    }
  }
}
```

- **registry** - Terraform Registry modules, namespaced by hostname.
  - `registry.terraform.io` - public registry (`namespace/name/provider`).
  - `app.terraform.io` or a custom hostname - private registry, authenticated
    with `TFE_TOKEN`.
- **git** - Git repositories pinned to a tag or short commit hash. Use the
  `github.com/owner/repo` shorthand or a full `git::https://...` URL.

## Wiring the extension

Register the extension in `MODULE.bazel`:

```starlark
tf_modules = use_extension("@rules_tf2//tf2:extensions.bzl", "tf_modules")
tf_modules.download(
    versions_file = "path/to/versions.json",
)
use_repo(tf_modules, "tf_module_registry")
```

## Aliasing

Like providers, external modules are aliased to a stable label:

- Registry: `terraform-aws-modules/vpc/aws:5.0.0` -> `vpc_aws_5`
- Git: `github.com/hashicorp/consul:v0.11.0` -> `hashicorp_consul_0_11_0`
- Private: `my-org/mod/aws:1.0.0` -> `mod_aws_1`

Reference them from a `tf_module` through the `modules` attribute:

```starlark
tf_module(
    name = "my_deployment",
    srcs = [
        "main.tf",
        "outputs.tf",
        "terraform.tf",
        "variables.tf",
        "README.md",
    ],
    providers = ["@tf_provider_registry//:aws_6"],
    modules = [
        "//my/local/module:tf_module",     # Local module
        "@tf_module_registry//:vpc_aws_5",  # External module
    ],
)
```

## See Also

- [Module Registry](../tf-modules/module-registry.md)
- [Provider Versioning](providers.md)
