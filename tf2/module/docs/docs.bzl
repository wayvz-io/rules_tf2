"""Terraform documentation testing and generation rules"""

load("//tf2/tools/runners:tfdoc.bzl", "create_tfdoc_generator", "create_tfdoc_test")

def _tf_doc_test_impl(ctx):
    """Implementation of tf_doc_test rule"""

    script, runfiles = create_tfdoc_test(
        ctx,
        name = ctx.label.name + "_test.sh",
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

def _tf_generate_docs_impl(ctx):
    """Implementation of tf_generate_docs rule"""

    script, runfiles = create_tfdoc_generator(
        ctx,
        name = ctx.label.name + "_generate.sh",
        config = ctx.file.config,
    )

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_doc_test = rule(
    implementation = _tf_doc_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files including README.md",
            mandatory = True,
        ),
        "config": attr.label(
            allow_single_file = [".yaml", ".yml"],
            doc = "terraform-docs configuration file",
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Tests that README.md is up-to-date with terraform-docs output",
)

tf_generate_docs = rule(
    implementation = _tf_generate_docs_impl,
    attrs = {
        "config": attr.label(
            allow_single_file = [".yaml", ".yml"],
            doc = "terraform-docs configuration file",
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    executable = True,
    doc = "Generates README.md file using terraform-docs",
)
