"""Module dependency validation test rule"""

load("//tf2/core/rules:info.bzl", "TfModuleInfo")
load("//tf2/utilities/utils:runfiles.bzl", "get_runfiles_dir_script")

def _tf_module_deps_test_impl(ctx):
    """Implementation of tf_module_deps_test rule"""
    
    # Get the module being tested
    module = ctx.attr.module[TfModuleInfo]
    
    # Get the labels of declared dependencies from both deps and modules
    dep_labels = []
    module_name_mappings = {}
    all_deps = list(module.deps) + list(module.modules)
    for dep in all_deps:
        if hasattr(dep, "label"):
            # Convert label to package path
            label_str = str(dep.label)
            # Remove target name to get just the package
            if ":" in label_str:
                package = label_str.split(":")[0]
                module_name = label_str.split(":")[1]
            else:
                package = label_str
                module_name = package.split("/")[-1]
            # Remove leading workspace and // prefixes
            if package.startswith("@@//"):
                package = package[4:]
            elif package.startswith("@//"):
                package = package[3:]
            elif package.startswith("//"):
                package = package[2:]
            dep_labels.append(package)
            
            # For modules attribute, also map the module name to ./modules/<name>
            # This handles the case where modules are rewritten to ./modules/<module_name>
            if dep in module.modules:
                rewritten_path = ctx.label.package + "/modules/" + module_name
                module_name_mappings["./modules/" + module_name] = rewritten_path
                dep_labels.append(rewritten_path)
                
                # Also handle ../module_name references (sibling directory references)
                # Normalize what ../module_name would resolve to from current package
                current_package_parts = ctx.label.package.split("/")
                if len(current_package_parts) > 0:
                    parent_package = "/".join(current_package_parts[:-1])
                    sibling_normalized_path = parent_package + "/" + module_name
                    dep_labels.append(sibling_normalized_path)
    
    # Create test script
    script = ctx.actions.declare_file(ctx.label.name + "_test.sh")
    
    # Create simpler script content
    runfiles_script = get_runfiles_dir_script()
    module_package = ctx.label.package
    deps = " ".join(['"%s"' % d for d in dep_labels])
    # Filter to only include .tf files and exclude examples directory
    tf_files = [f for f in ctx.files.srcs if f.path.endswith(".tf") and "/examples/" not in f.path]
    files = " ".join([f.short_path for f in tf_files])
    
    script_content = '''#!/usr/bin/env bash
set -euo pipefail

''' + runfiles_script + '''

# Current module package
MODULE_PACKAGE="''' + module_package + '''"

# Declared dependencies
DECLARED_DEPS=(''' + deps + ''')

# Function to normalize relative paths
normalize_path() {
    local base="$1"
    local relative="$2"
    
    # Remove ./ prefix if present
    relative="${relative#./}"
    
    # Handle parent directory references
    while [[ "$relative" == ../* ]] || [[ "$relative" == .. ]]; do
        if [[ "$relative" == ../* ]]; then
            relative="${relative#../}"
        else
            relative=""
        fi
        base="${base%/*}"
    done
    
    # Combine paths
    if [ -n "$relative" ] && [ -n "$base" ]; then
        echo "$base/$relative"
    elif [ -n "$base" ]; then
        echo "$base"
    else
        echo "$relative"
    fi
}

# Find all module sources in Terraform files
MISSING_DEPS=()
FILES=(''' + files + ''')

for file in "${FILES[@]}"; do
    FILE_PATH="$RUNFILES/_main/$file"
    
    if [ -f "$FILE_PATH" ]; then
        # Extract module sources that are relative paths
        while IFS= read -r line; do
            if echo "$line" | grep -q 'source.*=.*"'; then
                # Extract the source value between quotes
                source=$(echo "$line" | awk -F'"' '{for(i=2;i<=NF;i+=2) print $i}' | head -1)
                
                # Check if it's a relative path
                if [[ "$source" == "./"* ]] || [[ "$source" == "../"* ]]; then
                    # Normalize the path
                    NORMALIZED=$(normalize_path "$MODULE_PACKAGE" "$source")
                    
                    # Check if it's in declared dependencies
                    FOUND=false
                    for dep in "${DECLARED_DEPS[@]}"; do
                        if [ "$dep" = "$NORMALIZED" ]; then
                            FOUND=true
                            break
                        fi
                    done
                    
                    if [ "$FOUND" = "false" ]; then
                        MISSING_DEPS+=("$source:$NORMALIZED")
                    fi
                fi
            fi
        done < <(grep -h 'source' "$FILE_PATH" 2>/dev/null | grep '=')
    fi
done

# Report results
if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "ERROR: Module uses relative imports without declaring dependencies"
    echo ""
    echo "Found relative module imports without corresponding modules attribute:"
    for dep in "${MISSING_DEPS[@]}"; do
        IFS=':' read -r source normalized <<< "$dep"
        echo "  - $source (add dependency: //$normalized)"
    done
    echo ""
    echo "Add the missing dependencies to the modules attribute:"
    echo "  modules = ["
    for dep in "${MISSING_DEPS[@]}"; do
        IFS=':' read -r source normalized <<< "$dep"
        echo "    \"//$normalized\","
    done
    echo "  ]"
    exit 1
else
    echo "✓ All relative module imports have corresponding dependencies"
    exit 0
fi
'''
    
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )
    
    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = ctx.runfiles(files = tf_files),
        ),
    ]

tf_module_deps_test = rule(
    implementation = _tf_module_deps_test_impl,
    attrs = {
        "module": attr.label(
            doc = "The tf_module target to test",
            providers = [TfModuleInfo],
            mandatory = True,
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files",
            mandatory = True,
        ),
    },
    test = True,
    doc = "Validates that relative module imports are declared as dependencies",
)