"""Utilities for accessing downloaded tool binaries

This module provides centralized tool path resolution for the tf2 module.
It handles both main repository and external repository contexts automatically.

Public functions:
- get_terraform_path(ctx): Get path to terraform binary
- get_tflint_path(ctx): Get path to tflint binary
- get_terraform_docs_path(ctx): Get path to terraform-docs binary
- get_sentinel_path(ctx): Get path to sentinel binary
- get_stacksplugin_path(ctx): Get path to stacksplugin binary
- get_opa_path(ctx): Get path to opa binary
- get_tflint_plugin_path(ctx, plugin_name): Get path to TFLint plugin binary
"""

# Tool configuration for path resolution
# Note: Exported as TOOL_CONFIGS for testing purposes
_TOOL_CONFIGS = {
    "terraform": {
        "binary_name": "terraform",
        "repo_name": "terraform_tool",
    },
    "tflint": {
        "binary_name": "tflint",
        "repo_name": "tflint_tool",
    },
    "terraform-docs": {
        "binary_name": "terraform-docs",
        "repo_name": "terraform_docs_tool",
    },
    "sentinel": {
        "binary_name": "sentinel",
        "repo_name": "sentinel_tool",
    },
    "stacksplugin": {
        "binary_name": "tfstacks",
        "repo_name": "stacksplugin_tool",
    },
    "opa": {
        "binary_name": "opa",
        "repo_name": "opa_tool",
    },
}

# Plugin configuration for path resolution
# Note: Exported as PLUGIN_CONFIGS for testing purposes
_PLUGIN_CONFIGS = {
    "aws": {
        "binary_name": "tflint-ruleset-aws",
        "repo_name": "tflint_plugin_aws",
    },
    "azurerm": {
        "binary_name": "tflint-ruleset-azurerm",
        "repo_name": "tflint_plugin_azurerm",
    },
    "google": {
        "binary_name": "tflint-ruleset-google",
        "repo_name": "tflint_plugin_google",
    },
    "opa": {
        "binary_name": "tflint-ruleset-opa",
        "repo_name": "tflint_plugin_opa",
    },
}

def _is_external_repository(ctx):
    """Check if we're running in an external repository context.

    Args:
        ctx: Rule context

    Returns:
        Boolean: True if external repository, False if main repository
    """
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        for tool_file in ctx.files._tools:
            # Check for external repository patterns (both old and new bzlmod naming)
            if "rules_tf2~~tf_tools~" in tool_file.short_path or "rules_tf2++tf_tools+" in tool_file.short_path:
                return True
    return False

def get_tool_path(ctx, tool_name):
    """Get the runfiles path to a downloaded tool binary.

    Args:
        ctx: Rule context
        tool_name: Name of the tool (terraform, tflint, terraform-docs)

    Returns:
        String path to the tool binary in runfiles
    """
    if tool_name not in _TOOL_CONFIGS:
        fail("Unknown tool: {}. Supported tools: {}".format(
            tool_name,
            ", ".join(_TOOL_CONFIGS.keys()),
        ))

    config = _TOOL_CONFIGS[tool_name]
    repo_name = config["repo_name"]
    binary_name = config["binary_name"]

    # Determine repository prefix based on context
    if _is_external_repository(ctx):
        # External repository - tools are under rules_tf2++ prefix (new bzlmod naming)
        repo_path = "rules_tf2++tf_tools+{}".format(repo_name)
    else:
        # Main repository - tools are under + prefix (new bzlmod naming)
        repo_path = "+tf_tools+{}".format(repo_name)

    return "$RUNFILES/{}/{}".format(repo_path, binary_name)

def get_terraform_path(ctx):
    """Get the path to the terraform binary."""
    return get_tool_path(ctx, "terraform")

def get_tflint_path(ctx):
    """Get the path to the tflint binary."""
    return get_tool_path(ctx, "tflint")

def get_terraform_docs_path(ctx):
    """Get the path to the terraform-docs binary."""
    return get_tool_path(ctx, "terraform-docs")

def get_sentinel_path(ctx):
    """Get the path to the sentinel binary."""
    return get_tool_path(ctx, "sentinel")

def get_stacksplugin_path(ctx):
    """Get the path to the stacksplugin (tfstacks) binary."""
    return get_tool_path(ctx, "stacksplugin")

def get_opa_path(ctx):
    """Get the path to the opa binary."""
    return get_tool_path(ctx, "opa")

def get_tflint_plugin_path(ctx, plugin_name):
    """Get the runfiles path to a TFLint plugin binary.

    Args:
        ctx: Rule context
        plugin_name: Name of the plugin (aws, azurerm, google, opa)

    Returns:
        String path to the plugin binary in runfiles or None if not available
    """
    if plugin_name not in _PLUGIN_CONFIGS:
        return None  # Plugin not available

    config = _PLUGIN_CONFIGS[plugin_name]
    repo_name = config["repo_name"]
    binary_name = config["binary_name"]

    # Determine repository prefix based on context
    if _is_external_repository(ctx):
        # External repository - plugins are under rules_tf2++ prefix (new bzlmod naming)
        repo_path = "rules_tf2++tf_tools+{}".format(repo_name)
    else:
        # Main repository - plugins are under + prefix (new bzlmod naming)
        repo_path = "+tf_tools+{}".format(repo_name)

    return "$RUNFILES/{}/{}".format(repo_path, binary_name)

# Common tools attribute for rules that need access to tools
TOOLS_ATTR = {
    "_tools": attr.label_list(
        default = [
            "@tf_tool_registry//:terraform_bin",
            "@tf_tool_registry//:tflint_bin",
            "@tf_tool_registry//:terraform_docs_bin",
            "@tf_tool_registry//:sentinel_bin",
            "@tf_tool_registry//:stacksplugin_bin",
            "@tf_tool_registry//:opa_bin",
            "@tflint_plugin_registry//:aws",
            "@tflint_plugin_registry//:azurerm",
            "@tflint_plugin_registry//:google",
            "@tflint_plugin_registry//:opa",
        ],
        allow_files = True,
        doc = "Tool binaries and TFLint plugins",
    ),
}
