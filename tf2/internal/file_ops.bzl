"""Internal file operations utilities for Terraform staging"""

load("//tf2/tools/runners:sh_toolchain.bzl", "SH_TOOLCHAIN_TYPE", "run_shell")

def copy_source_files(source_files, output_prefix = ""):
    """Simple helper to copy source files with optional prefix.

    Args:
        source_files: List of source files
        output_prefix: Optional prefix for output files

    Returns:
        List of output file names
    """
    output_files = []
    for src_file in source_files:
        if output_prefix:
            output_files.append("{}/{}".format(output_prefix, src_file.basename))
        else:
            output_files.append(src_file.basename)
    return output_files

def build_staging_copy_commands(
        source_files,
        staging_dir_path,
        package_path,
        var_files = [],
        lock_file = None,
        rename_tfvars = False):
    """Build shell commands to copy source files to a staging directory.

    This function handles:
    - Files directly in the package (copied to staging root)
    - Files in subdirectories within the package (preserve relative paths)
    - Files from bazel-out with nested modules/templates (preserve structure)
    - Variable files with optional .tfvars → .auto.tfvars renaming
    - Lock file copying as .terraform.lock.hcl

    Args:
        source_files: List of source files to stage
        staging_dir_path: Path to the staging directory
        package_path: The Bazel package path (ctx.label.package)
        var_files: List of variable files to copy to staging root
        lock_file: Optional lock file to copy as .terraform.lock.hcl
        rename_tfvars: If True, rename .tfvars to .auto.tfvars (TFC compatibility)

    Returns:
        List of shell commands to copy files
    """
    copy_commands = []
    created_dirs = {}

    for src_file in source_files:
        src_path = src_file.short_path

        # Determine the destination path based on the source file location
        dest_path = src_file.basename  # Default to just the filename

        # Check if this file is within the package and has subdirectories
        if src_path.startswith(package_path + "/"):
            # Extract everything after the package
            relative_path = src_path[len(package_path) + 1:]

            # If the file is in a subdirectory, preserve the directory structure
            if "/" in relative_path:
                dest_path = relative_path

                # Create parent directories if needed
                parts = relative_path.split("/")
                if len(parts) > 1:
                    dest_dir = "/".join(parts[:-1])
                    if dest_dir not in created_dirs:
                        copy_commands.append("mkdir -p '{}/{}'".format(staging_dir_path, dest_dir))
                        created_dirs[dest_dir] = True
            else:
                # File is directly in the package root
                dest_path = relative_path

            # Check if this is a bazel-out processed file with nested modules or templates
        elif "bazel-out" in src_path and ("/modules/" in src_path or "/templates/" in src_path):
            # This is a processed file - extract the module/templates structure
            parts = src_path.split("/")
            for i, part in enumerate(parts):
                if part in ["modules", "templates"] and i < len(parts) - 1:
                    # Found the modules/templates directory, preserve structure from here
                    module_path = "/".join(parts[i:])
                    dest_path = module_path

                    # Create parent directories
                    dest_dir = "/".join(parts[i:-1])
                    if dest_dir not in created_dirs:
                        copy_commands.append("mkdir -p '{}/{}'".format(staging_dir_path, dest_dir))
                        created_dirs[dest_dir] = True
                    break

        # Otherwise, it's a file from outside the package - use just basename

        copy_commands.append("cp -L '{}' '{}/{}'".format(
            src_file.path,
            staging_dir_path,
            dest_path,
        ))

    # Process variable files - copy to staging root with optional rename
    for var_file in var_files:
        dest_name = var_file.basename

        # Auto-rename tfvars files for TFC compatibility if requested
        if rename_tfvars:
            if dest_name.endswith(".tfvars") and not dest_name.endswith(".auto.tfvars"):
                dest_name = dest_name[:-7] + ".auto.tfvars"
            elif dest_name.endswith(".tfvars.json") and not dest_name.endswith(".auto.tfvars.json"):
                dest_name = dest_name[:-12] + ".auto.tfvars.json"

        copy_commands.append("cp -L '{}' '{}/{}'".format(
            var_file.path,
            staging_dir_path,
            dest_name,
        ))

    # Add lockfile if present
    if lock_file:
        copy_commands.append("cp -L '{}' '{}/.terraform.lock.hcl'".format(
            lock_file.path,
            staging_dir_path,
        ))

    return copy_commands

def create_staging_directory(ctx, name_suffix, source_files, package_path = None):
    """Create a staging directory with source files using a single shell action.

    Args:
        ctx: Rule context
        name_suffix: Suffix for the staging directory name
        source_files: List of source files to stage
        package_path: Optional package path override (defaults to ctx.label.package)

    Returns:
        The staging directory (declared directory)
    """
    if package_path == None:
        package_path = ctx.label.package

    staging_dir = ctx.actions.declare_directory("{}_{}".format(ctx.label.name, name_suffix))

    copy_commands = build_staging_copy_commands(source_files, staging_dir.path, package_path)

    run_shell(
        ctx,
        inputs = source_files,
        outputs = [staging_dir],
        command = """
set -euo pipefail
mkdir -p '{staging_dir}'
{copy_commands}
""".format(
            staging_dir = staging_dir.path,
            copy_commands = "\n".join(copy_commands),
        ),
        mnemonic = "PrepareTerraformStaging",
        progress_message = "Preparing Terraform staging for %s" % ctx.label,
    )

    return staging_dir

def stage_terraform_files(ctx, output_dir, source_files, nested_modules = None):
    """Stage Terraform files into a directory structure using Starlark actions.

    This function replaces shell-based file staging with pure Starlark actions,
    making the build more hermetic and debuggable.

    Args:
        ctx: Rule context
        output_dir: Output directory for staged files
        source_files: List of source files to stage
        nested_modules: Optional dict of nested modules to include

    Returns:
        List of staged files
    """
    staged_files = []

    # Stage main source files
    for src_file in source_files:
        # Create staged file in output directory
        staged_file = ctx.actions.declare_file(
            "{}/{}".format(output_dir, src_file.basename),
        )

        # Copy file to staged location
        run_shell(
            ctx,
            inputs = [src_file],
            outputs = [staged_file],
            command = "cp {} {}".format(src_file.path, staged_file.path),
            mnemonic = "StageTerraformFile",
            progress_message = "Staging {}".format(src_file.basename),
        )

        staged_files.append(staged_file)

    # Stage nested modules if provided
    if nested_modules:
        for module_name, module_files in nested_modules.items():
            module_dir = "{}/modules/{}".format(output_dir, module_name)
            for module_file in module_files:
                staged_file = ctx.actions.declare_file(
                    "{}/{}".format(module_dir, module_file.basename),
                )

                run_shell(
                    ctx,
                    inputs = [module_file],
                    outputs = [staged_file],
                    command = "mkdir -p {} && cp {} {}".format(
                        staged_file.dirname,
                        module_file.path,
                        staged_file.path,
                    ),
                    mnemonic = "StageNestedModule",
                    progress_message = "Staging nested module {}".format(module_file.basename),
                )

                staged_files.append(staged_file)

    return staged_files
