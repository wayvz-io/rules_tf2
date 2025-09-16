"""Terraform format testing and fixing rules"""

load("//tf2/utilities/utils:runfiles.bzl", "get_workspace_dir_script", "get_runfiles_dir_script")
load("//tf2/utilities/tools:tool_paths.bzl", "get_terraform_path", "TOOLS_ATTR")

def _tf_format_test_impl(ctx):
    """Implementation of tf_format_test rule"""
    
    # Create a test script that checks formatting
    script = ctx.actions.declare_file(ctx.label.name + "_test.sh")
    terraform_bin = get_terraform_path(ctx)
    
    # For format checking, we still need to call the terraform CLI
    # But we can simplify the script structure
    srcs_paths = [f.path for f in ctx.files.srcs]
    
    # Build a more efficient script
    script_content = ["#!/usr/bin/env bash", "set -euo pipefail", ""]
    script_content.append(get_runfiles_dir_script())
    script_content.append("# Check if files are properly formatted")
    script_content.append("FAILED=0")
    script_content.append("")
    
    # Add individual file checks
    for src in srcs_paths:
        script_content.extend([
            'if [ -f "{src}" ]; then'.format(src = src),
            '    if ! {terraform_bin} fmt -check "{src}" > /dev/null 2>&1; then'.format(src = src, terraform_bin = terraform_bin),
            '        echo "ERROR: {src} is not properly formatted"'.format(src = src),
            '        {terraform_bin} fmt -diff "{src}"'.format(src = src, terraform_bin = terraform_bin),
            '        FAILED=1',
            '    fi',
            'fi',
        ])
    
    script_content.extend([
        "",
        "if [ $FAILED -eq 1 ]; then",
        "    echo ''",
        "    echo 'Run terraform fmt to fix formatting issues'",
        "    exit 1",
        "fi",
        "",
        "echo 'All files are properly formatted'",
    ])
    
    script_text = "\n".join(script_content)
    
    ctx.actions.write(
        output = script,
        content = script_text,
        is_executable = True,
    )
    
    runfiles_files = list(ctx.files.srcs)
    # Include tool binaries in runfiles
    if hasattr(ctx.attr, '_tools') and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)
    
    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

def _tf_format_impl(ctx):
    """Implementation of tf_format rule"""
    
    # Create a script that runs terraform fmt
    script = ctx.actions.declare_file(ctx.label.name + "_format.sh")
    terraform_bin = get_terraform_path(ctx)
    
    script_content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}
{workspace_script}
cd "$WORKSPACE_DIR"

# Format all .tf files in the module directory
MODULE_DIR="{module_dir}"
echo "Formatting Terraform files in $MODULE_DIR..."
{terraform_bin} fmt "$MODULE_DIR"
echo "✓ Formatted Terraform files"
""".format(
        runfiles_script = get_runfiles_dir_script(),
        workspace_script = get_workspace_dir_script(),
        module_dir = ctx.label.package,
        terraform_bin = terraform_bin,
    )
    
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )
    
    runfiles_files = list(ctx.files.srcs)
    # Include tool binaries in runfiles
    if hasattr(ctx.attr, '_tools') and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)
    
    return [
        DefaultInfo(
            files = depset([script] + ctx.files.srcs),
            executable = script,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

tf_format_test = rule(
    implementation = _tf_format_test_impl,
    attrs = dict({
        "srcs": attr.label_list(
            allow_files = [".tf"],
            doc = "Terraform source files to check formatting",
            mandatory = True,
        ),
    }, **TOOLS_ATTR),
    test = True,
    doc = "Tests that Terraform files are properly formatted",
)

tf_format = rule(
    implementation = _tf_format_impl,
    attrs = dict({
        "srcs": attr.label_list(
            allow_files = [".tf"],
            doc = "Terraform source files to format",
            mandatory = True,
        ),
    }, **TOOLS_ATTR),
    executable = True,
    doc = "Formats Terraform configuration files",
)