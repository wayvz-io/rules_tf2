# rules_tf2 - Terraform Rules for Bazel

A comprehensive set of Bazel rules for managing Terraform infrastructure with advanced features including Terraform Cloud integration, provider management, and CDKTF support.

## Features

- 🏗️ **Terraform Module & Stack Management** - Define reusable modules and deployable stacks
- ☁️ **Terraform Cloud Integration** - Native support for TFC/TFE workflows  
- 📦 **Provider Management** - Automatic provider downloading and caching
- 🚀 **Arbitrary Command Execution** - Run any terraform command through Bazel
- 🔧 **CDKTF Support** - Generate and use CDK for Terraform bindings
- ✅ **Comprehensive Testing** - Format, lint, validate, and test your Terraform code
- 🐳 **OCI Deployment** - Push Terraform configurations as OCI artifacts
- 🔧 **Host Tool Integration** - Uses terraform/tflint/terraform-docs from Nix environment

## Project Structure

```
tf/
├── core/               # Core functionality
│   ├── rules/         # Module, stack, and variable rules
│   ├── providers/     # Provider management
│   ├── repositories/  # Repository rules
│   └── cdktf/        # CDKTF support
├── macros/            # High-level convenience macros
├── testing/           # Test rules (validate, format, lint, etc.)
├── execution/         # Terraform execution runners
│   └── scripts/      # Shell scripts for execution
├── publish/           # Publishing targets (OCI, Terraform Registry, etc.)
│   └── oci/          # OCI artifact publishing
├── utilities/         # Helper utilities and tools
└── def.bzl           # Public API exports
```

## Quick Start

### 1. Add to MODULE.bazel

```starlark
bazel_dep(name = "rules_tf2", version = "0.1.0")

# For development, use local path override
local_path_override(
    module_name = "rules_tf2",
    path = "../rules_tf2",
)

# Once published, use GitHub archive
# archive_override(
#     module_name = "rules_tf2",
#     urls = ["https://github.com/wayvz-io/rules_tf2/archive/refs/tags/v0.1.0.tar.gz"],
#     strip_prefix = "rules_tf2-0.1.0",
# )

# Configure providers
tf_providers = use_extension("@rules_tf2//tf:extensions.bzl", "tf_providers")
tf_providers.download(
    providers = {
        "hashicorp/aws": ["6.2.0", "5.0.0"],
        "hashicorp/azurerm": ["4.18.0"],
        "hashicorp/google": ["6.17.0"],
    },
)
use_repo(tf_providers, "tf_provider_registry")
```

### 2. Define a Terraform Module

Create a reusable Terraform module:

```starlark
load("@tf2//tf:def.bzl", "tf_module")

tf_module(
    name = "vpc",
    # srcs defaults to all .tf and .tf.json files in the directory
    providers = [
        "@tf_provider_registry//:aws_6",
    ],
)
```

This automatically generates:
- `:vpc` - The module target
- `:vpc_format_test` - Format checking
- `:vpc_lint_test` - Linting with tflint
- `:vpc_doc_test` - Documentation validation
- `:vpc_versions_check_test` - Provider version validation
- `:vpc_deps_test` - Module dependency validation

### 3. Define a Terraform Stack

Create a deployable stack:

```starlark
load("@tf2//tf:def.bzl", "tf_stack", "tf_variables")

# Define variables
tf_variables(
    name = "prod_vars",
    files = ["prod.tfvars"],
)

# Define the stack
tf_stack(
    name = "production",
    # srcs defaults to all .tf files
    modules = [
        "//infrastructure/modules:vpc",
        "//infrastructure/modules:rds",
    ],
    providers = [
        "@tf_provider_registry//:aws_6",
    ],
)
```

Stack targets include all module targets plus:
- `:production_validate_test` - Terraform validation

### 4. Terraform Cloud Integration

Deploy to Terraform Cloud/Enterprise:

```starlark
load("@tf2//tf:def.bzl", "tf_cloud_configuration")

tf_cloud_configuration(
    name = "production",
    stack = "//infrastructure/stacks:production",
    variables = ":prod_vars",
    organization = "my-org",
    workspace_name = "production-us-east-1",
    auto_apply = True,  # Auto-apply after successful plan
)
```

This creates:
- `:production_validate` - Local validation
- `:production_tfc_plan` - Run plan in Terraform Cloud
- `:production_tfc_apply` - Run apply in Terraform Cloud

Run with:
```bash
# Using environment variable
export TFE_TOKEN="your-token"
bazel run //infrastructure:production_tfc_plan

# Using 1Password
op run -- bazel run //infrastructure:production_tfc_plan
```

### 5. Run Arbitrary Terraform Commands

Use `tf_runner` for full terraform CLI access:

```starlark
load("@tf2//tf:def.bzl", "tf_runner")

tf_runner(
    name = "terraform",
    stack = ":production",
    variables = ":prod_vars",
    backend_type = "local",  # or "cloud", "remote"
)
```

Then run any terraform command:
```bash
# State management
bazel run //infrastructure:terraform -- state list
bazel run //infrastructure:terraform -- state show aws_instance.web

# Resource management
bazel run //infrastructure:terraform -- taint aws_instance.web
bazel run //infrastructure:terraform -- untaint aws_instance.web
bazel run //infrastructure:terraform -- import aws_instance.web i-1234567890

# Planning and applying
bazel run //infrastructure:terraform -- plan -target=aws_instance.web
bazel run //infrastructure:terraform -- apply -auto-approve

# Other commands
bazel run //infrastructure:terraform -- refresh
bazel run //infrastructure:terraform -- output -json
bazel run //infrastructure:terraform -- show
bazel run //infrastructure:terraform -- providers
```

## Provider Management

### Using Provider Registry (Recommended)

Providers are automatically downloaded and cached:

```starlark
# In MODULE.bazel
tf_providers.download(
    providers = {
        "hashicorp/aws": ["6.2.0", "5.48.0"],  # Multiple versions
        "hashicorp/random": ["3.7.2"],
    },
)
```

Reference in BUILD files:
```starlark
tf_module(
    name = "my_module",
    providers = [
        "@tf_provider_registry//:aws_6",      # Major version
        "@tf_provider_registry//:aws_5_48",    # Specific version
        "@tf_provider_registry//:random_3",
    ],
)
```

### Manual Provider Mirrors

For air-gapped environments or custom providers:

```starlark
load("@tf2//tf:def.bzl", "provider_mirror")

provider_mirror(
    name = "custom_provider",
    provider = "example.com/custom/provider",
    version = "1.0.0",
    # Will download from the provider's registry
)
```

## Testing

### Automatic Test Generation

Every `tf_module` and `tf_stack` automatically generates comprehensive tests:

| Test Target | Description | Command |
|------------|-------------|---------|
| `*_format_test` | Checks Terraform formatting | `terraform fmt -check` |
| `*_lint_test` | Runs TFLint with config | `tflint` |
| `*_validate_test` | Validates configuration | `terraform validate` |
| `*_versions_check_test` | Verifies provider versions match | Custom check |
| `*_doc_test` | Validates README.md is current | `terraform-docs` |
| `*_deps_test` | Checks module dependencies | Custom check |
| `*_test` | Runs *.tftest.hcl tests | `terraform test` |

Run all tests:
```bash
bazel test //infrastructure/...
```

### Custom Test Configuration

```starlark
tf_module(
    name = "my_module",
    providers = [...],
    tflint_config = "//infrastructure:tflint.hcl",
    tfdoc_config = "//infrastructure:terraform-docs.yml",
)
```

## Advanced Features

### CDKTF Support

Generate CDK for Terraform bindings:

```starlark
# In MODULE.bazel
cdktf_providers = use_extension("@tf2//tf:extensions.bzl", "cdktf_providers")
cdktf_providers.generate(
    provider = "hashicorp/aws",
    version = "6.2.0",
    language = "go",  # or "typescript", "python", "java", "csharp"
)
use_repo(cdktf_providers, "cdktf_aws_6_go")

# In BUILD.bazel
go_library(
    name = "infrastructure",
    srcs = ["main.go"],
    deps = [
        "@cdktf_aws_6_go//aws/...",
        "@com_github_hashicorp_terraform_cdk_go_cdktf//:cdktf",
    ],
)
```

### OCI Artifact Push

Deploy Terraform configurations as OCI artifacts:

```starlark
load("@tf2//tf:def.bzl", "tf_stack_push_oci")

tf_stack_push_oci(
    name = "push",
    stack = ":production",
    registry = "registry.example.com",
    repository = "terraform/production",
    tag = "v1.0.0",
)
```

### Module Dependencies

Compose modules with dependencies:

```starlark
tf_module(
    name = "application",
    deps = [
        "//infrastructure/modules:vpc",
        "//infrastructure/modules:database",
    ],
    providers = [...],
)
```

## Configuration

### Environment Setup

The tf2 rules require tools to be available in PATH. Use the Nix flake:

```bash
# Enter development environment
nix develop

# Or run commands directly
nix develop -c bazel test //...
```

### Terraform Cloud Configuration

Configure via environment or MODULE.bazel:

```starlark
# In MODULE.bazel
tfc_config = use_extension("@tf2//tf:extensions.bzl", "tfc_config")
tfc_config.configure(
    organization = "my-default-org",
    tfe_host = "app.terraform.io",  # Or your TFE instance
    default_auto_apply = False,
)
```

## Migration Guide

### From tf2 v0.0.x

The module structure has been reorganized for better maintainability:

| Old Location | New Location |
|--------------|--------------|
| `//tf/private/rules/*` | `//tf/core/rules/*` |
| `//tf/private/providers/*` | `//tf/core/providers/*` |
| `//tf/private/tests/*` | `//tf/testing/*` |
| `//tf/private/runner/*` | `//tf/execution/*` |
| `//tf/private/oci/*` | `//tf/publish/oci/*` |
| `//tf/private/tools/*` | `//tf/utilities/tools/*` |
| `//tf/private/rules:variables.bzl` | `//tf/core/rules:variables.bzl` |

API changes:
- Removed experimental `*_native` rules
- CDKTF generation moved to MODULE.bazel extensions
- Scripts extracted to external files for debugging

### From Terragrunt/Terraform

Benefits of migrating to Bazel:
- **Dependency tracking** - Bazel knows when to rebuild
- **Parallel execution** - Tests and builds run in parallel
- **Caching** - Provider downloads and test results are cached
- **Hermeticity** - Reproducible builds with pinned versions
- **Unified CI/CD** - Same commands locally and in CI

## Troubleshooting

### Provider Download Issues

If providers fail to download:
```bash
# Clear provider cache
bazel clean --expunge

# Re-download providers
bazel build @tf_provider_registry//...
```

### Terraform Cloud Authentication

```bash
# Check token is set
echo $TFE_TOKEN

# For 1Password users
op run --no-masking -- env | grep TFE_TOKEN

# Test authentication
bazel run //infrastructure:production_validate
```

### Test Failures

```bash
# Run with verbose output
bazel test //infrastructure:my_module_format_test --test_output=all

# Check test logs
cat bazel-testlogs/infrastructure/my_module_format_test/test.log
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

See [LICENSE](../../LICENSE) file in the repository root.