"""OPA command execution utilities"""

load(":tool_paths.bzl", "get_opa_path")

def create_opa_test(ctx, name, srcs, data = None):
    """Creates an OPA test.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Rego policy and test files (.rego)
        data: Optional JSON data files

    Returns:
        Script file and runfiles
    """
    return _create_opa_test_action(ctx, name, srcs, data)

def create_opa_fmt_check(ctx, name, srcs):
    """Creates an OPA format check.

    Args:
        ctx: Rule context
        name: Check name
        srcs: Rego policy files to check

    Returns:
        Script file and runfiles
    """
    return _create_opa_fmt_action(ctx, name, srcs, check_only = True)

def create_opa_fmt(ctx, name, srcs):
    """Creates an OPA format fixer.

    Args:
        ctx: Rule context
        name: Fixer name
        srcs: Rego policy files to format

    Returns:
        Script file and runfiles
    """
    return _create_opa_fmt_action(ctx, name, srcs, check_only = False)

def _create_opa_test_action(ctx, name, srcs, data = None):
    """Creates an OPA test action.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Rego policy and test files (.rego)
        data: Optional JSON data files

    Returns:
        Script file and runfiles
    """
    opa_bin = get_opa_path(ctx)
    script = ctx.actions.declare_file(name + ".sh")

    # Build source file copy commands - all .rego files go to work dir
    copy_commands = []
    for src in srcs:
        src_path = src.short_path if src.short_path.startswith("bazel-out/") else "_main/{}".format(src.short_path)
        copy_commands.append('cp "$RUNFILES/{}" "$WORK_DIR/{}"'.format(src_path, src.basename))

    # Copy data files if provided
    if data:
        for data_file in data:
            data_path = data_file.short_path if data_file.short_path.startswith("bazel-out/") else "_main/{}".format(data_file.short_path)
            copy_commands.append('cp "$RUNFILES/{}" "$WORK_DIR/{}"'.format(data_path, data_file.basename))

    # Create test script
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

# Copy source files and data files
{copy_commands}
cd "$WORK_DIR"

# Run OPA test
if {opa_bin} test -v .; then
    echo "✓ OPA tests passed"
    exit 0
else
    echo "✗ OPA tests failed"
    exit 1
fi
'''.format(
        copy_commands = "\n".join(copy_commands),
        opa_bin = opa_bin,
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Build runfiles
    runfiles_files = list(srcs)
    if data:
        runfiles_files.extend(data)
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return script, ctx.runfiles(files = runfiles_files)

def _create_opa_fmt_action(ctx, name, srcs, check_only = True):
    """Creates an OPA format action.

    Args:
        ctx: Rule context
        name: Action name
        srcs: Rego policy files to format
        check_only: If True, only check formatting (don't modify files)

    Returns:
        Script file and runfiles
    """
    opa_bin = get_opa_path(ctx)
    script = ctx.actions.declare_file(name + ".sh")

    # Build source file copy commands
    copy_commands = []
    for src in srcs:
        src_path = src.short_path if src.short_path.startswith("bazel-out/") else "_main/{}".format(src.short_path)
        copy_commands.append('cp "$RUNFILES/{}" "$WORK_DIR/{}"'.format(src_path, src.basename))

    if check_only:
        # Check formatting only - OPA uses --fail flag
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

# Check formatting
if {opa_bin} fmt --fail *.rego >/dev/null 2>&1; then
    echo "✓ Rego files are properly formatted"
    exit 0
else
    echo "✗ Rego files need formatting. Run 'bazel run' on the format target to fix."
    exit 1
fi
'''.format(
            copy_commands = "\n".join(copy_commands),
            opa_bin = opa_bin,
        )
    else:
        # Fix formatting and copy back
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
    echo "ERROR: BUILD_WORKSPACE_DIRECTORY not set. Run with 'bazel run'."
    exit 1
fi

# Create work directory
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Copy source files
{copy_commands}
cd "$WORK_DIR"

# Check if formatting is needed
set +e
{opa_bin} fmt --fail *.rego >/dev/null 2>&1
NEEDS_FORMAT=$?
set -e

if [ $NEEDS_FORMAT -eq 0 ]; then
    echo "✓ Rego files are already properly formatted"
    exit 0
fi

# Format files (opa fmt -w writes in place)
echo "Formatting Rego files..."
{opa_bin} fmt -w *.rego

# Copy formatted files back to source
echo "Copying formatted files back to source..."
for f in *.rego; do
    cp "$f" "$WORKSPACE_DIR/{package}/$f"
done
echo "✓ Rego files formatted"
'''.format(
            copy_commands = "\n".join(copy_commands),
            opa_bin = opa_bin,
            package = ctx.label.package,
        )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Build runfiles
    runfiles_files = list(srcs)
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return script, ctx.runfiles(files = runfiles_files)
