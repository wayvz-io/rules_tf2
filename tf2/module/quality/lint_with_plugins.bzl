"""TFLint test rule implementation with plugin support"""

load("//tf2/tools/runners:tflint.bzl", "create_tflint_test", "create_tflint_autofix")

def _tf_lint_plugin_test_impl(ctx):
    """Implementation of tf_lint_plugin_test rule"""
    
    plugins = []
    if ctx.files.plugins:
        plugins = ctx.files.plugins
    
    script, runfiles = create_tflint_test(
        ctx,
        name = ctx.label.name + "_lint.sh",
        srcs = ctx.files.srcs,
        config = ctx.file.config,
        plugins = plugins,
    )
    
    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_lint_plugin_test = rule(
    implementation = _tf_lint_plugin_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files",
            mandatory = True,
        ),
        "config": attr.label(
            allow_single_file = [".hcl"],
            doc = "TFLint configuration file",
        ),
        "plugins": attr.label_list(
            allow_files = True,
            doc = "TFLint plugin binaries",
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Lints Terraform configuration using tflint with plugins",
)

def _tf_lint_plugin_negative_test_impl(ctx):
    """Implementation of tf_lint_plugin_negative_test rule"""
    
    plugins = []
    if ctx.files.plugins:
        plugins = ctx.files.plugins
    
    script, runfiles = create_tflint_test(
        ctx,
        name = ctx.label.name + "_lint.sh",
        srcs = ctx.files.srcs,
        config = ctx.file.config,
        plugins = plugins,
        expect_issues = True,
    )
    
    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_lint_plugin_negative_test = rule(
    implementation = _tf_lint_plugin_negative_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files with intentional lint issues",
            mandatory = True,
        ),
        "config": attr.label(
            allow_single_file = [".hcl"],
            doc = "TFLint configuration file",
        ),
        "plugins": attr.label_list(
            allow_files = True,
            doc = "TFLint plugin binaries",
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Tests that tflint detects issues in problematic Terraform configuration with plugins",
)

def tf_lint_plugin_negative_test_sized(name, srcs, config = None, plugins = None, size = None, **kwargs):
    """Wrapper macro for tf_lint_plugin_negative_test with proper size handling.

    Args:
        name: Test name
        srcs: Source files with intentional lint issues
        config: Optional tflint configuration file
        plugins: Optional list of tflint plugin binaries
        size: Test size (small, medium, large)
        **kwargs: Additional arguments passed to the underlying rule
    """
    tf_lint_plugin_negative_test(
        name = name,
        srcs = srcs,
        config = config,
        plugins = plugins,
        size = size,
        **kwargs
    )