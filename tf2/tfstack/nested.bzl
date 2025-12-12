"""Nested module processing for Terraform Stacks - copying and path rewriting to ./components/"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")

def _process_module_files_for_stack(_, module, module_name):
    """Process a module's files for inclusion in a stack's components directory.

    Args:
        _: Unused rule context (kept for API compatibility)
        module: Module target with TfModuleInfo
        module_name: Name for the module directory under components/

    Returns:
        List of (src_file, dest_path) tuples
    """
    files_to_copy = []
    module_info = module[TfModuleInfo]

    for src_file in module_info.srcs.to_list():
        # Create destination path under components/module_name
        # Preserve the relative path structure within the module
        module_package = module.label.package
        src_path = src_file.path

        # Handle both source files and bazel-out files
        actual_path = src_path
        if "bazel-out/" in src_path and "/bin/" in src_path:
            bin_idx = src_path.find("/bin/")
            if bin_idx != -1:
                actual_path = src_path[bin_idx + 5:]

        # Get the relative path within the module
        if actual_path.startswith(module_package + "/"):
            relative_path = actual_path[len(module_package) + 1:]
        elif src_path.startswith(module_package + "/"):
            relative_path = src_path[len(module_package) + 1:]
        else:
            relative_path = src_file.basename

        dest_path = paths.join("components", module_name, relative_path)
        files_to_copy.append((src_file, dest_path))

    return files_to_copy

def _derive_component_name(module_label):
    """Derive component directory name from module label.

    Args:
        module_label: Label of the module

    Returns:
        String name for the component directory
    """

    # Use the package name (last directory component)
    path_parts = module_label.package.split("/")
    package_name = path_parts[-1] if path_parts else module_label.name

    # If target name is generic, use package name
    if module_label.name in ["tf_module", "module"]:
        return package_name

    return module_label.name

def _rewrite_component_file(ctx, src_file, dest_path, module_mappings):
    """Rewrite a component file to update module source paths.

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

    # Use sed to perform replacements
    sed_commands = []
    for old_source, new_source in module_mappings.items():
        # Escape special characters for sed
        old_escaped = old_source.replace("/", "\\/").replace(".", "\\.")
        new_escaped = new_source.replace("/", "\\/")
        sed_commands.append('s/source\\s*=\\s*"{}"/source = "{}"/g'.format(old_escaped, new_escaped))

    sed_expr = "; ".join(sed_commands)

    ctx.actions.run_shell(
        inputs = [src_file],
        outputs = [output_file],
        command = 'sed \'{}\' "{}" > "{}"'.format(sed_expr, src_file.path, output_file.path),
        mnemonic = "RewriteStackComponent",
        progress_message = "Rewriting component source paths in %s" % dest_path,
    )

    return output_file

def process_stack_modules(ctx, component_files, deploy_files, data_files, modules):
    """Process all modules for a stack, copying files and rewriting paths to ./components/.

    Args:
        ctx: Rule context
        component_files: List of .tfcomponent.hcl files
        deploy_files: List of .tfdeploy.hcl files
        data_files: List of data files (JSON, etc.)
        modules: List of tf_module dependencies

    Returns:
        Tuple of (all_files, module_mappings) where:
        - all_files: List of all files (components, deploys, data, processed modules)
        - module_mappings: Dict of source path rewrites
    """
    all_files = []
    module_mappings = {}

    # Track processed destination paths to avoid duplicates
    processed_dest_paths = {}

    # Track module names to detect conflicts
    module_name_to_label = {}

    # First pass: build module mappings
    for module in modules:
        if TfModuleInfo not in module:
            continue

        module_name = _derive_component_name(module.label)

        # Check for naming conflicts
        if module_name in module_name_to_label:
            existing_label = module_name_to_label[module_name]
            fail(
                "Naming conflict: Two modules would be staged to 'components/%s/':\n" % module_name +
                "  1. %s\n" % existing_label +
                "  2. %s\n\n" % str(module.label) +
                "Rename one of the modules to avoid the conflict.",
            )

        module_name_to_label[module_name] = str(module.label)

        # Build mappings for various relative path patterns
        current_package = ctx.label.package
        current_depth = current_package.count("/")

        module_rel_path = module.label.package
        if module_rel_path.startswith("iac/"):
            module_rel_path = module_rel_path[4:]

        # Standard mapping: various relative depths to ./components/name
        new_source = "./components/" + module_name
        for i in range(1, min(current_depth + 2, 6)):
            relative_prefix = "../" * i
            original_source = relative_prefix + module.label.package
            module_mappings[original_source] = new_source

            # Also try without iac/ prefix
            if module.label.package.startswith("iac/"):
                module_mappings[relative_prefix + module.label.package[4:]] = new_source

        # Sibling reference
        sibling_source = "../" + module_name
        module_mappings[sibling_source] = new_source

        # Direct local reference
        local_source = "./" + module_name
        module_mappings[local_source] = new_source

    # Second pass: process module files
    for module in modules:
        if TfModuleInfo not in module:
            continue

        module_name = _derive_component_name(module.label)
        module_files = _process_module_files_for_stack(ctx, module, module_name)

        for src_file, dest_path in module_files:
            if dest_path in processed_dest_paths:
                continue

            processed_dest_paths[dest_path] = True

            # For .tf files, they might need internal rewriting (for nested modules)
            if src_file.basename.endswith(".tf"):
                output = ctx.actions.declare_file(dest_path)
                ctx.actions.symlink(
                    output = output,
                    target_file = src_file,
                )
                all_files.append(output)
            else:
                output = ctx.actions.declare_file(dest_path)
                ctx.actions.symlink(
                    output = output,
                    target_file = src_file,
                )
                all_files.append(output)

    # Process component files with path rewriting
    for comp_file in component_files:
        if module_mappings:
            rewritten = _rewrite_component_file(ctx, comp_file, comp_file.basename, module_mappings)
            all_files.append(rewritten)
        else:
            all_files.append(comp_file)

    # Copy deploy files as-is (no path rewriting needed)
    for deploy_file in deploy_files:
        all_files.append(deploy_file)

    # Copy data files as-is
    for data_file in data_files:
        all_files.append(data_file)

    return all_files, module_mappings
