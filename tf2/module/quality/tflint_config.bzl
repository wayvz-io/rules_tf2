"""TFLint configuration generation rules"""

load(
    "//tf2/module/quality:tflint_defaults.bzl",
    "get_base_rules",
    "get_provider_rules",
    "get_tagged_overrides",
    "merge_rule_configs",
)
load("//tf2/tools/runners:tool_paths.bzl", "TOOLS_ATTR", "get_tflint_plugin_path")

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

def _generate_plugin_block(plugin_name, plugin_version, plugin_path):
    """Generate a TFLint plugin block

    Args:
        plugin_name: Name of the plugin
        plugin_version: Version of the plugin
        plugin_path: Path to the plugin binary

    Returns:
        String containing the plugin block
    """
    return '''plugin "{plugin_name}" {{
  enabled = true
  version = "{plugin_version}"
  source = "file://{plugin_path}"
}}'''.format(
        plugin_name = plugin_name,
        plugin_version = plugin_version,
        plugin_path = plugin_path,
    )

def _generate_rule_block(rule_name, rule_config):
    """Generate a TFLint rule block

    Args:
        rule_name: Name of the rule
        rule_config: Configuration dictionary for the rule

    Returns:
        String containing the rule block
    """
    lines = ['rule "{}" {{'.format(rule_name)]

    for key, value in rule_config.items():
        if type(value) == "bool":
            lines.append("  {} = {}".format(key, "true" if value else "false"))
        elif type(value) == "string":
            lines.append('  {} = "{}"'.format(key, value))
        elif type(value) == "list":
            # Handle arrays like tags
            formatted_items = ['"{}"'.format(item) for item in value]
            lines.append("  {} = [{}]".format(key, ", ".join(formatted_items)))
        else:
            lines.append("  {} = {}".format(key, value))

    lines.append("}")
    return "\n".join(lines)

def _tf_generate_tflint_config_impl(ctx):
    """Implementation of tf_generate_tflint_config rule"""

    output_file = ctx.actions.declare_file(ctx.label.name + ".hcl")

    # Get provider list from providers attribute
    providers = [str(p.label) for p in ctx.attr.providers]

    # Detect which plugins are needed
    needed_plugins = _detect_provider_plugins(providers)

    # Get tflint config from versions.json if provided
    if ctx.attr.versions_file:
        # For now, use default config - will be enhanced to read from versions.json
        global_config = {
            "format": "compact",
            "force": False,
            "disabled_by_default": False,
        }
    else:
        global_config = {
            "format": "compact",
            "force": False,
            "disabled_by_default": False,
        }

    # Build the configuration content
    config_lines = []

    # Add global config block
    config_lines.append("config {")
    for key, value in global_config.items():
        if type(value) == "bool":
            config_lines.append("  {} = {}".format(key, "true" if value else "false"))
        elif type(value) == "string":
            config_lines.append('  {} = "{}"'.format(key, value))
        else:
            config_lines.append("  {} = {}".format(key, value))
    config_lines.append("}")
    config_lines.append("")

    # Start with base Terraform rules
    merged_rules = get_base_rules()

    # Add provider-specific rules for detected plugins
    for plugin_name in needed_plugins:
        provider_rules = get_provider_rules(plugin_name)
        merged_rules = merge_rule_configs(merged_rules, provider_rules)

    # Apply tagged overrides
    for tag in ctx.attr.module_tags:
        tag_overrides = get_tagged_overrides(tag)
        if tag_overrides:
            merged_rules = merge_rule_configs(merged_rules, tag_overrides)

    # Apply module-specific overrides
    if ctx.attr.rule_overrides:
        # Parse JSON strings in rule_overrides
        parsed_overrides = {}
        for rule_name, json_config in ctx.attr.rule_overrides.items():
            parsed_overrides[rule_name] = json.decode(json_config)
        merged_rules = merge_rule_configs(merged_rules, parsed_overrides)

    # Generate plugin blocks for needed plugins
    plugin_paths = {}
    for plugin_name in needed_plugins:
        plugin_path = get_tflint_plugin_path(ctx, plugin_name)
        if plugin_path:
            # Use default version for now - will be enhanced to read from versions.json
            plugin_version = "0.42.0" if plugin_name == "aws" else "0.29.0" if plugin_name == "azurerm" else "0.35.0"
            plugin_paths[plugin_name] = plugin_path
            config_lines.append(_generate_plugin_block(plugin_name, plugin_version, plugin_path))
            config_lines.append("")

    # Generate rule blocks
    for rule_name, rule_config in merged_rules.items():
        config_lines.append(_generate_rule_block(rule_name, rule_config))
        config_lines.append("")

    # Write the configuration file directly
    ctx.actions.write(
        output = output_file,
        content = "\n".join(config_lines),
    )

    # Include plugin binaries in runfiles if any were detected
    runfiles_files = [output_file]
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return [
        DefaultInfo(
            files = depset([output_file]),
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

tf_generate_tflint_config = rule(
    implementation = _tf_generate_tflint_config_impl,
    attrs = dict({
        "providers": attr.label_list(
            doc = "List of provider targets to analyze for plugin detection",
            mandatory = True,
        ),
        "versions_file": attr.label(
            allow_single_file = [".json"],
            doc = "Optional versions.json file to read configuration from",
        ),
        "module_tags": attr.string_list(
            doc = "Tags to apply tagged rule overrides",
            default = [],
        ),
        "rule_overrides": attr.string_dict(
            doc = "Module-specific rule overrides (JSON string format)",
            default = {},
        ),
    }, **TOOLS_ATTR),
    doc = "Generates TFLint configuration based on detected providers and rules",
)
