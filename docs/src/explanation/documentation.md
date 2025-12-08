# About Documentation

## Overview

rules_tf2 uses terraform-docs to generate and validate module documentation. Each `tf_module` gets:

- `*_doc_test` - Verifies README.md matches terraform-docs output
- `*_generate_docs` - Regenerates README.md

## What terraform-docs Generates

terraform-docs extracts documentation from your Terraform files:

- Module description (from header comment or `description` in `main.tf`)
- Input variables (names, types, defaults, descriptions)
- Output values (names, descriptions)
- Required providers

This is rendered into your README.md.

## The doc_test

`*_doc_test` compares your current README.md against what terraform-docs would generate. If they differ, the test fails—your documentation is stale.

This catches:
- New variables added without updating docs
- Outputs renamed without updating docs
- Description changes not reflected in README

## Regenerating Documentation

When the test fails, regenerate your README:

```bash
bazel run //path/to:my_module_generate_docs
```

This runs terraform-docs and updates README.md in place.

## Configuration

Provide a custom `.terraform-docs.yml` to control output format:

```starlark
tf_module(
    name = "my_module",
    srcs = glob(["*.tf"]) + ["README.md"],
    tfdoc_config = ".terraform-docs.yml",
)
```

Without a config file, terraform-docs uses its defaults.

## See Also

- [Linting](linting.md) - TFLint checks
- [Validation](validation.md) - terraform validate
