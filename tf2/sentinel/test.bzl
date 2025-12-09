"""Sentinel test rule implementations"""

load("//tf2/tools/runners:sentinel.bzl", "create_sentinel_fmt", "create_sentinel_fmt_check", "create_sentinel_test")

def _tf_sentinel_test_impl(ctx):
    """Implementation of tf_sentinel_test rule"""

    script, runfiles = create_sentinel_test(
        ctx,
        name = ctx.label.name + "_sentinel",
        srcs = ctx.files.srcs,
        tests = ctx.files.tests,
        config = ctx.file.config,
    )

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_sentinel_test = rule(
    implementation = _tf_sentinel_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".sentinel"],
            doc = "Sentinel policy files",
            mandatory = True,
        ),
        "tests": attr.label_list(
            allow_files = [".hcl", ".sentinel", ".json"],
            doc = "Test files and mock data (test/**/*.hcl, mocks/*.sentinel)",
            mandatory = True,
        ),
        "config": attr.label(
            allow_single_file = ["sentinel.hcl"],
            doc = "Optional sentinel configuration file",
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Tests Sentinel policies using sentinel test framework with user-provided mocks",
)

def _tf_sentinel_fmt_test_impl(ctx):
    """Implementation of tf_sentinel_fmt_test rule"""

    script, runfiles = create_sentinel_fmt_check(
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

tf_sentinel_fmt_test = rule(
    implementation = _tf_sentinel_fmt_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".sentinel"],
            doc = "Sentinel policy files to check formatting",
            mandatory = True,
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Tests that Sentinel policy files are properly formatted",
)

def _tf_sentinel_fmt_impl(ctx):
    """Implementation of tf_sentinel_fmt rule for autofix"""

    script, runfiles = create_sentinel_fmt(
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

tf_sentinel_fmt = rule(
    implementation = _tf_sentinel_fmt_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".sentinel"],
            doc = "Sentinel policy files to format",
            mandatory = True,
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    executable = True,
    doc = "Formats Sentinel policy files",
)
