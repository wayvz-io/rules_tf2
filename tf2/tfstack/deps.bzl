"""Terraform Stack component dependency validation"""

load("//tf2/providers/core:info.bzl", "TfStackInfo")
load("//tf2/tools/runners:shell_utils.bzl", "get_runfiles_dir_script")

def _tf_stack_deps_test_impl(ctx):
    """Implementation of tf_stack_deps_test rule.

    This test verifies that component source references in .tfcomponent.hcl files
    have corresponding module targets in the modules attribute.
    """

    stack_info = ctx.attr.stack[TfStackInfo]

    # Get component files
    component_files = stack_info.component_files.to_list()

    # Build a mapping from module labels to their aliases (if any)
    module_aliases = stack_info.module_aliases if stack_info.module_aliases else {}

    # Get declared module names (from modules attribute)
    # If a module has an alias, use the alias name; otherwise derive from label
    declared_modules = []
    for module in stack_info.modules:
        # Check if this module has an alias
        # The module_aliases dict uses label strings in the format "//package:target"
        # but str(label) may include repo prefix like "@@//..." or "@repo//..."
        # Try multiple formats to find a match
        label = module.label
        label_str = str(label)

        # Normalize label to "//package:target" format
        # str(label) for main repo: "@@//path:target" or "//path:target"
        normalized_label = "//" + label.package + ":" + label.name

        alias_found = False
        for key in [label_str, normalized_label]:
            if key in module_aliases:
                declared_modules.append(module_aliases[key])
                alias_found = True
                break

        if not alias_found:
            # Derive the module name the same way we do in nested.bzl
            path_parts = label.package.split("/")
            package_name = path_parts[-1] if path_parts else label.name

            if label.name in ["tf_module", "module"]:
                declared_modules.append(package_name)
            else:
                declared_modules.append(label.name)

    # Create the test script
    script = ctx.actions.declare_file(ctx.label.name + "_test.sh")

    # Build list of component file paths
    component_paths = " ".join(['"{}"'.format(f.path) for f in component_files])
    declared_modules_str = " ".join(['"{}"'.format(m) for m in declared_modules])

    script_content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}

# Component files to check
COMPONENT_FILES=({component_paths})

# Declared modules in BUILD file
DECLARED_MODULES=({declared_modules})

FAILED=0

# Extract source references from component files
for comp_file in "${{COMPONENT_FILES[@]}}"; do
    if [ ! -f "$comp_file" ]; then
        continue
    fi

    # Extract source = "..." patterns from component blocks
    # Look for patterns like: source = "./something" or source = "../something"
    while IFS= read -r line; do
        source_path=$(echo "$line" | grep -oP 'source\\s*=\\s*"\\K[^"]+' || true)
        if [ -z "$source_path" ]; then
            continue
        fi

        # Skip remote modules (not relative paths)
        if [[ ! "$source_path" =~ ^\\.\\.?/ ]]; then
            continue
        fi

        # Extract the module name from the source path
        # e.g., "../vpc" -> "vpc", "./components/vpc" -> "vpc"
        module_name=$(basename "$source_path")

        # Check if this module is declared
        found=false
        for declared in "${{DECLARED_MODULES[@]}}"; do
            if [ "$declared" == "$module_name" ]; then
                found=true
                break
            fi
        done

        if [ "$found" == "false" ]; then
            echo "ERROR: Component file '$comp_file' references module '$module_name' (from source=\"$source_path\")"
            echo "       but no corresponding module is declared in the 'modules' attribute."
            echo "       Add the module to the BUILD file's tf_stack modules attribute."
            FAILED=1
        fi
    done < "$comp_file"
done

if [ $FAILED -eq 1 ]; then
    echo ""
    echo "Stack dependency validation failed."
    exit 1
fi

echo "Stack dependency validation passed - all referenced modules are declared."
""".format(
        runfiles_script = get_runfiles_dir_script(),
        component_paths = component_paths,
        declared_modules = declared_modules_str,
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = ctx.runfiles(files = component_files),
        ),
    ]

tf_stack_deps_test = rule(
    implementation = _tf_stack_deps_test_impl,
    attrs = {
        "stack": attr.label(
            mandatory = True,
            providers = [TfStackInfo],
            doc = "The tf_stack target to validate dependencies",
        ),
    },
    test = True,
    doc = "Validates that component source references have corresponding module declarations",
)
