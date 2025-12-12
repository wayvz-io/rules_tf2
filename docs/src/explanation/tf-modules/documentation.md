# Documentation

Each `tf_module` generates documentation targets using terraform-docs:

- `*_doc_test` - Verifies README.md matches terraform-docs output
- `*_generate_docs` - Regenerates README.md

## What terraform-docs Generates

terraform-docs extracts from your Terraform files:

- Module description (from header comment or `description` in main.tf)
- Input variables (names, types, defaults, descriptions)
- Output values (names, descriptions)
- Required providers

This is rendered into your README.md.

## doc_test

`*_doc_test` compares your README.md against what terraform-docs would generate. If they differ, the test fails.

This catches:
- New variables added without updating docs
- Outputs renamed without updating docs
- Description changes not reflected in README

## Regenerating Documentation

When the test fails, regenerate:

```bash
bazel run //path/to:my_module_generate_docs
```

This runs terraform-docs and updates README.md in place.

## Configuration

Provide a custom `.terraform-docs.yml` to control output format:

```starlark
tf_module(
    name = "my_module",
    srcs = [
        "main.tf",
        "outputs.tf",
        "README.md",
        "variables.tf",
    ],
    tfdoc_config = ".terraform-docs.yml",
)
```

Without a config file, terraform-docs uses its defaults.

## Including README in srcs

The README.md must be in `srcs` for the doc test to work:

```starlark
tf_module(
    srcs = [
        "main.tf",
        "outputs.tf",
        "README.md",
        "variables.tf",
    ],
)
```

If README.md isn't listed, the doc test can't compare against it.
