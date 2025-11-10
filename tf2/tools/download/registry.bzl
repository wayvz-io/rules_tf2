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

# Filegroup to include all tools
filegroup(
    name = "all",
    srcs = [
        "@terraform_tool//:bin",
        "@tflint_tool//:bin",
        "@terraform_docs_tool//:bin",
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

    # Build aliases for each plugin
    plugin_aliases = ""
    plugin_filegroup_srcs = []

    for plugin_name in plugins:
        repo_name = "tflint_plugin_{}".format(plugin_name)
        plugin_aliases += '''
alias(
    name = "{plugin_name}",
    actual = "@{repo_name}//:bin",
)

alias(
    name = "{plugin_name}_bin",
    actual = "@{repo_name}//:bin",
)
'''.format(plugin_name = plugin_name, repo_name = repo_name)
        plugin_filegroup_srcs.append('"@{}//:{}"'.format(repo_name, plugin_name))

    # Create registry BUILD file with aliases
    build_content = '''package(default_visibility = ["//visibility:public"])

{plugin_aliases}

# Filegroup to include all plugins
filegroup(
    name = "all_plugins",
    srcs = [
        {plugin_srcs}
    ],
)
'''.format(
        plugin_aliases = plugin_aliases,
        plugin_srcs = ",\n        ".join(plugin_filegroup_srcs) if plugin_filegroup_srcs else "",
    )

    repository_ctx.file("BUILD.bazel", build_content)

tflint_plugin_registry = repository_rule(
    implementation = _tflint_plugin_registry_impl,
    attrs = {
        "plugins": attr.string_list(doc = "List of plugin names to register"),
    },
    doc = "Creates a registry of downloaded TFLint plugins with aliases",
)
