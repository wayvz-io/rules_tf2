"""Utilities for parsing and working with versions.json files"""

def _parse_versions_json(repository_ctx, versions_file):
    """Parse a versions.json file and return its contents

    Args:
        repository_ctx: The repository context
        versions_file: Path to the versions.json file

    Returns:
        Dictionary containing parsed versions.json content
    """
    versions_content = repository_ctx.read(versions_file)
    versions_data = json.decode(versions_content)

    # Validate the schema - providers is required
    if "providers" not in versions_data:
        fail("versions.json must contain a 'providers' section")

    # Set defaults for optional sections
    versions_data.setdefault("tools", {})
    versions_data.setdefault("tflint_plugins", {})
    versions_data.setdefault("tflint_config", {})

    return versions_data

def _get_tool_version(versions_data, tool_name, default_version = None):
    """Get tool version from versions.json

    Args:
        versions_data: Parsed versions.json data
        tool_name: Name of the tool
        default_version: Default version if not found

    Returns:
        Tool version string or default_version if not found
    """
    return versions_data.get("tools", {}).get(tool_name, default_version)

def _get_tflint_plugin_version(versions_data, plugin_name):
    """Get TFLint plugin version from versions.json

    Args:
        versions_data: Parsed versions.json data
        plugin_name: Name of the plugin

    Returns:
        Plugin version string or None if not found
    """
    return versions_data.get("tflint_plugins", {}).get(plugin_name)

def _get_tflint_config(versions_data):
    """Get TFLint configuration from versions.json

    Args:
        versions_data: Parsed versions.json data

    Returns:
        Dictionary containing TFLint configuration
    """
    config = versions_data.get("tflint_config", {})

    # Set defaults for global section
    global_defaults = {
        "format": "compact",
        "force": False,
        "disabled_by_default": False,
    }
    global_config = config.get("global", {})
    for key, default_value in global_defaults.items():
        global_config.setdefault(key, default_value)
    config["global"] = global_config

    # Set defaults for missing sections
    config.setdefault("rules", {})
    config.setdefault("tagged_overrides", {})

    return config

def _get_providers(versions_data):
    """Get providers from versions.json

    Args:
        versions_data: Parsed versions.json data

    Returns:
        Dictionary containing provider versions
    """
    return versions_data.get("providers", {})

# Export functions for use by other modules
parse_versions_json = _parse_versions_json
get_tool_version = _get_tool_version
get_tflint_plugin_version = _get_tflint_plugin_version
get_tflint_config = _get_tflint_config
get_providers = _get_providers
