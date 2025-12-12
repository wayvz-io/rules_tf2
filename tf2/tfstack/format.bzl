"""Terraform Stack format testing and fixing rules"""

load("//tf2/providers/core:info.bzl", "TfStackInfo")
load("//tf2/tools/runners:shell_utils.bzl", "get_runfiles_dir_script", "get_workspace_dir_script")
load("//tf2/tools/runners:tool_paths.bzl", "TOOLS_ATTR", "get_stacksplugin_path", "get_terraform_path")

def _tf_stack_format_test_impl(ctx):
    """Implementation of tf_stack_format_test rule"""

    stack_info = ctx.attr.stack[TfStackInfo]
    terraform_bin = get_terraform_path(ctx)
    stacksplugin_bin = get_stacksplugin_path(ctx)

    # Get all HCL files to check
    hcl_files = []
    for f in stack_info.component_files.to_list():
        hcl_files.append(f)
    for f in stack_info.deploy_files.to_list():
        hcl_files.append(f)

    if not hcl_files:
        fail("No .tfcomponent.hcl or .tfdeploy.hcl files found in stack")

    # Create the test script
    script = ctx.actions.declare_file(ctx.label.name + "_test.sh")

    srcs_paths = [f.path for f in hcl_files]

    script_content = ["#!/usr/bin/env bash", "set -euo pipefail", ""]
    script_content.append(get_runfiles_dir_script())
    script_content.append("# Check if stack HCL files are properly formatted")
    script_content.append("FAILED=0")
    script_content.append("")

    # Create staging directory with all HCL files for terraform stacks fmt
    # We need to check all files in a directory together
    script_content.extend([
        "# Create temp staging directory",
        "STAGING_DIR=$(mktemp -d)",
        "trap 'rm -rf $STAGING_DIR' EXIT",
        "",
        "# Set up stacksplugin for terraform stacks commands",
        "PLUGIN_DIR=$STAGING_DIR/.terraform.d/stacksplugin",
        "mkdir -p $PLUGIN_DIR",
        'cp "{}" "$PLUGIN_DIR/tfstacks"'.format(stacksplugin_bin),
        "chmod +x $PLUGIN_DIR/tfstacks",
        "",
        "# Point terraform to use our plugin directory",
        "export HOME=$STAGING_DIR",
        "",
    ])

    # Copy files to staging
    for src in srcs_paths:
        script_content.append('cp "{}" "$STAGING_DIR/"'.format(src))

    # Run terraform stacks fmt -check on the staging directory
    script_content.extend([
        "",
        "cd $STAGING_DIR",
        'if ! {terraform_bin} stacks fmt -check . > /dev/null 2>&1; then'.format(terraform_bin = terraform_bin),
        '    echo "ERROR: Stack HCL files are not properly formatted"',
        '    {terraform_bin} stacks fmt -diff .'.format(terraform_bin = terraform_bin),
        "    FAILED=1",
        "fi",
    ])

    format_target = ctx.label.name.replace("_format_test", "_format")
    package_path = "//" + ctx.label.package + ":" + format_target

    script_content.extend([
        "",
        "if [ $FAILED -eq 1 ]; then",
        "    echo ''",
        "    echo 'Run \"bazel run {format_target}\" to fix formatting issues'".format(format_target = package_path),
        "    exit 1",
        "fi",
        "",
        "echo 'All stack HCL files are properly formatted'",
    ])

    script_text = "\n".join(script_content)

    ctx.actions.write(
        output = script,
        content = script_text,
        is_executable = True,
    )

    runfiles_files = hcl_files[:]
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

def _tf_stack_format_impl(ctx):
    """Implementation of tf_stack_format rule"""

    terraform_bin = get_terraform_path(ctx)
    stacksplugin_bin = get_stacksplugin_path(ctx)

    script = ctx.actions.declare_file(ctx.label.name + "_format.sh")

    script_content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}
{workspace_script}
cd "$WORKSPACE_DIR"

# Set up stacksplugin for terraform stacks commands
PLUGIN_DIR="$HOME/.terraform.d/stacksplugin"
mkdir -p "$PLUGIN_DIR"
cp "{stacksplugin_bin}" "$PLUGIN_DIR/tfstacks"
chmod +x "$PLUGIN_DIR/tfstacks"

# Format all HCL files in the stack directory using terraform stacks fmt
MODULE_DIR="{module_dir}"
echo "Formatting Terraform Stack HCL files in $MODULE_DIR..."

cd "$MODULE_DIR"
{terraform_bin} stacks fmt .

echo "Formatted Terraform Stack HCL files"
""".format(
        runfiles_script = get_runfiles_dir_script(),
        workspace_script = get_workspace_dir_script(),
        module_dir = ctx.label.package,
        terraform_bin = terraform_bin,
        stacksplugin_bin = stacksplugin_bin,
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    runfiles_files = []
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

tf_stack_format_test = rule(
    implementation = _tf_stack_format_test_impl,
    attrs = dict({
        "stack": attr.label(
            mandatory = True,
            providers = [TfStackInfo],
            doc = "The tf_stack target to check formatting",
        ),
    }, **TOOLS_ATTR),
    test = True,
    doc = "Tests that Terraform Stack HCL files are properly formatted",
)

tf_stack_format = rule(
    implementation = _tf_stack_format_impl,
    attrs = dict({
        "stack": attr.label(
            mandatory = True,
            providers = [TfStackInfo],
            doc = "The tf_stack target to format",
        ),
    }, **TOOLS_ATTR),
    executable = True,
    doc = "Formats Terraform Stack HCL configuration files",
)
