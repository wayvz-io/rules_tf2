"""TFLint test rule implementation"""

load("//tf2/tools/runners:tflint.bzl", "create_tflint_autofix", "create_tflint_test")

def _tf_lint_test_impl(ctx):
    """Implementation of tf_lint_test rule"""

    script, runfiles = create_tflint_test(
        ctx,
        name = ctx.label.name + "_lint.sh",
        srcs = ctx.files.srcs,
        config = ctx.file.config,
    )

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_lint_test = rule(
    implementation = _tf_lint_test_impl,
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
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Lints Terraform configuration using tflint",
)

def _tf_lint_negative_test_impl(ctx):
    """Implementation of tf_lint_negative_test rule"""

    script, runfiles = create_tflint_test(
        ctx,
        name = ctx.label.name + "_lint.sh",
        srcs = ctx.files.srcs,
        config = ctx.file.config,
        expect_issues = True,
    )

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_lint_negative_test = rule(
    implementation = _tf_lint_negative_test_impl,
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
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Tests that tflint detects issues in problematic Terraform configuration",
)

def _tf_lint_impl(ctx):
    """Implementation of tf_lint rule for autofix"""

    script, runfiles = create_tflint_autofix(
        ctx,
        name = ctx.label.name + "_lint.sh",
        srcs = ctx.files.srcs,
        config = ctx.file.config,
    )

    return [
        DefaultInfo(
            files = depset([script] + ctx.files.srcs),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_lint = rule(
    implementation = _tf_lint_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files to lint and fix",
            mandatory = True,
        ),
        "config": attr.label(
            allow_single_file = [".hcl"],
            doc = "TFLint configuration file",
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    executable = True,
    doc = "Runs tflint with autofix to automatically fix lint issues",
)
