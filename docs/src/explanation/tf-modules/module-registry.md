# Module Registry Publishing

rules_tf2 can publish modules to Terraform Registry (HCP Terraform / Terraform Enterprise).

## What Gets Published

The published bundle includes:

- **Module sources** - Files declared in `srcs`
- **Nested modules** - Child modules from `modules` attribute
- **Generated lockfile** - `.terraform.lock.hcl` for reproducible provider versions

Only Bazel-exposed files are included. No stray files, no build artifacts.

## tf_publish_registry

```starlark
tf_publish_registry(
    name = "publish",
    module = ":my_module",
    organization = "my-org",
    namespace = "my-namespace",
    module_name = "vpc",
)
```

Run with:

```bash
bazel run //path/to:publish
```

## Authentication

Authentication uses one of:

- `TFE_TOKEN` environment variable
- Terraform CLI credentials (`~/.terraform.d/credentials.tfrc.json`)

The registry API endpoint is derived from your Terraform Cloud/Enterprise configuration.

## Versioning

Module versions typically come from git tags or CI build numbers. The publish rule accepts a `version` attribute or reads from environment variables.

## See Also

- [tf_publish_registry Reference](../../reference/publishing/tf-publish-registry.md)
