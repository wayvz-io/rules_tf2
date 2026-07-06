# How-to Guides

Task-oriented recipes for common goals. Each assumes you know what you want to
do; for the concepts behind them, follow the links into
[Explanation](../explanation/architecture.md) and
[Reference](../reference/rules/).

## Modules & testing

- [Create and test a module](create-and-test-a-module.md) — declare a `tf_module` and run the generated suite
- [Write native Terraform tests](write-native-tests.md) — add `.tftest.hcl` tests with `tf_test`
- [Test policies (OPA & Sentinel)](test-policies.md) — `tf_opa_test` / `tf_sentinel_test`

## Providers & dependencies

- [Add or update a provider](add-a-provider.md) — `versions.json`, lockfile sync, and automation
- [Use an external module](use-an-external-module.md) — registry & Git modules
- [Generate BUILD files with Gazelle](generate-build-files.md) — auto-generate `tf_module` targets

## Running & shipping

- [Run Terraform through Bazel](run-terraform.md) — `tf_runner` for plan/apply
- [Run against Terraform Cloud](terraform-cloud.md) — `tfc_workspace` and provider-baked agent images
- [Publish a module](publish-a-module.md) — TFC private registry or a Flux OCI artifact

## Runnable examples

For copy-and-run configurations, see the
[`examples/`](https://github.com/wayvz-io/rules_tf2/tree/main/examples) directory.
