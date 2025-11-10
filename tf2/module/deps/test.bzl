"""Terraform test execution rule"""

load("//tf2/tools/runners:terraform.bzl", "create_terraform_script", "terraform_init_script")
load("//tf2/tools/runners:tool_paths.bzl", "get_terraform_path")

def _tf_test_impl(ctx):
    """Implementation of tf_test rule"""
    
    # Get plugin directory from provider registry if available
    plugin_dir = None
    extra_runfiles = []
    if ctx.attr.provider_registry:
        # The provider_registry is a directory containing the providers
        plugin_dir = ctx.file.provider_registry
        if plugin_dir:
            extra_runfiles.append(plugin_dir)
    
    # Add lock file to sources if provided
    all_srcs = ctx.files.srcs
    if ctx.attr.lock_file:
        all_srcs = ctx.files.srcs + ctx.files.lock_file
        extra_runfiles.extend(ctx.files.lock_file)
    
    # Create terraform init and test commands
    init_cmd = terraform_init_script(ctx, plugin_dir = plugin_dir)
    terraform_bin = get_terraform_path(ctx)
    test_cmd = "{} test -no-color".format(terraform_bin)
    
    # Add specific test file if provided
    if ctx.attr.test_files:
        for test_file in ctx.files.test_files:
            test_cmd += " " + test_file.basename
    
    script, runfiles = create_terraform_script(
        ctx,
        name = ctx.label.name + "_test.sh",
        commands = [init_cmd, test_cmd],
        srcs = all_srcs + ctx.files.test_files,
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

tf_test = rule(
    implementation = _tf_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module or stack source files",
            mandatory = True,
        ),
        "test_files": attr.label_list(
            allow_files = [".tftest.hcl", ".tftest.json"],
            doc = "Terraform test files (*.tftest.hcl or *.tftest.json)",
            mandatory = True,
        ),
        "lock_file": attr.label(
            allow_single_file = [".terraform.lock.hcl"],
            doc = "Terraform lock file",
        ),
        "provider_registry": attr.label(
            doc = "Provider registry directory containing downloaded providers",
            allow_single_file = True,
        ),
        "_terraform_wrapper_script": attr.label(
            default = "//tf2/utilities/scripts:terraform_wrapper.sh",
            allow_single_file = True,
        ),
        "_copy_module_files_script": attr.label(
            default = "//tf2/utilities/scripts:copy_module_files.sh",
            allow_single_file = True,
        ),
        "_copy_source_files_script": attr.label(
            default = "//tf2/utilities/scripts:copy_source_files.sh",
            allow_single_file = True,
        ),
        "_terraform_init_script": attr.label(
            default = "//tf2/utilities/scripts:terraform_init.sh",
            allow_single_file = True,
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Runs Terraform tests",
)