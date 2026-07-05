# Generate BUILD files with Gazelle

Auto-generate and update `tf_module` / `tf_test` targets for directories of
Terraform files, instead of hand-writing `BUILD.bazel`.

## Prerequisites

- A Gazelle binary that includes the rules_tf2 `terraform` language plugin, wired
  to a `gazelle` target. See the [Gazelle Extension reference](../reference/gazelle/README.md)
  for the `gazelle_binary` setup.

## Steps

1. Run Gazelle over a path (or the whole repo):

   ```bash
   bazel run //:gazelle -- path/to/modules
   ```

2. For each directory containing `.tf` files, Gazelle writes a `tf_module` with
   **explicit `srcs`** (never globs) — all `.tf` files, referenced templates, and
   `README.md`. When `.tftest.hcl` files are present it also emits a `tf_test`
   wired to that module.

3. Re-run it any time the files change; Gazelle updates `srcs` in place while
   **preserving** hand-set attributes (`providers`, `tflint_config`,
   `tfdoc_config`, `visibility`, `skip_validation`, `tags`, `testonly`).

## Directives

Control generation with `# gazelle:` comments in a `BUILD.bazel`:

```starlark
# gazelle:terraform_enabled false                      # skip this directory
# gazelle:terraform_provider aws @tf_provider_registry//:aws_6   # map a provider to a registry label
# gazelle:terraform_ignore_file_warning secrets.tf     # silence the dynamic-path warning for a file
```

`providers` is only emitted when a `terraform_provider` directive maps the
`required_providers` in `terraform.tf` to registry labels.

## Verification

The generated `BUILD.bazel` builds and tests: `bazel test //path/to:all`.

## See also

- [Gazelle Extension reference](../reference/gazelle/README.md)
- [Gazelle versioning](../explanation/versioning/gazelle.md)
