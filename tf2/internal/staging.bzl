"""Staging utilities for Terraform execution"""

# Providers are imported in the functions that use them
load("//tf2/internal:file_ops.bzl", "stage_terraform_files")

def prepare_staging_directory(ctx, stack_info, var_files = [], backend_config = None):
    """Prepare a staging directory with all Terraform files using Starlark actions.

    Args:
        ctx: Rule context
        stack_info: TfModuleInfo provider from the stack
        var_files: List of variable files to include
        backend_config: Optional backend configuration content

    Returns:
        tuple: (staging_dir, all_inputs)
    """
    srcs = stack_info.srcs.to_list()

    # Prepare additional files
    additional_files = {}
    if backend_config:
        additional_files["backend_override.tf"] = backend_config

    # Use the centralized staging utility
    staging_dir = stage_terraform_files(
        ctx,
        srcs = srcs,
        var_files = var_files,
        additional_files = additional_files,
    )

    # Prepare all inputs
    all_inputs = srcs + var_files

    return staging_dir, all_inputs
