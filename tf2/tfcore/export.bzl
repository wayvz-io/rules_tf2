"""File export capability for Terraform modules"""

load("//tf2/providers/core:info.bzl", "TfModuleInfo")

def _tf_file_export_impl(ctx):
    """Implementation of tf_file_export rule.

    Creates an executable script that exports a processed Terraform module
    to a local filesystem directory, including all .tf files, nested modules,
    and the lockfile.
    """
    module = ctx.attr.module
    if TfModuleInfo not in module:
        fail("module must be a tf_module target")

    module_info = module[TfModuleInfo]

    # Get all files from the module
    module_files = module_info.srcs.to_list()

    # Get the lockfile if it exists
    lock_file = module_info.lock_file

    # Create the export script
    script = ctx.actions.declare_file(ctx.label.name + ".sh")

    # Build the script content
    script_content = """#!/usr/bin/env bash
set -euo pipefail

EXPORT_DIR="$1"
MODULE_NAME="{module_name}"

if [ -z "${{EXPORT_DIR:-}}" ]; then
    echo "Usage: bazel run {target} <export_directory>"
    echo ""
    echo "Example:"
    echo "  bazel run {target} /tmp/exported_modules"
    echo ""
    echo "This will create: /tmp/exported_modules/{module_name}/"
    exit 1
fi

# Make export directory absolute
if [[ "$EXPORT_DIR" != /* ]]; then
    EXPORT_DIR="$PWD/$EXPORT_DIR"
fi

# Create target path
TARGET_PATH="$EXPORT_DIR/$MODULE_NAME"

echo "========================================="
echo "Exporting Terraform Module"
echo "========================================="
echo "Module: {module_name}"
echo "Target: $TARGET_PATH"
echo "========================================="

# Remove existing directory if it exists
if [ -d "$TARGET_PATH" ]; then
    echo "Removing existing directory: $TARGET_PATH"
    rm -rf "$TARGET_PATH"
fi

# Create the directory
mkdir -p "$TARGET_PATH"

""".format(
        module_name = module_info.name,
        target = str(ctx.label),
    )

    # Track directories we need to create
    dirs_to_create = {}

    # Determine the script directory reference for runfiles
    # Bazel creates a .runfiles directory named after the script
    script_content += """
# Find the runfiles directory
# Bazel creates it as <script_name>.runfiles/
RUNFILES="$0.runfiles"
if [ ! -d "$RUNFILES" ]; then
    # Fallback: try to find it relative to the script
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    RUNFILES="$SCRIPT_PATH.runfiles"
fi

"""

    # Add copy commands for each module file
    for file in module_files:
        # Determine the destination path within the module
        file_path = file.short_path

        # Find the module package in the path to extract the relative path
        package = ctx.attr.module.label.package

        # Extract the relative path from the file
        # For files in bazel-bin, we need to handle the path carefully
        if package in file_path:
            # Find where the package path appears
            idx = file_path.find(package)
            if idx >= 0:
                # Get everything after the package path
                rel_path = file_path[idx + len(package) + 1:]  # +1 to skip the slash
            else:
                rel_path = file.basename
        else:
            # For files like modules/foo/bar.tf, preserve the structure
            # Check if this is a modules/ file
            if "/modules/" in file_path:
                modules_idx = file_path.rfind("/modules/")
                if modules_idx != -1:
                    rel_path = file_path[modules_idx + 1:]  # +1 to skip the leading /
                else:
                    rel_path = file.basename
            else:
                rel_path = file.basename

        # Track directory creation
        if "/" in rel_path:
            dest_dir = "/".join(rel_path.split("/")[:-1])
            dirs_to_create[dest_dir] = True

        # For runfiles, use short_path which already includes workspace for generated files
        # For source files, short_path doesn't include workspace, so we prepend it
        src_path = file.short_path
        if src_path.startswith("../"):
            # External repository file
            runfile_path = src_path[3:]  # Remove ../ prefix
        elif src_path.startswith(ctx.workspace_name + "/"):
            # Already includes workspace
            runfile_path = src_path
        else:
            # Source file, needs workspace prepended
            runfile_path = ctx.workspace_name + "/" + src_path

        script_content += """# Copy {filename}
cp -L "$RUNFILES/{src}" "$TARGET_PATH/{dest}"
""".format(
            filename = rel_path,
            src = runfile_path,
            dest = rel_path,
        )

    # Add lockfile copy if it exists
    if lock_file:
        lock_file_path = lock_file.short_path
        if lock_file_path.startswith("../"):
            lock_runfile_path = lock_file_path[3:]
        elif lock_file_path.startswith(ctx.workspace_name + "/"):
            lock_runfile_path = lock_file_path
        else:
            lock_runfile_path = ctx.workspace_name + "/" + lock_file_path

        script_content += """
# Copy lockfile
echo "Including lockfile: .terraform.lock.hcl"
cp -L "$RUNFILES/{lock_file_path}" "$TARGET_PATH/.terraform.lock.hcl"
""".format(lock_file_path = lock_runfile_path)

    # Add directory creation commands at the beginning (after TARGET_PATH is created)
    if dirs_to_create:
        dir_creation = "\n# Create subdirectories\n"
        for dir_path in sorted(dirs_to_create.keys()):
            dir_creation += 'mkdir -p "$TARGET_PATH/{}"\n'.format(dir_path)

        # Insert directory creation after the TARGET_PATH mkdir
        script_content = script_content.replace(
            'mkdir -p "$TARGET_PATH"',
            'mkdir -p "$TARGET_PATH"' + dir_creation,
        )

    script_content += """
echo "========================================="
echo "Export complete!"
echo "========================================="
echo "Module exported to: $TARGET_PATH"
echo ""
echo "Files exported:"
"""

    # Add file listing
    for file in module_files:
        file_path = file.short_path
        package = ctx.attr.module.label.package

        if package in file_path:
            idx = file_path.find(package)
            if idx >= 0:
                rel_path = file_path[idx + len(package) + 1:]
            else:
                rel_path = file.basename
        else:
            if "/modules/" in file_path:
                modules_idx = file_path.rfind("/modules/")
                if modules_idx != -1:
                    rel_path = file_path[modules_idx + 1:]
                else:
                    rel_path = file.basename
            else:
                rel_path = file.basename

        script_content += 'echo "  - {}"\n'.format(rel_path)

    if lock_file:
        script_content += 'echo "  - .terraform.lock.hcl"\n'

    script_content += """
echo "========================================="
"""

    # Write the script
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Collect all inputs for runfiles
    all_inputs = module_files
    if lock_file:
        all_inputs = all_inputs + [lock_file]

    return [DefaultInfo(
        executable = script,
        runfiles = ctx.runfiles(files = all_inputs),
    )]

tf_file_export = rule(
    implementation = _tf_file_export_impl,
    attrs = {
        "module": attr.label(
            doc = "The tf_module target to export",
            providers = [TfModuleInfo],
            mandatory = True,
        ),
    },
    executable = True,
    doc = """Exports a processed Terraform module to a file system location.

    This rule creates an executable that exports a tf_module (including all processed
    .tf files, nested modules, and the lockfile) to a local filesystem directory.

    The exported directory structure matches what would be packaged for OCI/registry
    publish, making it suitable for:
    - Manual deployment
    - Testing terraform commands locally
    - Integration with external tools
    - Backup/archival

    Example:
        tf_module(
            name = "my_module",
            srcs = glob(["*.tf"]),
            providers = ["@tf_provider_registry//:aws_6"],
        )

        tf_file_export(
            name = "my_module_export",
            module = ":my_module",
        )

    Usage:
        bazel run //path/to:my_module_export /tmp/exported_modules

        # Creates: /tmp/exported_modules/my_module/
        # ├── main.tf
        # ├── variables.tf
        # ├── outputs.tf
        # ├── terraform.tf
        # ├── .terraform.lock.hcl
        # └── modules/
        #     └── nested_module/
        #         └── ...
    """,
)
