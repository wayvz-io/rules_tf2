# OPA (Open Policy Agent)

[Open Policy Agent](https://www.openpolicyagent.org/) (OPA) is a general-purpose
policy engine that evaluates policies written in the Rego language. rules_tf2
provides rules for testing Rego policies within Bazel, so you can validate
Terraform plans against your policies as part of your build.

## Rules

Three rules are available:

| Rule | Description |
|------|-------------|
| `tf_opa_test` | Run Rego policy tests with `opa test` |
| `tf_opa_fmt_test` | Check that Rego files are formatted |
| `tf_opa_fmt` | Fix formatting (run with `bazel run`) |

## Usage

```starlark
load("@rules_tf2//tf2:def.bzl", "tf_opa_test", "tf_opa_fmt_test", "tf_opa_fmt")

# Test the policy with OPA's built-in test framework
tf_opa_test(
    name = "require_tags_test",
    srcs = ["require_tags.rego", "require_tags_test.rego"],
)

# Check that Rego files are properly formatted
tf_opa_fmt_test(
    name = "format_test",
    srcs = ["require_tags.rego", "require_tags_test.rego"],
)

# Auto-format Rego files
tf_opa_fmt(
    name = "format",
    srcs = ["require_tags.rego", "require_tags_test.rego"],
)
```

## Test Structure

OPA tests follow the standard Rego convention:

- **Policy files** (`.rego`) - The policies to evaluate, usually declaring an
  `allow`/`deny` rule over a Terraform plan (`input.resource_changes`).
- **Test files** (`.rego`) - Rules prefixed with `test_` that assert policy
  behaviour using `with input as {...}` to supply mock plan data inline.
- **Data files** (`.json`) - Optional JSON supplied to `tf_opa_test` via the
  `data` attribute for policies that read from `data.*`.

`opa test` discovers every `test_*` rule in the supplied `srcs` and reports pass
or fail per test. A worked example lives at
[`examples/opa_policy/`](https://github.com/wayvz-io/rules_tf2/tree/main/examples/opa_policy),
which enforces required tags (`Environment`, `Owner`, `Project`) on taggable AWS
resources.

## Tool Download

The `opa` CLI is downloaded automatically when OPA rules are used. Configure the
version in `versions.json`:

```json
{
  "tools": {
    "opa": "1.4.2"
  }
}
```

## See Also

- [Sentinel](sentinel.md) - the HashiCorp Sentinel equivalent
- [`examples/opa_policy/`](https://github.com/wayvz-io/rules_tf2/tree/main/examples/opa_policy)
