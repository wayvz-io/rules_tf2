"""Terraform file organization checking and reorganization rules

Note: Organization checking is now handled by TFLint with the tf2 plugin
via the tf2_terraform_file_organization rule. The hcl_tool reorganize
command is still used for actually moving blocks between files.
"""

load("//tf2/tools/runners:shell_utils.bzl", "get_runfiles_dir_script", "get_workspace_dir_script")

def _tf_organization_check_test_impl(ctx):
    """Implementation of tf_organization_check_test rule using TFLint with tf2 plugin"""

    # Get the tflint binary and tf2 plugin
    tflint = ctx.attr._tflint[DefaultInfo].files_to_run.executable
    tf2_plugin = ctx.attr._tf2_plugin[DefaultInfo].files_to_run.executable

    # Create minimal TFLint config for organization checking only
    tflint_config = ctx.actions.declare_file(ctx.label.name + "_tflint.hcl")
    config_content = """# Auto-generated tflint configuration for organization checking
config {
  call_module_type = "none"
  force = false
  disabled_by_default = true
}

plugin "tf2" {
  enabled = true
}

# Enable only the organization rule
rule "tf2_terraform_file_organization" {
  enabled = true
}
"""
    ctx.actions.write(
        output = tflint_config,
        content = config_content,
    )

    # Create test executable that validates organization using TFLint
    test_file = ctx.actions.declare_file(ctx.label.name + "_test.sh")

    ctx.actions.write(
        output = test_file,
        content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}

# Get the directory containing the source files
SOURCE_DIR="$(dirname "{srcs_0}")"
CONFIG_FILE="$RUNFILES/_main/{config_file}"
TFLINT="$RUNFILES/_main/{tflint}"
TF2_PLUGIN="$RUNFILES/_main/{tf2_plugin}"

# Create temporary plugin directory (use TMPDIR or /tmp since HOME may not be set in sandbox)
TFLINT_HOME="${{TMPDIR:-/tmp}}/tflint_$$"
mkdir -p "$TFLINT_HOME/.tflint.d/plugins"
cp "$TF2_PLUGIN" "$TFLINT_HOME/.tflint.d/plugins/tflint-ruleset-tf2"
chmod +x "$TFLINT_HOME/.tflint.d/plugins/tflint-ruleset-tf2"
export TFLINT_PLUGIN_DIR="$TFLINT_HOME/.tflint.d/plugins"
trap "rm -rf $TFLINT_HOME" EXIT

# Run TFLint to check organization
if ! "$TFLINT" --config="$CONFIG_FILE" --chdir="$SOURCE_DIR" --minimum-failure-severity=warning; then
    echo "" >&2
    echo "ERROR: Terraform files are not properly organized" >&2
    echo "Run 'bazel run //{package}:{target_base}_reorganize' to fix the organization" >&2
    exit 1
fi

echo "Terraform files are properly organized"
exit 0
""".format(
            runfiles_script = get_runfiles_dir_script(),
            tflint = tflint.short_path,
            tf2_plugin = tf2_plugin.short_path,
            config_file = tflint_config.short_path,
            srcs_0 = ctx.files.srcs[0].short_path if ctx.files.srcs else ".",
            package = ctx.label.package,
            target_base = ctx.label.name.replace("_organization_check_test", ""),
        ),
        is_executable = True,
    )

    tflint_runfiles = ctx.attr._tflint[DefaultInfo].default_runfiles.files
    tf2_plugin_runfiles = ctx.attr._tf2_plugin[DefaultInfo].default_runfiles.files

    return [
        DefaultInfo(
            files = depset([test_file]),
            executable = test_file,
            runfiles = ctx.runfiles(
                files = [test_file, tflint_config, tflint, tf2_plugin] + ctx.files.srcs,
                transitive_files = depset(transitive = [tflint_runfiles, tf2_plugin_runfiles]),
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
        hcl_tool = hcl_tool.short_path if hcl_tool.short_path.startswith("bazel-out/") else "_main/{}".format(hcl_tool.short_path),
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
        "_tflint": attr.label(
            default = "@tf_tool_registry//:tflint",
            executable = True,
            cfg = "exec",
        ),
        "_tf2_plugin": attr.label(
            default = "@rules_tf2//go/tflint_ruleset:tflint-ruleset-tf2",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
    doc = "Tests that Terraform files are properly organized using TFLint tf2 plugin",
)

def _tf_organization_negative_test_impl(ctx):
    """Implementation of tf_organization_negative_test rule that expects organization issues"""

    # Get the tflint binary and tf2 plugin
    tflint = ctx.attr._tflint[DefaultInfo].files_to_run.executable
    tf2_plugin = ctx.attr._tf2_plugin[DefaultInfo].files_to_run.executable

    # Create minimal TFLint config for organization checking only
    tflint_config = ctx.actions.declare_file(ctx.label.name + "_tflint.hcl")
    config_content = """# Auto-generated tflint configuration for organization checking
config {
  call_module_type = "none"
  force = false
  disabled_by_default = true
}

plugin "tf2" {
  enabled = true
}

# Enable only the organization rule
rule "tf2_terraform_file_organization" {
  enabled = true
}
"""
    ctx.actions.write(
        output = tflint_config,
        content = config_content,
    )

    # Create test executable that expects organization issues
    test_file = ctx.actions.declare_file(ctx.label.name + "_test.sh")

    ctx.actions.write(
        output = test_file,
        content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}

# Get the directory containing the source files
SOURCE_DIR="$(dirname "{srcs_0}")"
CONFIG_FILE="$RUNFILES/_main/{config_file}"
TFLINT="$RUNFILES/_main/{tflint}"
TF2_PLUGIN="$RUNFILES/_main/{tf2_plugin}"

# Create temporary plugin directory (use TMPDIR or /tmp since HOME may not be set in sandbox)
TFLINT_HOME="${{TMPDIR:-/tmp}}/tflint_$$"
mkdir -p "$TFLINT_HOME/.tflint.d/plugins"
cp "$TF2_PLUGIN" "$TFLINT_HOME/.tflint.d/plugins/tflint-ruleset-tf2"
chmod +x "$TFLINT_HOME/.tflint.d/plugins/tflint-ruleset-tf2"
export TFLINT_PLUGIN_DIR="$TFLINT_HOME/.tflint.d/plugins"
trap "rm -rf $TFLINT_HOME" EXIT

# Run TFLint to check organization - EXPECT this to fail
if "$TFLINT" --config="$CONFIG_FILE" --chdir="$SOURCE_DIR"; then
    echo "" >&2
    echo "✗ Expected organization issues but none were found (negative test failed)" >&2
    exit 1
else
    echo "✓ Found organization issues as expected (negative test passed)"
    exit 0
fi
""".format(
            runfiles_script = get_runfiles_dir_script(),
            tflint = tflint.short_path,
            tf2_plugin = tf2_plugin.short_path,
            config_file = tflint_config.short_path,
            srcs_0 = ctx.files.srcs[0].short_path if ctx.files.srcs else ".",
        ),
        is_executable = True,
    )

    tflint_runfiles = ctx.attr._tflint[DefaultInfo].default_runfiles.files
    tf2_plugin_runfiles = ctx.attr._tf2_plugin[DefaultInfo].default_runfiles.files

    return [
        DefaultInfo(
            files = depset([test_file]),
            executable = test_file,
            runfiles = ctx.runfiles(
                files = [test_file, tflint_config, tflint, tf2_plugin] + ctx.files.srcs,
                transitive_files = depset(transitive = [tflint_runfiles, tf2_plugin_runfiles]),
            ),
        ),
    ]

tf_organization_negative_test = rule(
    implementation = _tf_organization_negative_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Terraform source files with intentional organization issues",
            mandatory = True,
        ),
        "_tflint": attr.label(
            default = "@tf_tool_registry//:tflint",
            executable = True,
            cfg = "exec",
        ),
        "_tf2_plugin": attr.label(
            default = "@rules_tf2//go/tflint_ruleset:tflint-ruleset-tf2",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
    doc = "Tests that disorganized Terraform files are detected by TFLint tf2 plugin",
)

tf_reorganize = rule(
    implementation = _tf_reorganize_impl,
    attrs = {
        "_hcl_tool": attr.label(
            default = "@rules_tf2//go/hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
    doc = "Reorganizes Terraform files into standard structure",
)
