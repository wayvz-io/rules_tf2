"""TFLint configuration generator for tf2 rules"""

load("//tf2/core/rules:info.bzl", "TfProviderConfigurationsInfo")

def _tf_tflint_config_impl(ctx):
    """Implementation of tf_tflint_config rule"""

    # Get the generated versions file from provider_configurations if provided
    versions_file = None
    expected_versions = ""
    if ctx.attr.provider_configurations:
        provider_info = ctx.attr.provider_configurations[TfProviderConfigurationsInfo]
        if provider_info.versions_file:
            versions_file = provider_info.versions_file

    # Create .tflint.hcl configuration file
    tflint_config = ctx.actions.declare_file(ctx.label.name + ".hcl")

    # Create tf2_versions.json file for the plugin to read
    tf2_versions_file = None
    if versions_file:
        tf2_versions_file = ctx.actions.declare_file(ctx.label.name + "_tf2_versions.json")
        ctx.actions.symlink(
            output = tf2_versions_file,
            target_file = versions_file,
        )

    # Build configuration content
    config_content = """# Auto-generated tflint configuration for tf2 validation

config {
  module = true
  force = false
}

# Standard terraform rules
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}

# File organization rules
rule "terraform_naming_convention" {
  enabled = true
  format = "snake_case"
}
"""

    # Add plugin configuration if we have a custom plugin
    if ctx.attr.use_tf2_plugin:
        config_content += """
# TF2 custom plugin (when available)
plugin "tf2" {
  enabled = true
  version = "0.1.0"
  source = "local"
}
"""

    ctx.actions.write(
        output = tflint_config,
        content = config_content,
    )

    outputs = [tflint_config]
    if tf2_versions_file:
        outputs.append(tf2_versions_file)

    return [
        DefaultInfo(
            files = depset(outputs),
        ),
    ]

tf_tflint_config = rule(
    implementation = _tf_tflint_config_impl,
    attrs = {
        "provider_configurations": attr.label(
            doc = "Provider configurations to include in config (optional)",
            providers = [TfProviderConfigurationsInfo],
        ),
        "use_tf2_plugin": attr.bool(
            doc = "Whether to enable tf2 custom plugin",
            default = False,
        ),
    },
    doc = "Generates a TFLint configuration file for tf2 validation",
)