# CDKTF Generation Tests

This directory contains tests for the CDKTF (CDK for Terraform) generation functionality in the tf2 Bazel module.

## Overview

The tf2 module now supports generating CDKTF provider bindings using the same provider definitions used for Terraform. This enables:

1. **Language-specific bindings** - Generate bindings for Go, TypeScript, Python, Java, or C#
2. **Reuse provider definitions** - Use the same `provider_mirror` targets for both Terraform and CDKTF
3. **Host tool integration** - Uses `cdktf` from the Nix environment (no toolchain downloads)

## Basic Usage

### Generate CDKTF Bindings

```starlark
load("@tf2//tf:def.bzl", "cdktf_generate")

cdktf_generate(
    name = "aws_bindings",
    provider_alias = "//providers:aws_6",
    language = "go",  # or "typescript", "python", "java", "csharp"
)
```

This creates a target that generates CDKTF bindings for the specified provider.

### Go Library Generation (with compilation)

```starlark
load("@tf2//tf:def.bzl", "cdktf_go_library")

cdktf_go_library(
    name = "aws_cdktf_lib",
    provider_alias = "//providers:aws_6",
    importpath = "github.com/example/generated/aws",
    visibility = ["//visibility:public"],
)
```

This macro combines `cdktf_generate` with `go_library` to create a compilable Go library.

**Note**: To use `cdktf_go_library`, you need to add CDKTF dependencies to your MODULE.bazel:

```starlark
go_deps.module(
    path = "github.com/aws/jsii-runtime-go",
    version = "v1.94.0",
)
go_deps.module(
    path = "github.com/hashicorp/terraform-cdk-go/cdktf",
    version = "v0.20.3",
)
```

## How It Works

1. **Provider Info** - The rule reads provider information from `provider_registry_alias` targets
2. **cdktf.json Generation** - Creates a cdktf.json configuration file with provider details
3. **cdktf get Execution** - Runs `cdktf get` to generate language-specific bindings
4. **Output Directory** - Generated files are placed in a Bazel-managed output directory

## Implementation Details

The implementation uses:
- **Native Starlark actions** - Minimal bash scripting for maintainability
- **Proper temp directory handling** - Handles CDKTF's temp file requirements
- **Go module support** - Automatically creates go.mod for Go projects
- **Error tolerance** - Handles cdktf's non-zero exit codes when files are still generated

## Files

- `BUILD.bazel` - Test targets for Go generation
- `typescript_test.bazel` - Test targets for TypeScript/Python generation
- `test_generated.go` - Example file showing how generated bindings would be used

## Requirements

- `cdktf` CLI tool (provided by Nix flake)
- `go` for Go bindings (provided by Nix flake)
- Network access for downloading provider schemas

## Testing

```bash
# From the tf2 directory
nix develop ../../../flake -c bazel build //tests/cdktf_test:all

# Build specific targets
nix develop ../../../flake -c bazel build //tests/cdktf_test:local_cdktf_gen
nix develop ../../../flake -c bazel build //tests/cdktf_test:null_cdktf_gen
```