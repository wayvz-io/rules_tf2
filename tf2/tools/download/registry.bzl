"""Tool and plugin registry repository rules"""

def _tool_registry_impl(repository_ctx):
    """Implementation of tool registry repository rule.

    This rule creates aliases to the individual tool repositories.
    The actual tool downloading is handled by the module extension.

    Args:
        repository_ctx: Repository rule context
    """

    # Create registry BUILD file with aliases
    build_content = '''package(default_visibility = ["//visibility:public"])

alias(
    name = "terraform",
    actual = "@terraform_tool//:bin",
)

alias(
    name = "tflint",
    actual = "@tflint_tool//:bin",
)

alias(
    name = "terraform-docs",
    actual = "@terraform_docs_tool//:bin",
)

# Export tool binaries for direct access
alias(
    name = "terraform_bin",
    actual = "@terraform_tool//:bin",
)

alias(
    name = "tflint_bin",
    actual = "@tflint_tool//:bin",
)

alias(
    name = "terraform_docs_bin",
    actual = "@terraform_docs_tool//:bin",
)

alias(
    name = "stacksplugin",
    actual = "@stacksplugin_tool//:bin",
)

alias(
    name = "stacksplugin_bin",
    actual = "@stacksplugin_tool//:bin",
)

# Filegroup to include all tools
filegroup(
    name = "all",
    srcs = [
        "@terraform_tool//:bin",
        "@tflint_tool//:bin",
        "@terraform_docs_tool//:bin",
        "@stacksplugin_tool//:bin",
    ],
)
'''

    repository_ctx.file("BUILD.bazel", build_content)

tool_registry = repository_rule(
    implementation = _tool_registry_impl,
    attrs = {},
    doc = "Creates a registry of downloaded tools with aliases",
)

def _tflint_plugin_registry_impl(repository_ctx):
    """Implementation of TFLint plugin registry repository rule.

    Args:
        repository_ctx: Repository rule context
    """
    plugins = repository_ctx.attr.plugins
    local_plugins = repository_ctx.attr.local_plugins

    # All known plugins that might be referenced
    all_known_plugins = ["aws", "azurerm", "google", "opa", "terraform"]

    # Track which plugins are actually available
    available_plugins = {p: True for p in plugins}
    available_plugins.update({p: True for p in local_plugins.keys()})

    # Build aliases for each plugin
    plugin_aliases = ""
    plugin_filegroup_srcs = []

    # Handle downloaded plugins
    # Map plugin names to their binary file names
    plugin_binary_names = {
        "aws": "tflint-ruleset-aws",
        "azurerm": "tflint-ruleset-azurerm",
        "google": "tflint-ruleset-google",
        "opa": "tflint-ruleset-opa",
        "terraform": "tflint-ruleset-terraform",
    }
    for plugin_name in plugins:
        repo_name = "tflint_plugin_{}".format(plugin_name)
        binary_name = plugin_binary_names.get(plugin_name, "tflint-ruleset-{}".format(plugin_name))
        # Point to the actual binary file, not the sh_binary wrapper
        plugin_aliases += '''
alias(
    name = "{plugin_name}",
    actual = "@{repo_name}//:{binary_name}",
)

alias(
    name = "{plugin_name}_bin",
    actual = "@{repo_name}//:{binary_name}",
)
'''.format(plugin_name = plugin_name, repo_name = repo_name, binary_name = binary_name)
        plugin_filegroup_srcs.append('"@{}//:{}"'.format(repo_name, binary_name))

    # Handle local (built-from-source) plugins
    for plugin_name, plugin_target in local_plugins.items():
        plugin_aliases += '''
alias(
    name = "{plugin_name}",
    actual = "{plugin_target}",
)

alias(
    name = "{plugin_name}_bin",
    actual = "{plugin_target}",
)
'''.format(plugin_name = plugin_name, plugin_target = plugin_target)
        plugin_filegroup_srcs.append('"{}"'.format(plugin_target))

    # Create empty filegroups for plugins that aren't available
    # This allows rules to reference these targets without failing at analysis time
    # The rule implementation can check if the filegroup is empty
    empty_plugin_filegroups = ""
    for plugin_name in all_known_plugins:
        if plugin_name not in available_plugins.keys():
            empty_plugin_filegroups += '''
# Placeholder for {plugin_name} plugin (not configured)
filegroup(
    name = "{plugin_name}",
    srcs = [],
)

filegroup(
    name = "{plugin_name}_bin",
    srcs = [],
)
'''.format(plugin_name = plugin_name)

    # Create registry BUILD file with aliases
    build_content = '''package(default_visibility = ["//visibility:public"])

{plugin_aliases}
{empty_plugin_filegroups}

# Filegroup to include all plugins
filegroup(
    name = "all_plugins",
    srcs = [
        {plugin_srcs}
    ],
)
'''.format(
        plugin_aliases = plugin_aliases,
        empty_plugin_filegroups = empty_plugin_filegroups,
        plugin_srcs = ",\n        ".join(plugin_filegroup_srcs) if plugin_filegroup_srcs else "",
    )

    repository_ctx.file("BUILD.bazel", build_content)

tflint_plugin_registry = repository_rule(
    implementation = _tflint_plugin_registry_impl,
    attrs = {
        "plugins": attr.string_list(
            doc = "List of downloaded plugin names to register",
            default = [],
        ),
        "local_plugins": attr.string_dict(
            doc = "Dictionary of local plugin names to build targets (e.g., {'tf2': '//go/tflint_ruleset:tflint-ruleset-tf2'})",
            default = {},
        ),
    },
    doc = "Creates a registry of TFLint plugins (both downloaded and local) with aliases",
)
