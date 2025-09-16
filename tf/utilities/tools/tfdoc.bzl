"""terraform-docs command execution utilities"""

load("//tf/utilities/utils:runfiles.bzl", "get_runfiles_dir_script", "create_temp_dir_script", "get_workspace_dir_script", "create_runfiles_path")

def create_tfdoc_test_script(ctx, name, srcs, config = None):
    """Creates a script that tests documentation is up-to-date.
    
    Args:
        ctx: Rule context
        name: Script name
        srcs: Source files including README.md
        config: Optional terraform-docs configuration file
        
    Returns:
        Script file and runfiles
    """
    script = ctx.actions.declare_file(name)
    
    config_setup = ""
    config_arg = ""
    if config:
        config_path = create_runfiles_path(ctx, config)
        config_setup = """
# Copy config file if provided
cp "$RUNFILES/{config_path}" "$WORK_DIR/.terraform-docs.yml"
""".format(config_path = config_path)
        config_arg = "--config $WORK_DIR/.terraform-docs.yml"
    
    script_content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}
{temp_dir_script}

# Copy all files from the module directory
MODULE_DIR="$RUNFILES/_main/{module_dir}"
if [ -d "$MODULE_DIR" ]; then
    # Copy with -L to follow symlinks
    cp -rL "$MODULE_DIR"/* "$WORK_DIR/" 2>/dev/null || true
fi

{config_setup}

# Check if README.md exists
if [ ! -f "$WORK_DIR/README.md" ]; then
    echo "ERROR: README.md does not exist in {module_dir}/"
    echo ""
    echo "To generate it, run:"
    echo "  bazel run //{module_dir}:{target_base}_generate_docs"
    exit 1
fi

# Make a copy of the original README.md
cp "$WORK_DIR/README.md" "$WORK_DIR/README-original.md"

# Generate documentation (this will inject into README.md)
cd "$WORK_DIR"
# Redirect ALL output to suppress terraform init noise during test
if ! terraform-docs markdown . {config_arg} >/dev/null 2>&1; then
    echo "ERROR: terraform-docs failed"
    # Show output only on failure for debugging
    terraform-docs markdown . {config_arg}
    exit 1
fi

# Compare the generated docs with original README.md
if ! diff -q "README-original.md" "README.md" > /dev/null 2>&1; then
    echo "ERROR: README.md is out of date in {module_dir}/"
    echo ""
    echo "To update it, run:"
    echo "  bazel run //{module_dir}:{target_base}_generate_docs"
    exit 1
fi

echo "✓ README.md is up-to-date"
""".format(
        runfiles_script = get_runfiles_dir_script(),
        temp_dir_script = create_temp_dir_script(),
        module_dir = ctx.label.package,
        config_setup = config_setup,
        config_arg = config_arg,
        target_base = ctx.label.name.replace("_doc_test", ""),
    )
    
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )
    
    runfiles_files = list(srcs)
    if config:
        runfiles_files.append(config)
    
    return script, ctx.runfiles(files = runfiles_files)

def create_tfdoc_generate_script(ctx, name, config = None):
    """Creates a script that generates documentation.
    
    Args:
        ctx: Rule context
        name: Script name
        config: Optional terraform-docs configuration file
        
    Returns:
        Script file and runfiles
    """
    script = ctx.actions.declare_file(name)
    
    config_arg = ""
    if config:
        config_arg = "--config $WORKSPACE_DIR/{}".format(config.path)
    
    script_content = """#!/usr/bin/env bash
set -euo pipefail

{workspace_script}

# Source and target paths
MODULE_DIR="$WORKSPACE_DIR/{package}"
TARGET_FILE="$MODULE_DIR/README.md"

# Create directory if needed
mkdir -p "$MODULE_DIR"

# Generate the documentation
echo "Generating documentation for {package}..."
cd "$MODULE_DIR"
# Suppress terraform init output but show terraform-docs errors
if ! terraform-docs markdown . {config_arg} 2>/dev/null; then
    echo "ERROR: terraform-docs failed for {package}"
    terraform-docs markdown . {config_arg}
    exit 1
fi

echo "Generated $TARGET_FILE"
""".format(
        workspace_script = get_workspace_dir_script(),
        package = ctx.label.package,
        config_arg = config_arg,
    )
    
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )
    
    runfiles_files = []
    if config:
        runfiles_files.append(config)
    
    return script, ctx.runfiles(files = runfiles_files)