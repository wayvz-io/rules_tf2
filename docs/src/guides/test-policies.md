# Test policies (OPA & Sentinel)

Run OPA (Rego) and Sentinel policy tests as hermetic Bazel tests, against the
configuration — before any plan reaches a backend.

## Prerequisites

- `opa` and/or `sentinel` versions set in `versions.json` (`tools` block).

## OPA (Rego)

1. Put the policy and its tests next to a `BUILD.bazel`. Test rules must be
   prefixed `test_`:

   ```
   opa_policy/
     require_tags.rego          # package terraform.tags
     require_tags_test.rego     # test_… rules
   ```

2. Declare `tf_opa_test` — `srcs` holds both the policy and test `.rego` files
   (add `data = [...]` for any `.json` the policy reads via `data.*`):

   ```starlark
   load("@rules_tf2//tf2:def.bzl", "tf_opa_test")

   tf_opa_test(
       name = "require_tags_test",
       srcs = glob(["*.rego"]),
       size = "small",
   )
   ```

3. Run it (`opa test` runs in an isolated work dir, offline):

   ```bash
   bazel test //path/to:require_tags_test
   ```

## Sentinel

1. Lay out the policy, test cases, and mocks:

   ```
   sentinel_policy/
     require_tags.sentinel
     test/require_tags/pass.hcl      # asserts rules { main = true }
     test/require_tags/fail.hcl
     mocks/mock-tfplan-pass.sentinel # user-provided mock data
   ```

2. Declare `tf_sentinel_test` — `srcs` is the policy, `tests` is the test cases
   plus mocks (both required; `config` for an optional `sentinel.hcl`):

   ```starlark
   load("@rules_tf2//tf2:def.bzl", "tf_sentinel_test")

   tf_sentinel_test(
       name = "require_tags_test",
       srcs = ["require_tags.sentinel"],
       tests = glob(["test/**/*.hcl"]) + glob(["mocks/*.sentinel"]),
   )
   ```

   The runner preserves the `test/` and `mocks/` directory structure, so the
   relative `source = "../../mocks/…"` paths in your `.hcl` resolve.

3. Run it:

   ```bash
   bazel test //path/to:require_tags_test
   ```

## Verification

Both are ordinary `bazel test` targets — they run offline and join the hermetic
suite. Sentinel mocks are user-provided (not generated from a real plan).

## See also

- [`tf_opa`](../reference/rules/tf-opa.md) · [`tf_sentinel`](../reference/rules/tf-sentinel.md)
- [OPA](../explanation/opa.md) · [Sentinel](../explanation/sentinel.md) — including the pre-plan vs post-plan policy layers
