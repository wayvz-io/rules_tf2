# How-to Guides

Task-oriented instructions for accomplishing specific goals.

> **Note**: This project is published as-is and is not actively maintained.
> A curated set of how-to guides has not been written. This page collects the
> most relevant reference and explanation pages for common tasks until then.

## Common tasks

| Goal | Where to look |
|------|---------------|
| Create a module with automatic tests | [`tf_module`](../reference/rules/tf-module.md), [Module Structure](../explanation/tf-modules/structure.md) |
| Configure providers and lock files | [Provider Versioning](../explanation/versioning/providers.md) |
| Use external modules | [External Modules](../explanation/versioning/external-modules.md), [Module Registry](../explanation/tf-modules/module-registry.md) |
| Run Terraform commands via Bazel | [`tf_runner`](../reference/rules/tf-runner.md) |
| Run native Terraform tests | [`tf_test`](../reference/rules/tf-test.md) |
| Test policies (Sentinel / OPA) | [Sentinel](../explanation/sentinel.md), [OPA](../explanation/opa.md) |
| Publish to a registry or OCI | [`tf_publish_registry`](../reference/publishing/tf-publish-registry.md), [`tf_publish_oci`](../reference/publishing/tf-publish-oci.md) |
| Integrate with Terraform Cloud | [`tf_cloud_workspace`](../reference/cloud/tf-cloud-workspace.md), [`tfc_agent_image`](../reference/cloud/tfc-agent-image.md) |
| Customize TFLint rules | [Linting](../explanation/tf-modules/linting.md) |
| Generate documentation | [Documentation](../explanation/tf-modules/documentation.md) |

## Runnable examples

For copy-and-run configurations, see the
[`examples/`](https://github.com/wayvz-io/rules_tf2/tree/main/examples) directory.
