"""Terraform validation test rule"""

load("//tf2/tools/runners:terraform.bzl", "create_terraform_script", "terraform_init_script")
load("//tf2/tools/runners:tool_paths.bzl", "get_terraform_path")

def _tf_validate_test_impl(ctx):
    """Implementation of tf_validate_test rule"""

    # Get unpacked providers directory from provider registry if available
    plugin_dir = None
    extra_runfiles = []
    if ctx.attr.provider_registry:
        # Use the unpacked providers directory for filesystem_mirror
        # Create a synthetic file to represent the directory
        if ctx.files.provider_registry:
            # Create a marker file to pass the directory location
            plugin_dir_marker = ctx.actions.declare_file(ctx.label.name + "_provider_dir.txt")
            ctx.actions.write(
                output = plugin_dir_marker,
                content = "mirror_linux_arm64",  # Use the actual mirror directory name
            )
            plugin_dir = plugin_dir_marker

            # For runfiles, we need to include all provider files
            extra_runfiles.append(plugin_dir_marker)
            extra_runfiles.extend(ctx.files.provider_registry)

    # Add lock file to sources if provided
    all_srcs = ctx.files.srcs
    if ctx.attr.lock_file:
        all_srcs = ctx.files.srcs + ctx.files.lock_file
        extra_runfiles.extend(ctx.files.lock_file)

    # Create terraform init and validate commands
    init_cmd = terraform_init_script(ctx, plugin_dir = plugin_dir)
    terraform_bin = get_terraform_path(ctx)
    validate_cmd = "{} validate -no-color".format(terraform_bin)

    script, runfiles = create_terraform_script(
        ctx,
        name = ctx.label.name + "_validate.sh",
        commands = [init_cmd, validate_cmd],
        srcs = all_srcs,
        extra_runfiles = extra_runfiles,
    )

    # Merge runfiles from provider registry if available
    if ctx.attr.provider_registry and ctx.files.provider_registry:
        runfiles = runfiles.merge(ctx.runfiles(files = ctx.files.provider_registry))

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_validate_test = rule(
    implementation = _tf_validate_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files",
            mandatory = True,
        ),
        "versions_file": attr.label(
            allow_single_file = [".tf", ".tf.json"],
            doc = "terraform.tf versions file",
        ),
        "lock_file": attr.label(
            allow_single_file = [".terraform.lock.hcl"],
            doc = "Terraform lock file",
        ),
        "provider_registry": attr.label(
            doc = "Provider registry directory containing downloaded providers",
            allow_files = True,
        ),
        "_terraform_wrapper_script": attr.label(
            default = "//tf2/runner/scripts:terraform_wrapper.sh",
            allow_single_file = True,
        ),
        "_copy_module_files_script": attr.label(
            default = "//tf2/module/scripts:copy_module_files.sh",
            allow_single_file = True,
        ),
        "_copy_source_files_script": attr.label(
            default = "//tf2/module/scripts:copy_source_files.sh",
            allow_single_file = True,
        ),
        "_terraform_init_script": attr.label(
            default = "//tf2/runner/scripts:terraform_init.sh",
            allow_single_file = True,
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Validates Terraform configuration",
)
