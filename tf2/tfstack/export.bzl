"""Terraform Stack directory export rule"""

load("//tf2/providers/core:info.bzl", "TfStackInfo")
load("//tf2/tfstack:nested.bzl", "process_stack_modules")
load("//tf2/tools/runners:shell_utils.bzl", "get_runfiles_dir_script", "get_workspace_dir_script")

def _tf_stack_file_export_impl(ctx):
    """Implementation of tf_stack_file_export rule.

    Exports a Terraform Stack to a directory with proper structure:
    - *.tfcomponent.hcl at root
    - *.tfdeploy.hcl at root
    - components/ directory with referenced modules
    - .terraform.lock.hcl
    - .terraform-version
    """

    stack_info = ctx.attr.stack[TfStackInfo]

    # Get component and deploy files
    component_files = stack_info.component_files.to_list()
    deploy_files = stack_info.deploy_files.to_list()
    data_files = stack_info.data_files.to_list()

    # Process modules and rewrite paths
    all_processed_files, _ = process_stack_modules(
        ctx,
        component_files,
        deploy_files,
        data_files,
        stack_info.modules,
    )

    # Create staging directory for the export
    staging_dir = ctx.actions.declare_directory("{}_export_staging".format(ctx.label.name))

    # Build copy commands
    copy_commands = []
    all_inputs = []
    created_dirs = {}

    for f in all_processed_files:
        # Determine destination path
        if f.path.endswith(".tfcomponent.hcl") or f.path.endswith(".tfdeploy.hcl"):
            dest_path = f.basename
        elif f.path.endswith(".json"):
            # Data files - preserve structure if in subdirectory
            dest_path = f.basename
        elif "/components/" in f.path:
            idx = f.path.find("/components/")
            dest_path = f.path[idx + 1:]

            parts = dest_path.split("/")
            if len(parts) > 1:
                dest_dir = "/".join(parts[:-1])
                if dest_dir not in created_dirs:
                    copy_commands.append("mkdir -p '{}/{}'".format(staging_dir.path, dest_dir))
                    created_dirs[dest_dir] = True
        else:
            dest_path = f.basename

        copy_commands.append("cp -L '{}' '{}/{}'".format(f.path, staging_dir.path, dest_path))
        all_inputs.append(f)

    # Add lockfile if present
    if stack_info.lock_file:
        copy_commands.append("cp -L '{}' '{}/.terraform.lock.hcl'".format(
            stack_info.lock_file.path,
            staging_dir.path,
        ))
        all_inputs.append(stack_info.lock_file)

    # Add .terraform-version file
    version_content = stack_info.terraform_version or "1.14.1"
    copy_commands.append("echo '{}' > '{}/.terraform-version'".format(version_content, staging_dir.path))

    # Create the staging directory
    ctx.actions.run_shell(
        inputs = all_inputs,
        outputs = [staging_dir],
        command = """
set -euo pipefail
mkdir -p '{staging_dir}'
{copy_commands}
""".format(
            staging_dir = staging_dir.path,
            copy_commands = "\n".join(copy_commands),
        ),
        mnemonic = "PrepareStackExport",
        progress_message = "Preparing Terraform Stack export for %s" % ctx.label,
    )

    # Create the export script
    script = ctx.actions.declare_file("{}_export.sh".format(ctx.label.name))

    script_content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_DIR="$SCRIPT_DIR/{staging_basename}"

# Output directory (default to current directory)
OUTPUT_DIR="${{1:-.}}"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Copy all files from staging to output
echo "Exporting Terraform Stack to $OUTPUT_DIR..."
cp -r "$STAGING_DIR"/. "$OUTPUT_DIR/"

# Make files writable
chmod -R u+w "$OUTPUT_DIR"

echo ""
echo "Stack exported successfully to: $OUTPUT_DIR"
echo ""
echo "Contents:"
find "$OUTPUT_DIR" -type f | head -20
TOTAL=$(find "$OUTPUT_DIR" -type f | wc -l)
if [ "$TOTAL" -gt 20 ]; then
    echo "... and $((TOTAL - 20)) more files"
fi
""".format(
        runfiles_script = get_runfiles_dir_script(),
        staging_basename = staging_dir.basename,
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([script, staging_dir]),
            executable = script,
            runfiles = ctx.runfiles(files = [staging_dir]),
        ),
    ]

tf_stack_file_export = rule(
    implementation = _tf_stack_file_export_impl,
    attrs = {
        "stack": attr.label(
            mandatory = True,
            providers = [TfStackInfo],
            doc = "The tf_stack target to export",
        ),
    },
    executable = True,
    doc = "Exports a Terraform Stack to a directory with proper structure",
)
