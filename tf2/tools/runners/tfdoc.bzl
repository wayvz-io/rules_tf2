"""terraform-docs command execution utilities"""

load(":tool_paths.bzl", "get_terraform_docs_path")

def create_tfdoc_test(ctx, name, srcs, config = None):
    """Creates a terraform-docs test.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Source files including README.md
        config: Optional terraform-docs configuration file

    Returns:
        Script file and runfiles
    """
    return _create_tfdoc_test_action(ctx, name, srcs, config)

def create_tfdoc_generator(ctx, name, config = None):
    """Creates a terraform-docs generator.

    Args:
        ctx: Rule context
        name: Generator name
        config: Optional terraform-docs configuration file

    Returns:
        Script file and runfiles
    """
    return _create_tfdoc_generate_action(ctx, name, config)

# Private functions merged from tfdoc_actions.bzl

def _create_tfdoc_test_action(ctx, name, srcs, config = None):
    """Creates a streamlined terraform-docs test action.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Source files including README.md
        config: Optional terraform-docs configuration file

    Returns:
        Script file and runfiles
    """
    terraform_docs_bin = get_terraform_docs_path(ctx)
    script = ctx.actions.declare_file(name + ".sh")

    # Setup config if provided
    config_setup = ""
    config_arg = ""
    if config:
        config_path = config.short_path if config.short_path.startswith("bazel-out/") else "_main/{}".format(config.short_path)
        config_setup = '''cp "$RUNFILES/{config_path}" "$WORK_DIR/.terraform-docs.yml"'''.format(
            config_path = config_path
        )
        config_arg = "--config $WORK_DIR/.terraform-docs.yml"

    # Build source file copy commands
    copy_commands = []
    for src in srcs:
        src_path = src.short_path if src.short_path.startswith("bazel-out/") else "_main/{}".format(src.short_path)
        copy_commands.append('cp "$RUNFILES/{}" "$WORK_DIR/{}"'.format(src_path, src.basename))

    # Create simplified script
    script_content = '''#!/usr/bin/env bash
set -euo pipefail

# Find runfiles
if [ -n "${{RUNFILES_DIR:-}}" ]; then
    RUNFILES="$RUNFILES_DIR"
elif [ -f "$0.runfiles_manifest" ]; then
    RUNFILES="$0.runfiles"
else
    RUNFILES="$0.runfiles"
fi

# Create work directory
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Copy source files
{copy_commands}
cd "$WORK_DIR"

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
if ! {terraform_docs_bin} markdown . {config_arg} >/dev/null 2>&1; then
    echo "ERROR: terraform-docs failed"
    # Show output only on failure for debugging
    {terraform_docs_bin} markdown . {config_arg}
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
'''.format(
        copy_commands = "\n".join(copy_commands),
        config_setup = config_setup,
        config_arg = config_arg,
        terraform_docs_bin = terraform_docs_bin,
        module_dir = ctx.label.package,
        target_base = ctx.label.name.replace("_doc_test", ""),
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Build runfiles
    runfiles_files = list(srcs)
    if config:
        runfiles_files.append(config)
    if hasattr(ctx.attr, '_tools') and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return script, ctx.runfiles(files = runfiles_files)

def _create_tfdoc_generate_action(ctx, name, config = None):
    """Creates a terraform-docs generate action.

    Args:
        ctx: Rule context
        name: Action name
        config: Optional terraform-docs configuration file

    Returns:
        Script file and runfiles
    """
    terraform_docs_bin = get_terraform_docs_path(ctx)
    script = ctx.actions.declare_file(name + ".sh")

    # Setup config argument if provided
    config_arg = ""
    if config:
        config_arg = "--config $WORKSPACE_DIR/{}".format(config.short_path)

    # Create simplified script
    script_content = '''#!/usr/bin/env bash
set -euo pipefail

# Find runfiles and workspace
if [ -n "${{RUNFILES_DIR:-}}" ]; then
    RUNFILES="$RUNFILES_DIR"
elif [ -f "$0.runfiles_manifest" ]; then
    RUNFILES="$0.runfiles"
else
    RUNFILES="$0.runfiles"
fi

if [ -n "${{BUILD_WORKSPACE_DIRECTORY:-}}" ]; then
    WORKSPACE_DIR="$BUILD_WORKSPACE_DIRECTORY"
else
    # Find workspace root by looking for MODULE.bazel
    WORKSPACE_DIR="$PWD"
    while [ ! -f "$WORKSPACE_DIR/MODULE.bazel" ] && [ "$WORKSPACE_DIR" != "/" ]; do
        WORKSPACE_DIR=$(dirname "$WORKSPACE_DIR")
    done
fi

# Source and target paths
MODULE_DIR="$WORKSPACE_DIR/{package}"
TARGET_FILE="$MODULE_DIR/README.md"

# Create directory if needed
mkdir -p "$MODULE_DIR"

# Generate the documentation
echo "Generating documentation for {package}..."
cd "$MODULE_DIR"

# Generate the documentation
if ! {terraform_docs_bin} markdown . {config_arg}; then
    echo "ERROR: terraform-docs failed for {package}"
    exit 1
fi

echo "Generated $TARGET_FILE"
'''.format(
        terraform_docs_bin = terraform_docs_bin,
        package = ctx.label.package,
        config_arg = config_arg,
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Build runfiles
    runfiles_files = []
    if config:
        runfiles_files.append(config)
    if hasattr(ctx.attr, '_tools') and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return script, ctx.runfiles(files = runfiles_files)