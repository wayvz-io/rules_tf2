"""Nested module processing - copying and path rewriting"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//tf2/modules/core:info.bzl", "TfExternalModuleInfo")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")
load("//tf2/tools/runners:sh_toolchain.bzl", "run_shell")

def _process_module_files(_, module, module_name, skip_nested_modules = None):
    """Process a module's files for inclusion in a parent module.

    Args:
        _: Unused rule context (kept for API compatibility)
        module: Module target with TfModuleInfo
        module_name: Name for the module directory
        skip_nested_modules: Optional dict of nested module names to skip (because they're top-level)

    Returns:
        List of (src_file, dest_path) tuples
    """
    files_to_copy = []
    module_info = module[TfModuleInfo]
    skip_nested_modules = skip_nested_modules or {}

    for src_file in module_info.srcs.to_list():
        # Create destination path under modules/module_name
        # Preserve the relative path structure within the module
        # Get the relative path from the module's package directory
        module_package = module.label.package
        src_path = src_file.path

        # Handle both source files and bazel-out files
        # For bazel-out files, extract the actual module path
        actual_path = src_path
        if "bazel-out/" in src_path and "/bin/" in src_path:
            # Extract path after /bin/
            bin_idx = src_path.find("/bin/")
            if bin_idx != -1:
                actual_path = src_path[bin_idx + 5:]  # Skip "/bin/"

        # Check if this file is from a nested module that should be skipped
        # (because it's also a top-level module in the parent)
        should_skip = False
        if "/modules/" in actual_path:
            # Extract the nested module name from the path
            # Path format: package/modules/nested_module_name/file.tf
            path_after_package = actual_path.replace(module_package + "/", "")
            if path_after_package.startswith("modules/"):
                parts = path_after_package.split("/")
                if len(parts) >= 2:
                    nested_module_name = parts[1]
                    if nested_module_name in skip_nested_modules:
                        should_skip = True

        if should_skip:
            continue

        # Get the relative path within the module
        if actual_path.startswith(module_package + "/"):
            relative_path = actual_path[len(module_package) + 1:]
        elif src_path.startswith(module_package + "/"):
            relative_path = src_path[len(module_package) + 1:]
        else:
            # Fallback to basename if we can't determine relative path
            relative_path = src_file.basename

        dest_path = paths.join("modules", module_name, relative_path)
        files_to_copy.append((src_file, dest_path))

    return files_to_copy

def _process_external_module_files(_, module, module_name):
    """Process an external module's files for inclusion in a parent module.

    Args:
        _: Unused rule context (kept for API compatibility)
        module: Module target with TfExternalModuleInfo
        module_name: Name for the module directory

    Returns:
        List of (src_file, dest_path) tuples
    """
    files_to_copy = []
    module_info = module[TfExternalModuleInfo]

    for src_file in module_info.files.to_list():
        # Derive the module-relative path from short_path to preserve submodule
        # directories. Flattening to basename collides files (e.g. a submodule's
        # variables.tf over the root's).
        short_path = src_file.short_path
        if short_path.startswith("../"):
            after_repo = short_path[3:]
            parts = after_repo.split("/", 1)
            relative_path = parts[1] if len(parts) > 1 else src_file.basename
        else:
            relative_path = short_path

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

        # Match the exact source or a "<source>//<subdir>" reference, keeping the
        # //subdir so external submodules resolve to the vendored copy.
        sed_commands.append('s/source\\s*=\\s*"{}\\(\\/\\/[^"]*\\)\\?"/source = "{}\\1"/g'.format(old_escaped, new_escaped))

    # Use sed to rewrite the file
    sed_expr = "; ".join(sed_commands)

    run_shell(
        ctx,
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

    # Validate that all modules provide either TfModuleInfo or TfExternalModuleInfo
    for module in modules:
        if TfModuleInfo not in module and TfExternalModuleInfo not in module:
            fail(
                "Invalid module target: {}\n".format(module.label) +
                "Targets in 'modules' must be either:\n" +
                "  - A tf_module target (provides TfModuleInfo)\n" +
                "  - An external module from @tf_module_registry (provides TfExternalModuleInfo)\n" +
                "Got a target that provides neither.",
            )

    all_files = []
    module_mappings = {}

    # Track which destination paths have been processed to avoid duplicates
    # This handles the case where a module is included both directly and transitively
    processed_dest_paths = {}

    # Track top-level modules to detect when nested modules reference them
    # This allows us to reuse the top-level copy instead of creating duplicates
    top_level_modules = {}  # label string -> module_name mapping

    # First pass: identify all top-level modules
    current_package = ctx.label.package
    for module in modules:
        # Skip modules that don't have module info providers
        if TfModuleInfo not in module and TfExternalModuleInfo not in module:
            continue

        # Skip external modules in this pass - they don't have nested modules
        if TfExternalModuleInfo in module:
            continue

        if TfModuleInfo not in module:
            continue

        # Determine module name from package path (last directory component)
        # This ensures unique names even when targets are named "tf_module"
        path_parts = module.label.package.split("/")
        package_name = path_parts[-1] if path_parts else module.label.name

        # Check if this is a LOCAL submodule (inside parent's modules/ directory)
        # Local submodules should NOT get a platform prefix - they use the directory name as-is
        # to match the Terraform source path: ./modules/<directory_name>
        is_local_submodule = module.label.package.startswith(current_package + "/modules/")

        if is_local_submodule:
            # For local submodules, use the directory name as-is (no platform prefix)
            module_name = package_name
        elif "service_intents" in module.label.package:
            if len(path_parts) >= 4:
                platform = path_parts[3]
                module_name = platform + "_" + package_name
            else:
                module_name = package_name
        else:
            module_name = package_name

        # Track this as a top-level module (use string representation of label)
        label_str = str(module.label)

        # Normalize the label string format (remove leading @// if present)
        if label_str.startswith("@//"):
            label_str = label_str[3:]
        elif label_str.startswith("//"):
            label_str = label_str[2:]
        top_level_modules[label_str] = module_name

    # Second pass: collect all modules and create mappings
    # We'll build a mapping that handles ANY path to a module and rewrites it to ./modules/<module_name>
    module_names = []
    module_name_to_label = {}  # Track which module uses each name

    # First, process external modules (they're simpler)
    for _, module in enumerate(modules):
        if TfExternalModuleInfo in module:
            module_info = module[TfExternalModuleInfo]
            module_name = module_info.alias

            # Validate name doesn't conflict
            if module_name in module_name_to_label:
                fail(
                    "Module name conflict: '%s' used by both %s and %s" %
                    (module_name, module_name_to_label[module_name], str(module.label)),
                )

            module_name_to_label[module_name] = str(module.label)
            module_names.append(module_name)

            # Map the source URL to ./modules/<alias>. A "<source>//<subdir>"
            # reference is handled by _rewrite_terraform_file, which keeps the
            # //subdir.
            new_source = "./modules/" + module_name
            module_mappings[module_info.source_url] = new_source

            # Process external module files
            module_files = _process_external_module_files(ctx, module, module_name)
            for src_file, dest_path in module_files:
                if dest_path in processed_dest_paths:
                    continue
                processed_dest_paths[dest_path] = True

                # External module files are already complete - just copy them
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

    # Now process local tf_module dependencies
    for _, module in enumerate(modules):
        if TfModuleInfo not in module:
            continue

        # Skip external modules - they were already processed above
        if TfExternalModuleInfo in module:
            continue

        # Use a unique module directory name to avoid conflicts
        # Derive from package path (last directory component) instead of target name
        # This ensures unique names even when targets are named "tf_module"
        path_parts = module.label.package.split("/")
        package_name = path_parts[-1] if path_parts else module.label.name

        # Check if this is a LOCAL submodule (inside parent's modules/ directory)
        # Local submodules should NOT get a platform prefix - they use the directory name as-is
        # to match the Terraform source path: ./modules/<directory_name>
        is_local_submodule = module.label.package.startswith(current_package + "/modules/")

        if is_local_submodule:
            # For local submodules, use the directory name as-is (no platform prefix)
            module_name = package_name
        elif "service_intents" in module.label.package:
            if len(path_parts) >= 4:  # ['iac', 'modules', 'service_intents', 'platform', ...]
                platform = path_parts[3]  # e.g., 'aws', 'azure', 'palo_alto'
                module_name = platform + "_" + package_name
            else:
                module_name = package_name
        else:
            module_name = package_name

        # Validate that the staged module name doesn't conflict with other modules
        if module_name in module_name_to_label:
            existing_label = module_name_to_label[module_name]
            current_label = str(module.label)

            # Check if both modules are in the same package - if so, use target name to differentiate
            existing_package = existing_label.split(":")[0].lstrip("@").lstrip("/")
            current_module_package = module.label.package
            if existing_package == current_module_package:
                # Same package - use target name to differentiate
                module_name = module.label.name
                if module_name in module_name_to_label:
                    # Still conflicts - this shouldn't happen, but handle gracefully
                    pass  # Will be caught by the existing error handling below
                else:
                    module_name_to_label[module_name] = current_label
                    module_names.append(module_name)
                    continue

            # Check if this is a parent-child relationship (local submodule)
            current_package = ctx.label.package
            is_local_submodule = (
                module.label.package.startswith(current_package + "/modules/") or
                existing_label.startswith("//" + current_package + "/modules/")
            )

            if is_local_submodule:
                fail(
                    "Naming conflict detected: Two modules will be staged to 'modules/%s/':\n" % module_name +
                    "  1. %s\n" % existing_label +
                    "  2. %s\n\n" % current_label +
                    "This typically happens when you have both:\n" +
                    "  - An external module (e.g., //iac/networking/aws/vpc)\n" +
                    "  - A local submodule in your modules/ directory (e.g., modules/vpc/)\n\n" +
                    "To fix this:\n" +
                    "  1. Rename the local submodule directory to avoid the conflict\n" +
                    "     (e.g., modules/vpc/ → modules/vpc_local/ or modules/vpc_custom/)\n" +
                    "  2. Update the BUILD file module reference:\n" +
                    "     %s → %s\n" % (
                        current_label,
                        current_label.replace("/modules/" + module_name, "/modules/" + module_name + "_local"),
                    ) +
                    "  3. Update any Terraform module source paths in your .tf files\n\n" +
                    "Local submodules cannot have the same name as external modules being staged.",
                )
            else:
                fail(
                    "Naming conflict detected: Two modules will be staged to 'modules/%s/':\n" % module_name +
                    "  1. %s\n" % existing_label +
                    "  2. %s\n\n" % current_label +
                    "Both modules would be copied to the same directory, causing a conflict.\n" +
                    "This should not happen - please report this as a bug.",
                )

        module_name_to_label[module_name] = str(module.label)
        module_names.append(module_name)

        # For each module, we want to rewrite ANY source path that references it
        # to the standardized ./modules/<module_name> path
        # We'll create multiple mappings to catch different path patterns:

        # 1. Long relative paths from stacks (../../../modules/...)
        if module.label.package.startswith("iac/"):
            module_rel_path = module.label.package[4:]  # Remove "iac/" prefix
        else:
            module_rel_path = module.label.package

        # Calculate the correct number of "../" based on the relative path depth
        # Get the current package depth (how many slashes in the package path)
        current_package = ctx.label.package
        current_depth = current_package.count("/")

        # Get the target module depth (assuming it starts from "iac/")
        target_depth = module.label.package.count("/")

        # Calculate how many levels we need to go up to get to common root (iac/)
        # From current package, we go up to iac/ and then down to the module
        levels_up = current_depth
        relative_prefix = "../" * levels_up

        # Map the full relative path
        original_source = relative_prefix + module_rel_path
        new_source = "./modules/" + module_name
        module_mappings[original_source] = new_source

        # Also map shorter relative paths that might be used
        # Try various combinations to catch different path patterns used in practice
        for i in range(1, min(levels_up + 2, 6)):  # Check up to 5 levels
            alt_prefix = "../" * i
            alt_source = alt_prefix + module_rel_path
            module_mappings[alt_source] = new_source

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

        # 3.5. Short paths leveraging common parent directories
        # Calculate common ancestor and generate short paths
        # For example: from iac/networking/aws/panorama/deployments/aws_panorama
        #              to iac/networking/aws/vpc
        #              common ancestor is iac/networking/aws
        #              so ../../../vpc should work (3 levels up to aws/, then vpc)
        current_parts = current_package.split("/")
        module_parts = module.label.package.split("/")

        # Find common ancestor
        common_depth = 0
        for i in range(min(len(current_parts), len(module_parts))):
            if current_parts[i] == module_parts[i]:
                common_depth = i + 1
            else:
                break

        # Calculate short path from common ancestor
        if common_depth > 0:
            # Levels up from current to common ancestor
            levels_to_common = len(current_parts) - common_depth

            # Remaining path from common ancestor to module
            remaining_path = "/".join(module_parts[common_depth:])

            if remaining_path:  # Only if there's a path after common ancestor
                short_path_prefix = "../" * levels_to_common
                short_source = short_path_prefix + remaining_path
                module_mappings[short_source] = new_source

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

        # Check if this module has nested dependencies that are also top-level
        # If so, we'll create module-specific mappings to reference the top-level versions
        # These mappings should ONLY be applied to this module's files, not to parent files
        module_specific_mappings = {}
        module_info = module[TfModuleInfo]
        if hasattr(module_info, "modules") and module_info.modules:
            for nested_module in module_info.modules:
                nested_label_str = str(nested_module.label)

                # Normalize the label string
                if nested_label_str.startswith("@//"):
                    nested_label_str = nested_label_str[3:]
                elif nested_label_str.startswith("//"):
                    nested_label_str = nested_label_str[2:]

                if nested_label_str in top_level_modules:
                    # This nested module is also a top-level module
                    # Create a mapping to reference it from this module (not parent)
                    nested_name = top_level_modules[nested_label_str]

                    # Get the nested module's package name (used in its modules/ directory)
                    nested_path_parts = nested_module.label.package.split("/")
                    nested_package_name = nested_path_parts[-1] if nested_path_parts else nested_module.label.name

                    # Map from the nested reference to the sibling top-level module
                    # Use the package name (which is what gets staged in modules/ directory)
                    # When child_with_nested_dep references ./modules/nested_dependency_test, it should become ../nested_dependency_test
                    module_specific_mappings["./modules/" + nested_package_name] = "../" + nested_name

                    # Also handle sibling-style references (e.g., ../flow_logs)
                    # When vpc references ../flow_logs, and both vpc and flow_logs are staged
                    # as sibling modules, the path should become ../flow_logs (which stays the same
                    # but now resolves correctly in the staged structure)

                    # Map various sibling reference patterns to the top-level staged name
                    module_specific_mappings["../" + nested_package_name] = "../" + nested_name

                    # Also handle deeper relative references (e.g., ../../generic/ipam_cidr_allocator)
                    # Calculate relative path from this module's package to the nested module's package
                    module_package_parts = module.label.package.split("/")
                    nested_package_parts = nested_module.label.package.split("/")

                    # Find common ancestor depth
                    common_depth = 0
                    for i in range(min(len(module_package_parts), len(nested_package_parts))):
                        if module_package_parts[i] == nested_package_parts[i]:
                            common_depth = i + 1
                        else:
                            break

                    # Calculate the relative path from this module to the nested module
                    levels_up = len(module_package_parts) - common_depth
                    remaining_path = "/".join(nested_package_parts[common_depth:])

                    if remaining_path and levels_up > 0:
                        # Create the relative path mapping
                        rel_path = "../" * levels_up + remaining_path
                        module_specific_mappings[rel_path] = "../" + nested_name

        # Track which nested modules we should skip (because they're top-level)
        # Build a dict of nested module directory names to skip
        skip_nested_modules = {}
        if hasattr(module_info, "modules") and module_info.modules:
            for nested_module in module_info.modules:
                nested_label_str = str(nested_module.label)
                if nested_label_str.startswith("@//"):
                    nested_label_str = nested_label_str[3:]
                elif nested_label_str.startswith("//"):
                    nested_label_str = nested_label_str[2:]
                if nested_label_str in top_level_modules:
                    # Get the nested module's staged directory name
                    # This is the name used when it was staged in the child's modules/ directory
                    nested_path_parts = nested_module.label.package.split("/")
                    nested_package_name = nested_path_parts[-1] if nested_path_parts else nested_module.label.name
                    skip_nested_modules[nested_package_name] = True

        # Process module files with skip list
        module_files = _process_module_files(ctx, module, module_name, skip_nested_modules)

        for src_file, dest_path in module_files:
            # Skip if we've already processed this destination path
            # This prevents duplicate symlinks when a module is included both directly and transitively
            if dest_path in processed_dest_paths:
                continue

            processed_dest_paths[dest_path] = True

            # For .tf files, rewrite them; for others, just copy
            if src_file.basename.endswith(".tf"):
                # Module files might also have relative references that need rewriting
                # Use module-specific mappings for this module's files
                rewritten = _rewrite_terraform_file(ctx, src_file, dest_path, module_specific_mappings)
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
            # Only prefix with module name if it's a generated file to avoid conflicts
            # Generated files typically have "bazel-out" in their path
            if "bazel-out" in src_file.path or "bazel-bin" in src_file.path:
                # This is a generated file, use a unique name to avoid conflicts
                unique_dest_path = ctx.label.name + "_" + src_file.basename
                rewritten = _rewrite_terraform_file(ctx, src_file, unique_dest_path, module_mappings)
            else:
                # This is a source file, keep the original basename
                rewritten = _rewrite_terraform_file(ctx, src_file, src_file.basename, module_mappings)
            parent_files.append(rewritten)
        else:
            # Keep non-TF files as-is
            parent_files.append(src_file)

    all_files.extend(parent_files)

    return all_files, module_mappings
