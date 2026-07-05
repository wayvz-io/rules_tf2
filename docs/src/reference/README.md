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
- [tf_sentinel](rules/tf-sentinel.md) - Test and format Sentinel policies
- [tf_opa](rules/tf-opa.md) - Test and format OPA (Rego) policies

### [Cloud Integration](cloud/README.md)

Terraform Cloud and Enterprise integration:

- [tfc_workspace](cloud/tfc-workspace.md) - Create TFC/TFE runner targets
- [tfc_publish_registry](cloud/tfc-publish-registry.md) - Publish to the TFC/TFE private registry
- [tfc_agent_image](cloud/tfc-agent-image.md) - Build TFC agent images with providers baked in

### [Flux (GitOps)](flux/README.md)

Publish modules as OCI artifacts for Flux:

- [tf_publish_oci_flux](flux/tf-publish-oci-flux.md) - Push a module as a Flux-compatible OCI artifact

### [Providers](providers/README.md)

Provider management:

- [provider_mirror](providers/provider-mirror.md) - Create provider filesystem mirrors

### [Module Extensions](extensions/README.md)

Bazel module extensions for MODULE.bazel:

- [Module Extensions](extensions/README.md) - `tf_providers` (provider download and
  management), `tf_tools` (terraform, tflint, terraform-docs), and related extensions
