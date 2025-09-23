"""Internal file operations utilities for Terraform staging"""

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
        ctx.actions.run_shell(
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

                ctx.actions.run_shell(
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
