# tf_opa

Rules for testing Open Policy Agent (OPA) policies written in Rego.

## tf_opa_test

Tests Rego policies using the `opa test` framework. Test rules are declared in
`.rego` files with names prefixed by `test_`.

```starlark
tf_opa_test(
    name = "require_tags_test",
    srcs = [
        "require_tags.rego",
        "require_tags_test.rego",
    ],
)
```

### Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | yes | Target name |
| `srcs` | label_list | yes | Rego policy and test files (`.rego`); tests have rules prefixed with `test_` |
| `data` | label_list | no | Optional JSON data files (`.json`) supplied to policies that read from `data.*` |

## tf_opa_fmt_test

Tests that Rego policy files are properly formatted.

```starlark
tf_opa_fmt_test(
    name = "format_test",
    srcs = ["require_tags.rego"],
)
```

### Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | yes | Target name |
| `srcs` | label_list | yes | Rego policy files to check (`.rego`) |

## tf_opa_fmt

Formats Rego policy files. Run with `bazel run`.

```starlark
tf_opa_fmt(
    name = "format",
    srcs = ["require_tags.rego"],
)
```

### Attributes

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string | yes | Target name |
| `srcs` | label_list | yes | Rego policy files to format (`.rego`) |

## Example

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_opa_test", "tf_opa_fmt_test", "tf_opa_fmt")

# Test policies with OPA's built-in test framework
tf_opa_test(
    name = "require_tags_test",
    srcs = [
        "require_tags.rego",
        "require_tags_test.rego",
    ],
)

# Check formatting
tf_opa_fmt_test(
    name = "format_test",
    srcs = [
        "require_tags.rego",
        "require_tags_test.rego",
    ],
)

# Fix formatting
tf_opa_fmt(
    name = "format",
    srcs = [
        "require_tags.rego",
        "require_tags_test.rego",
    ],
)
```

## Running Tests

```bash
# Run OPA policy tests
bazel test //path/to:require_tags_test

# Check formatting
bazel test //path/to:format_test

# Fix formatting
bazel run //path/to:format
```

## See Also

- [OPA Explanation](../../explanation/opa.md)
