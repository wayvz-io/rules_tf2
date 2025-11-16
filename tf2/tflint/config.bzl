"""TFLint configuration generation for tf2 rules"""

load("//tf2/providers/core:info.bzl", "TfProviderConfigurationsInfo")
load(":defaults.bzl", "get_base_rules", "get_provider_rules", "get_tagged_overrides", "merge_rule_configs")

def _provider_name_from_label(provider_label):
    """Extract provider name from a provider label

    Args:
        provider_label: Provider label like "@tf_provider_registry//:aws_6"

    Returns:
        Provider name like "aws"
    """

    # Extract the provider name from labels like "@tf_provider_registry//:aws_6"
    if provider_label.startswith("@tf_provider_registry//"):
        provider_part = provider_label.split(":")[-1]  # Get "aws_6"

        # Remove version suffix to get provider name
        provider_name = "_".join(provider_part.split("_")[:-1])  # Remove last part (version)
        return provider_name

    # Handle other provider registries or formats
    return None

def _detect_provider_plugins(providers):
    """Detect which TFLint plugins are needed based on providers

    Args:
        providers: List of provider labels

    Returns:
        List of plugin names that should be enabled
    """
    plugins = []

    for provider in providers:
        provider_name = _provider_name_from_label(provider)
        if provider_name in ["aws", "azurerm", "google"]:
            plugins.append(provider_name)

    return plugins

def _generate_tflint_config_with_defaults(providers = None, module_tags = None, rule_overrides = None, versions_file = None):
    """Generate tflint configuration using the defaults system

    Args:
        providers: List of provider labels to detect plugins
        module_tags: List of tags to apply rule overrides (e.g., ["test_module"])
        rule_overrides: Dict of rule name to override config
        versions_file: Optional versions file for tf2 plugin

    Returns:
        String containing the tflint configuration
    """

    # Start with base rules
    rules = get_base_rules()

    # Add provider-specific rules if providers specified
    if providers:
        plugins = _detect_provider_plugins(providers)
        for plugin in plugins:
            provider_rules = get_provider_rules(plugin)
            if provider_rules:
                rules = merge_rule_configs(rules, provider_rules)

    # Apply tagged overrides if provided
    if module_tags:
        for tag in module_tags:
            tag_overrides = get_tagged_overrides(tag)
            if tag_overrides:
                rules = merge_rule_configs(rules, tag_overrides)

    # Apply manual rule overrides
    if rule_overrides:
        # Handle dotted keys like "rule_name.field" by expanding them
        expanded_overrides = {}
        for key, value in rule_overrides.items():
            if "." in key:
                rule_name, field = key.split(".", 1)
                if rule_name not in expanded_overrides:
                    expanded_overrides[rule_name] = {}

                # Convert string values to appropriate types
                if value == "true":
                    expanded_overrides[rule_name][field] = True
                elif value == "false":
                    expanded_overrides[rule_name][field] = False
                else:
                    expanded_overrides[rule_name][field] = value
            else:
                expanded_overrides[key] = value

        rules = merge_rule_configs(rules, expanded_overrides)

    # Build config content
    config_lines = []

    # Add global config
    config_lines.append("# Auto-generated tflint configuration for tf2")
    config_lines.append("")
    config_lines.append("config {")
    config_lines.append("  force = false")
    config_lines.append("}")
    config_lines.append("")

    # Add terraform plugin (always enabled for base Terraform rules)
    config_lines.append("# Terraform language rules plugin")
    config_lines.append("plugin \"terraform\" {")
    config_lines.append("  enabled = true")
    config_lines.append("}")
    config_lines.append("")

    # Add plugin configuration if we have providers
    if providers:
        plugins = _detect_provider_plugins(providers)
        for plugin in plugins:
            config_lines.append("plugin \"{}\" {{".format(plugin))
            config_lines.append("  enabled = true")
            config_lines.append("}")
            config_lines.append("")

    # Add TF2 plugin if versions file provided
    if versions_file:
        config_lines.append("# TF2 custom plugin")
        config_lines.append("plugin \"tf2\" {")
        config_lines.append("  enabled = true")
        config_lines.append("  version = \"0.1.0\"")
        config_lines.append("  source = \"local\"")
        config_lines.append("}")
        config_lines.append("")

    # Add rule blocks
    for rule_name, rule_config in rules.items():
        config_lines.append("rule \"{}\" {{".format(rule_name))
        for key, value in rule_config.items():
            if type(value) == "bool":
                config_lines.append("  {} = {}".format(key, "true" if value else "false"))
            elif type(value) == "string":
                config_lines.append("  {} = \"{}\"".format(key, value))
            else:
                config_lines.append("  {} = {}".format(key, value))
        config_lines.append("}")
        config_lines.append("")

    return "\n".join(config_lines)

def _tf_generate_tflint_config_impl(ctx):
    """Implementation of tf_generate_tflint_config rule"""

    # Get providers from the providers attribute
    providers = [str(provider.label) for provider in ctx.attr.providers] if ctx.attr.providers else None

    # Create .tflint.hcl configuration file
    tflint_config = ctx.actions.declare_file(ctx.label.name + ".hcl")

    # Get the generated versions file from provider_configurations if provided
    versions_file = None
    if ctx.attr.provider_configurations:
        provider_info = ctx.attr.provider_configurations[TfProviderConfigurationsInfo]
        if provider_info.versions_file:
            versions_file = provider_info.versions_file

    # Generate configuration content using defaults system
    config_content = _generate_tflint_config_with_defaults(
        providers = providers,
        module_tags = ctx.attr.module_tags,
        rule_overrides = ctx.attr.rule_overrides,
        versions_file = versions_file,
    )

    ctx.actions.write(
        output = tflint_config,
        content = config_content,
    )

    # Create tf2_versions.json file if versions file provided
    outputs = [tflint_config]
    if versions_file:
        tf2_versions_file = ctx.actions.declare_file(ctx.label.name + "_tf2_versions.json")
        ctx.actions.symlink(
            output = tf2_versions_file,
            target_file = versions_file,
        )
        outputs.append(tf2_versions_file)

    return [
        DefaultInfo(
            files = depset(outputs),
        ),
    ]

tf_generate_tflint_config = rule(
    implementation = _tf_generate_tflint_config_impl,
    attrs = {
        "providers": attr.label_list(
            doc = "List of provider labels to detect plugins",
        ),
        "provider_configurations": attr.label(
            doc = "Provider configurations to include in config (optional)",
            providers = [TfProviderConfigurationsInfo],
        ),
        "module_tags": attr.string_list(
            doc = "Tags for applying tagged rule configurations",
            default = [],
        ),
        "rule_overrides": attr.string_dict(
            doc = "Manual rule overrides",
            default = {},
        ),
        "versions_file": attr.label(
            allow_single_file = [".json"],
            doc = "versions.json file for tool and plugin configuration",
        ),
    },
    doc = "Generates a TFLint configuration file for tf2 validation with defaults system",
)
