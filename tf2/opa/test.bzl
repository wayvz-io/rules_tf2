"""OPA test rule implementations"""

load("//tf2/tools/runners:opa.bzl", "create_opa_fmt", "create_opa_fmt_check", "create_opa_test")

def _tf_opa_test_impl(ctx):
    """Implementation of tf_opa_test rule"""

    script, runfiles = create_opa_test(
        ctx,
        name = ctx.label.name + "_opa",
        srcs = ctx.files.srcs,
        data = ctx.files.data,
    )

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_opa_test = rule(
    implementation = _tf_opa_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".rego"],
            doc = "Rego policy and test files (tests have rules prefixed with test_)",
            mandatory = True,
        ),
        "data": attr.label_list(
            allow_files = [".json"],
            doc = "Optional JSON data files for testing",
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Tests OPA policies using opa test framework",
)

def _tf_opa_fmt_test_impl(ctx):
    """Implementation of tf_opa_fmt_test rule"""

    script, runfiles = create_opa_fmt_check(
        ctx,
        name = ctx.label.name + "_fmt_test",
        srcs = ctx.files.srcs,
    )

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_opa_fmt_test = rule(
    implementation = _tf_opa_fmt_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".rego"],
            doc = "Rego policy files to check formatting",
            mandatory = True,
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Tests that Rego policy files are properly formatted",
)

def _tf_opa_fmt_impl(ctx):
    """Implementation of tf_opa_fmt rule for autofix"""

    script, runfiles = create_opa_fmt(
        ctx,
        name = ctx.label.name + "_fmt",
        srcs = ctx.files.srcs,
    )

    return [
        DefaultInfo(
            files = depset([script] + ctx.files.srcs),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_opa_fmt = rule(
    implementation = _tf_opa_fmt_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".rego"],
            doc = "Rego policy files to format",
            mandatory = True,
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    executable = True,
    doc = "Formats Rego policy files",
)
