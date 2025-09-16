"""Terraform file organization checking and reorganization rules"""

load("//tf/utilities/utils:runfiles.bzl", "get_workspace_dir_script", "create_runfiles_path")

def _tf_organization_check_test_impl(ctx):
    """Implementation of tf_organization_check_test rule"""
    
    # Get the hcl_tool binary
    hcl_tool = ctx.executable._hcl_tool
    
    # Create test executable that validates organization
    test_file = ctx.actions.declare_file(ctx.label.name + "_test.sh")
    
    ctx.actions.write(
        output = test_file,
        content = """#!/usr/bin/env bash
set -euo pipefail

# Get the directory containing the source files
SOURCE_DIR="$(dirname "{srcs_0}")"

# Run the hcl_tool validate-organization command
if ! "{hcl_tool}" validate-organization "$SOURCE_DIR"; then
    echo "" >&2
    echo "ERROR: Terraform files are not properly organized" >&2
    echo "Run 'bazel run //{package}:{target_base}_reorganize' to fix the organization" >&2
    exit 1
fi

echo "Terraform files are properly organized"
exit 0
""".format(
            hcl_tool = hcl_tool.short_path,
            srcs_0 = ctx.files.srcs[0].short_path if ctx.files.srcs else ".",
            package = ctx.label.package,
            target_base = ctx.label.name.replace("_organization_check_test", ""),
        ),
        is_executable = True,
    )
    
    return [
        DefaultInfo(
            files = depset([test_file]),
            executable = test_file,
            runfiles = ctx.runfiles(
                files = [test_file, hcl_tool] + ctx.files.srcs,
                transitive_files = ctx.attr._hcl_tool[DefaultInfo].default_runfiles.files,
            ),
        ),
    ]

def _tf_reorganize_impl(ctx):
    """Implementation of tf_reorganize rule"""
    
    # Get the hcl_tool binary
    hcl_tool = ctx.executable._hcl_tool
    
    # Create script to reorganize files in source directory
    script = ctx.actions.declare_file(ctx.label.name + "_reorganize.sh")
    
    script_content = """#!/usr/bin/env bash
set -euo pipefail

{workspace_script}

# Target directory for reorganization
TARGET_DIR="$WORKSPACE_DIR/{package}"
HCL_TOOL="$0.runfiles/{hcl_tool}"

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: Directory $TARGET_DIR does not exist"
    exit 1
fi

# Run the reorganize command
"$HCL_TOOL" reorganize "$TARGET_DIR"

echo "Reorganized Terraform files in $TARGET_DIR"
""".format(
        workspace_script = get_workspace_dir_script(),
        hcl_tool = create_runfiles_path(ctx, hcl_tool),
        package = ctx.label.package,
    )
    
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )
    
    return [
        DefaultInfo(
            files = depset([script, hcl_tool]),
            executable = script,
            runfiles = ctx.runfiles(
                files = [hcl_tool],
                transitive_files = ctx.attr._hcl_tool[DefaultInfo].default_runfiles.files,
            ),
        ),
    ]

tf_organization_check_test = rule(
    implementation = _tf_organization_check_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Terraform source files",
            mandatory = True,
        ),
        "_hcl_tool": attr.label(
            default = "@rules_tf2//hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
    doc = "Tests that Terraform files are properly organized",
)

tf_reorganize = rule(
    implementation = _tf_reorganize_impl,
    attrs = {
        "_hcl_tool": attr.label(
            default = "@rules_tf2//hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
    doc = "Reorganizes Terraform files into standard structure",
)