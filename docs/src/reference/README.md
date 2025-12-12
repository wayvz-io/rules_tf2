# Reference

Technical descriptions of rules, macros, and APIs.

Reference documentation provides authoritative, factual information about rules_tf2 components. Use this section when you need to look up specific parameters, return values, or usage patterns.

## Contents

### [Rules](rules/README.md)

Core Bazel rules for Terraform modules:

- [tf_module](rules/tf-module.md) - Main macro for creating Terraform modules with testing
- [tf_runner](rules/tf-runner.md) - Run arbitrary Terraform commands
- [tf_test](rules/tf-test.md) - Run Terraform native tests
- [tf_variables](rules/tf-variables.md) - Collect variable files for runners
- [tf_file_export](rules/tf-file-export.md) - Export modules to filesystem

### [Cloud Integration](cloud/README.md)

Terraform Cloud and Enterprise integration:

- [tf_cloud_workspace](cloud/tf-cloud-workspace.md) - Create TFC runner targets

### [Providers](providers/README.md)

Provider management:

- [provider_mirror](providers/provider-mirror.md) - Create provider filesystem mirrors

### [Publishing](publishing/README.md)

Module publishing:

- [tf_publish_registry](publishing/tf-publish-registry.md) - Publish to Terraform Registry
- [tf_publish_oci](publishing/tf-publish-oci.md) - Push to OCI registries

### [Module Extensions](extensions/README.md)

Bazel module extensions for MODULE.bazel:

- [tf_providers](extensions/tf-providers.md) - Provider download and management
- [tf_tools](extensions/tf-tools.md) - Tool download (terraform, tflint, terraform-docs)
