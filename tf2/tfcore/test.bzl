"""Terraform test execution rule"""

load("//tf2/providers/core:info.bzl", "TfModuleInfo", "TfProviderConfigurationsInfo")
load("//tf2/tools/runners:terraform.bzl", "create_terraform_script", "terraform_init_script")
load("//tf2/tools/runners:tool_paths.bzl", "get_terraform_path")

def _tf_test_impl(ctx):
    """Implementation of tf_test rule"""

    # Validate that either module or srcs is provided
    if not ctx.attr.module and not ctx.attr.srcs:
        fail("Either 'module' or 'srcs' attribute must be provided")

    # Get sources, lock file, and provider configurations from module if provided
    # Otherwise use direct attributes for backward compatibility
    if ctx.attr.module:
        module_info = ctx.attr.module[TfModuleInfo]
        all_srcs = module_info.srcs.to_list()
        lock_file_files = [module_info.lock_file] if module_info.lock_file else []

        # Get provider configurations from module
        if module_info.provider_configurations:
            provider_config = ctx.attr.module[TfModuleInfo].provider_configurations
            # For now, we still need provider_registry for the unpacked providers
            # This will be improved in future phases
    else:
        # Backward compatibility: use direct srcs attribute
        all_srcs = ctx.files.srcs
        lock_file_files = ctx.files.lock_file if ctx.attr.lock_file else []

    # Get plugin directory from provider registry if available
    plugin_dir = None
    extra_runfiles = []
    if ctx.attr.provider_registry:
        # The provider_registry is a directory containing the providers
        plugin_dir = ctx.file.provider_registry
        if plugin_dir:
            extra_runfiles.append(plugin_dir)

    # Add lock file to sources
    if lock_file_files:
        all_srcs = all_srcs + lock_file_files
        extra_runfiles.extend(lock_file_files)

    # Add data files to runfiles
    if ctx.attr.data:
        extra_runfiles.extend(ctx.files.data)

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
        "module": attr.label(
            doc = "Reference to a tf_module target (provides module sources, lock file, and provider config)",
            providers = [TfModuleInfo],
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files to test (use this OR 'module', not both)",
        ),
        "test_files": attr.label_list(
            allow_files = [".tftest.hcl", ".tftest.json"],
            doc = "Terraform test files (*.tftest.hcl or *.tftest.json) - MANDATORY",
            mandatory = True,
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Additional data files needed by tests (e.g., test fixtures)",
        ),
        "lock_file": attr.label(
            allow_single_file = [".terraform.lock.hcl"],
            doc = "Terraform lock file (only needed if using 'srcs' instead of 'module')",
        ),
        "provider_registry": attr.label(
            doc = "Provider registry directory containing downloaded providers",
            allow_single_file = True,
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = """Runs Terraform tests.

Usage:
  1. Reference a tf_module (recommended):
     tf_test(
         name = "my_test",
         module = ":my_module",
         test_files = ["tests/example.tftest.hcl"],
     )

  2. Or specify sources directly (backward compatibility):
     tf_test(
         name = "my_test",
         srcs = glob(["*.tf"]),
         test_files = ["tests/example.tftest.hcl"],
         lock_file = ":my_lock",
         provider_registry = "@tf_provider_registry//:unpacked_providers",
     )
""",
)
