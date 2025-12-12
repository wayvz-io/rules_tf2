# Terraform Stacks

Terraform Stacks is an HCP Terraform feature for orchestrating infrastructure across multiple environments. The `tf_stack` macro integrates stacks into the Bazel build system.

## How tf_stack Works

A stack references existing `tf_module` targets as components. The macro:

1. Aggregates providers from all referenced modules
2. Stages modules to a `./components/` directory structure
3. Generates `.terraform.lock.hcl` and `.terraform-version`
4. Creates format, validate, and dependency test targets

```starlark
tf_stack(
    name = "infra_stack",
    srcs = [
        "components.tfcomponent.hcl",
        "providers.tfcomponent.hcl",
        "dev.tfdeploy.hcl",
    ],
    modules = [":vpc", ":eks"],
)
```

## Module Staging

Referenced modules are staged to the `./components/` directory:

```
exported_stack/
├── *.tfcomponent.hcl        # Component definitions
├── *.tfdeploy.hcl           # Deployment configurations
├── components/              # Staged modules
│   ├── vpc/
│   │   ├── main.tf
│   │   └── variables.tf
│   └── eks/
│       └── ...
├── .terraform.lock.hcl      # Generated lockfile
└── .terraform-version       # Generated version file
```

Component files reference modules via `source = "./components/vpc"`.

## Provider Inheritance

Stacks inherit providers from all referenced modules. The generated lockfile includes all transitive providers from the module dependency tree.

When you update provider versions via `versions.json`, run the tf-update workflow to regenerate stack lockfiles.

## Generated Targets

| Target | Description |
|--------|-------------|
| `:stack` | Main stack target |
| `:stack_format_test` | Check HCL formatting |
| `:stack_validate_test` | Run `terraform stacks validate` |
| `:stack_deps_test` | Verify module references |
| `:stack_file_export` | Export to directory |

## Requirements

- Terraform >= 1.13.0 with Stacks support
- HCP Terraform account for `terraform stacks validate` and `terraform stacks fmt`

For local development without HCP Terraform, use `skip_validation = True`.

## See Also

- [tf_stack Reference](../reference/rules/tf-stack.md) - Full attribute documentation
