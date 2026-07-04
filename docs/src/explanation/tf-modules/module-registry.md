# Module Registry Publishing

rules_tf2 can publish modules to Terraform Registry (HCP Terraform / Terraform Enterprise).

## What Gets Published

The published bundle includes:

- **Module sources** - Files declared in `srcs`
- **Nested modules** - Child modules from `modules` attribute
- **Documentation** - README and generated docs

Only Bazel-exposed files are included. No stray files, no build artifacts. The
generated `.terraform.lock.hcl` is intentionally *not* bundled (consumers
resolve providers themselves) — consistent with the `*_no_lockfile_test`.

## tf_publish_registry

```starlark
tf_publish_registry(
    name = "publish",
    module = ":my_module",
    organization = "my-org",
    namespace = "my-namespace",
    module_name = "vpc",
    provider = "aws",
)
```

Run with:

```bash
bazel run //path/to:publish
```

## Authentication

Authentication requires the `TFE_TOKEN` environment variable — the publish
script exits if it is unset. There is no credentials-file fallback.

The registry endpoint defaults to `app.terraform.io`; point it at a Terraform
Enterprise host with the `registry` attribute.

## Versioning

The publish rule computes the next version automatically. It queries the registry for the module's current highest version and bumps it. Control which component is bumped with the `version_increment` attribute (`major`, `minor`, or `patch`; defaults to `patch`), or override the increment at run time:

```bash
bazel run //path/to:publish -- --version-type minor
```

You can also pin an exact version, bypassing auto-computation:

```bash
bazel run //path/to:publish -- --version 2.0.0
```

## See Also

- [tf_publish_registry Reference](../../reference/publishing/tf-publish-registry.md)
