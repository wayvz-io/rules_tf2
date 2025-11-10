"""Nested module processing - copying and path rewriting"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")

def _process_module_files(_, module, module_name):
    """Process a module's files for inclusion in a parent module.

    Args:
        _: Unused rule context (kept for API compatibility)
        module: Module target with TfModuleInfo
        module_name: Name for the module directory

    Returns:
        List of (src_file, dest_path) tuples
    """
    files_to_copy = []
    module_info = module[TfModuleInfo]

    for src_file in module_info.srcs.to_list():
        # Create destination path under modules/module_name
        # Preserve the relative path structure within the module
        # Get the relative path from the module's package directory
        module_package = module.label.package
        src_path = src_file.path

        # If the file is in the module's package, get the relative path
        if src_path.startswith(module_package + "/"):
            relative_path = src_path[len(module_package) + 1:]
        else:
            # Fallback to basename if we can't determine relative path
            relative_path = src_file.basename

        dest_path = paths.join("modules", module_name, relative_path)
        files_to_copy.append((src_file, dest_path))

    return files_to_copy

def _rewrite_terraform_file(ctx, src_file, dest_path, module_mappings):
    """Rewrite a Terraform file to update module source paths.

    Args:
        ctx: Rule context
        src_file: Source file to rewrite
        dest_path: Destination path for the file
        module_mappings: Dict of original source -> new source mappings

    Returns:
        File object for the rewritten file
    """
    output_file = ctx.actions.declare_file(dest_path)

    if not module_mappings:
        # No rewrites needed, just copy the file
        ctx.actions.symlink(
            output = output_file,
            target_file = src_file,
        )
        return output_file

    # Read the file content and perform replacements
    # Since we can't read files in Starlark, we'll use a run_shell action
    sed_commands = []
    for old_source, new_source in module_mappings.items():
        # Escape special characters for sed
        old_escaped = old_source.replace("/", "\\/").replace(".", "\\.")
        new_escaped = new_source.replace("/", "\\/")
        sed_commands.append('s/source\\s*=\\s*"{}"/source = "{}"/g'.format(old_escaped, new_escaped))

    # Use sed to rewrite the file
    sed_expr = "; ".join(sed_commands)

    ctx.actions.run_shell(
        inputs = [src_file],
        outputs = [output_file],
        command = 'sed \'{}\' "{}" > "{}"'.format(sed_expr, src_file.path, output_file.path),
        mnemonic = "RewriteTerraform",
        progress_message = "Rewriting %s" % dest_path,
    )

    return output_file

def process_nested_modules(ctx, parent_srcs, modules):
    """Process all nested modules for a parent module, copying files and rewriting paths.

    Args:
        ctx: Rule context
        parent_srcs: Source files for the parent module
        modules: List of nested module dependencies

    Returns:
        Tuple of (all_files, module_mappings) where:
        - all_files: List of all files (parent + processed modules)
        - module_mappings: Dict of source path rewrites
    """
    all_files = []
    module_mappings = {}

    # Track which destination paths have been processed to avoid duplicates
    # This handles the case where a module is included both directly and transitively
    processed_dest_paths = {}

    # First, collect all modules and create mappings
    # We'll build a mapping that handles ANY path to a module and rewrites it to ./modules/<module_name>
    module_names = []
    for _, module in enumerate(modules):
        if TfModuleInfo not in module:
            continue

        # Use a unique module directory name to avoid conflicts
        # For service_intents modules, include the platform to make them unique
        if "service_intents" in module.label.package:
            # Extract platform from path like iac/modules/service_intents/aws/service_instance
            path_parts = module.label.package.split("/")
            if len(path_parts) >= 4:  # ['iac', 'modules', 'service_intents', 'platform', ...]
                platform = path_parts[3]  # e.g., 'aws', 'azure', 'palo_alto'
                module_name = platform + "_" + module.label.name
            else:
                module_name = module.label.name
        else:
            module_name = module.label.name
        module_names.append(module_name)

        # For each module, we want to rewrite ANY source path that references it
        # to the standardized ./modules/<module_name> path
        # We'll create multiple mappings to catch different path patterns:

        # 1. Long relative paths from stacks (../../../modules/...)
        if module.label.package.startswith("iac/"):
            module_rel_path = module.label.package[4:]  # Remove "iac/" prefix
        else:
            module_rel_path = module.label.package

        # Map the full relative path
        original_source = "../../../" + module_rel_path
        new_source = "./modules/" + module_name
        module_mappings[original_source] = new_source

        # Also map from original module path to new prefixed name
        # This handles cases where the Terraform source uses the original module label
        # but we need to rewrite to the platform-prefixed directory name
        original_label_source = "../../" + module_rel_path
        module_mappings[original_label_source] = new_source

        # 2. Sibling module references (../module_name)
        sibling_source = "../" + module_name
        module_mappings[sibling_source] = new_source

        # Also handle sibling references using the original module label name
        original_label_name = module.label.name
        if original_label_name != module_name:  # Only if they're different
            sibling_original = "../" + original_label_name
            module_mappings[sibling_original] = new_source

            # Also handle direct module references for stack tests
            # Maps "./modules/service_instance" to "./modules/aws_service_instance"
            direct_original = "./modules/" + original_label_name
            module_mappings[direct_original] = new_source

        # 3. Parent directory references (../..)
        # For examples that reference their parent module with "../.."
        module_mappings["../.."] = new_source

        # Also handle with trailing slash
        module_mappings["../../"] = new_source

        # 4. Handle alternative path patterns for modules
        # For modules in service_intents, also map simplified paths
        if "service_intents" in module_rel_path:
            # Extract the last part of the path structure for simplified references
            path_parts = module_rel_path.split("/")
            if len(path_parts) >= 4:  # modules/service_intents/provider/module_name
                provider = path_parts[2]  # e.g., "azure", "aws", "palo_alto"
                original_module_name = path_parts[3]  # e.g., "vpc", "vnet", "service_instance"

                # Map ../../../../provider/module_name to this module
                alt_source = "../../../../" + provider + "/" + original_module_name
                module_mappings[alt_source] = new_source

        # Process module files
        module_files = _process_module_files(ctx, module, module_name)

        for src_file, dest_path in module_files:
            # Skip if we've already processed this destination path
            # This prevents duplicate symlinks when a module is included both directly and transitively
            if dest_path in processed_dest_paths:
                continue

            processed_dest_paths[dest_path] = True

            # For .tf files, rewrite them; for others, just copy
            if src_file.basename.endswith(".tf"):
                # Module files might also have relative references that need rewriting
                rewritten = _rewrite_terraform_file(ctx, src_file, dest_path, {})
                all_files.append(rewritten)
            else:
                # For non-TF files, we need to copy them
                output = ctx.actions.declare_file(dest_path)
                ctx.actions.symlink(
                    output = output,
                    target_file = src_file,
                )
                all_files.append(output)

    # Now process parent module files with module mappings
    parent_files = []
    for src_file in parent_srcs:
        if src_file.basename.endswith(".tf") and module_mappings:
            # Rewrite parent module TF files to update module sources
            # Use a unique output path to avoid conflicts with genrules
            # Prefix with the module name to make it unique
            unique_dest_path = ctx.label.name + "_" + src_file.basename
            rewritten = _rewrite_terraform_file(ctx, src_file, unique_dest_path, module_mappings)
            parent_files.append(rewritten)
        else:
            # Keep non-TF files as-is
            parent_files.append(src_file)

    all_files.extend(parent_files)

    return all_files, module_mappings
