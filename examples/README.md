# Terraform Bazel Rules Examples

This directory contains clean, well-documented examples of using the tf2 Bazel rules for Terraform.

## Examples

### 1. Basic Module (`basic_module/`)
A simple Terraform module demonstrating:
- Basic `tf_module` usage
- Provider configuration
- Standard Terraform resources
- Testing and validation

### 2. Module with Dependencies (`module_with_dependencies/`)
A more complex example showing:
- Using other modules as dependencies
- Nested module composition
- Provider inheritance
- Module outputs and variables

## Running Examples

```bash
# Run all tests for an example
bazel test //examples/basic_module:all

# Validate the module
bazel test //examples/basic_module:basic_module_validate_test

# Generate documentation
bazel run //examples/basic_module:basic_module_generate_docs

# Format the code
bazel run //examples/basic_module:basic_module_format
```

## Key Concepts

### tf_module Rule
The `tf_module` rule is the core building block for Terraform modules in Bazel:

```starlark
tf_module(
    name = "my_module",
    providers = [...],     # Required provider mirrors
    modules = [...],       # Optional module dependencies
    tflint_config = ...,   # Optional linting configuration
    tfdoc_config = ...,    # Optional documentation configuration
)
```

### Provider Management
Providers are managed centrally through the MODULE.bazel file and referenced as:
```starlark
providers = [
    "@tf_provider_registry//:aws_6",
    "@tf_provider_registry//:azurerm_4",
]
```

### Testing
Each module automatically generates several test targets:
- `*_validate_test` - Terraform validation
- `*_format_test` - Code formatting check
- `*_lint_test` - Linting with TFLint
- `*_doc_test` - Documentation validation
- `*_versions_check_test` - Provider version consistency

## Best Practices

1. **Keep modules focused** - Each module should have a single, well-defined purpose
2. **Use semantic versioning** - Pin provider versions appropriately
3. **Document thoroughly** - Use terraform-docs for automatic documentation
4. **Test everything** - Leverage the automatic test generation
5. **Follow conventions** - Use standard file organization (main.tf, variables.tf, outputs.tf)

## More Information

For more examples and edge cases, see the integration tests in `//tf2/tests/integration/`.