# Sentinel

Sentinel is HashiCorp's policy-as-code framework. rules_tf2 provides rules for testing Sentinel policies within Bazel.

## Rules

Three rules are available:

| Rule | Description |
|------|-------------|
| `tf_sentinel_test` | Run sentinel tests with mock data |
| `tf_sentinel_fmt_test` | Check policy file formatting |
| `tf_sentinel_fmt` | Fix formatting |

## Usage

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_sentinel_test", "tf_sentinel_fmt_test", "tf_sentinel_fmt")

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

tf_sentinel_fmt_test(
    name = "format_test",
    srcs = ["require_tags.sentinel"],
)

tf_sentinel_fmt(
    name = "format",
    srcs = ["require_tags.sentinel"],
)
```

## Test Structure

Sentinel tests require:

- **Policy files** (`.sentinel`) - The policies to test
- **Test files** (`test/**/*.hcl`) - Test cases with pass/fail expectations
- **Mock data** (`mocks/*.sentinel`) - Mock Terraform plan data

```
policies/
├── require_tags.sentinel
├── test/
│   └── require_tags/
│       ├── pass.hcl
│       └── fail.hcl
└── mocks/
    ├── mock-tfplan-pass.sentinel
    └── mock-tfplan-fail.sentinel
```

## Tool Download

The sentinel CLI is downloaded automatically when sentinel rules are used. Configure the version in `versions.json`:

```json
{
  "tools": {
    "sentinel": "0.26.0"
  }
}
```

## See Also

- [tf_sentinel_test Reference](../reference/rules/tf-sentinel.md)
