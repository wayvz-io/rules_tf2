# tf_sentinel

Rules for testing Sentinel policies.

## tf_sentinel_test

Tests Sentinel policies using the sentinel test framework with user-provided mocks.

```starlark
tf_sentinel_test(
    name = "require_tags_test",
    srcs = ["require_tags.sentinel"],
    tests = [
        "test/require_tags/pass.hcl",
        "test/require_tags/fail.hcl",
        "mocks/mock-tfplan-pass.sentinel",
        "mocks/mock-tfplan-fail.sentinel",
    ],
)
```

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | string | Target name |
| `srcs` | label_list | Sentinel policy files (`.sentinel`) |
| `tests` | label_list | Test files and mock data (`test/**/*.hcl`, `mocks/*.sentinel`) |
| `config` | label | Optional sentinel configuration file (`sentinel.hcl`) |

## tf_sentinel_fmt_test

Tests that Sentinel policy files are properly formatted.

```starlark
tf_sentinel_fmt_test(
    name = "format_test",
    srcs = ["require_tags.sentinel"],
)
```

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | string | Target name |
| `srcs` | label_list | Sentinel policy files to check (`.sentinel`) |

## tf_sentinel_fmt

Formats Sentinel policy files. Run with `bazel run`.

```starlark
tf_sentinel_fmt(
    name = "format",
    srcs = ["require_tags.sentinel"],
)
```

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | string | Target name |
| `srcs` | label_list | Sentinel policy files to format (`.sentinel`) |

## Example

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_sentinel_test", "tf_sentinel_fmt_test", "tf_sentinel_fmt")

# Test policies
tf_sentinel_test(
    name = "policy_tests",
    srcs = [
        "require_tags.sentinel",
        "restrict_instance_types.sentinel",
    ],
    tests = [
        "test/require_tags/pass.hcl",
        "test/require_tags/fail.hcl",
        "test/restrict_instance_types/pass.hcl",
        "mocks/mock-tfplan.sentinel",
    ],
)

# Check formatting
tf_sentinel_fmt_test(
    name = "format_test",
    srcs = [
        "require_tags.sentinel",
        "restrict_instance_types.sentinel",
    ],
)

# Fix formatting
tf_sentinel_fmt(
    name = "format",
    srcs = [
        "require_tags.sentinel",
        "restrict_instance_types.sentinel",
    ],
)
```

## Running Tests

```bash
# Run sentinel tests
bazel test //path/to:policy_tests

# Check formatting
bazel test //path/to:format_test

# Fix formatting
bazel run //path/to:format
```

## See Also

- [Sentinel Explanation](../../explanation/sentinel.md)
