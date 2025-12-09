"""Sentinel command execution utilities"""

load(":tool_paths.bzl", "get_sentinel_path")

def create_sentinel_test(ctx, name, srcs, tests, config = None):
    """Creates a Sentinel test.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Sentinel policy files (.sentinel)
        tests: Test directory files (test/**/*.hcl, test/**/*.sentinel mocks)
        config: Optional sentinel.hcl configuration

    Returns:
        Script file and runfiles
    """
    return _create_sentinel_test_action(ctx, name, srcs, tests, config)

def create_sentinel_fmt_check(ctx, name, srcs):
    """Creates a Sentinel format check.

    Args:
        ctx: Rule context
        name: Check name
        srcs: Sentinel policy files to check

    Returns:
        Script file and runfiles
    """
    return _create_sentinel_fmt_action(ctx, name, srcs, check_only = True)

def create_sentinel_fmt(ctx, name, srcs):
    """Creates a Sentinel format fixer.

    Args:
        ctx: Rule context
        name: Fixer name
        srcs: Sentinel policy files to format

    Returns:
        Script file and runfiles
    """
    return _create_sentinel_fmt_action(ctx, name, srcs, check_only = False)

def _create_sentinel_test_action(ctx, name, srcs, tests, config = None):
    """Creates a Sentinel test action.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Sentinel policy files (.sentinel)
        tests: Test directory files (test/**/*.hcl, test/**/*.sentinel mocks)
        config: Optional sentinel.hcl configuration

    Returns:
        Script file and runfiles
    """
    sentinel_bin = get_sentinel_path(ctx)
    script = ctx.actions.declare_file(name + ".sh")

    # Setup config copy if provided
    config_setup = ""
    if config:
        config_path = config.short_path if config.short_path.startswith("bazel-out/") else "_main/{}".format(config.short_path)
        config_setup = '''cp "$RUNFILES/{config_path}" "$WORK_DIR/sentinel.hcl"'''.format(
            config_path = config_path,
        )

    # Build source file copy commands - policy files go at root
    copy_commands = []
    for src in srcs:
        src_path = src.short_path if src.short_path.startswith("bazel-out/") else "_main/{}".format(src.short_path)
        copy_commands.append('cp "$RUNFILES/{}" "$WORK_DIR/{}"'.format(src_path, src.basename))

    # Build test file copy commands - maintain directory structure for test/ and mocks/
    for test_file in tests:
        test_path = test_file.short_path if test_file.short_path.startswith("bazel-out/") else "_main/{}".format(test_file.short_path)

        # Determine relative path within the package
        # The short_path includes the package path, we need to extract the relative part
        package_path = ctx.label.package
        if package_path and test_file.short_path.startswith(package_path + "/"):
            relative_path = test_file.short_path[len(package_path) + 1:]
        else:
            relative_path = test_file.basename

        # Create parent directory and copy file
        if "/" in relative_path:
            parent_dir = "/".join(relative_path.split("/")[:-1])
            copy_commands.append('mkdir -p "$WORK_DIR/{}"'.format(parent_dir))
        copy_commands.append('cp "$RUNFILES/{}" "$WORK_DIR/{}"'.format(test_path, relative_path))

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

# Copy source files and test files
{copy_commands}
cd "$WORK_DIR"

{config_setup}

# Run sentinel test
if {sentinel_bin} test .; then
    echo "✓ Sentinel tests passed"
    exit 0
else
    echo "✗ Sentinel tests failed"
    exit 1
fi
'''.format(
        copy_commands = "\n".join(copy_commands),
        config_setup = config_setup,
        sentinel_bin = sentinel_bin,
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Build runfiles
    runfiles_files = list(srcs) + list(tests)
    if config:
        runfiles_files.append(config)
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return script, ctx.runfiles(files = runfiles_files)

def _create_sentinel_fmt_action(ctx, name, srcs, check_only = True):
    """Creates a Sentinel format action.

    Args:
        ctx: Rule context
        name: Action name
        srcs: Sentinel policy files to format
        check_only: If True, only check formatting (don't modify files)

    Returns:
        Script file and runfiles
    """
    sentinel_bin = get_sentinel_path(ctx)
    script = ctx.actions.declare_file(name + ".sh")

    # Build source file copy commands
    copy_commands = []
    for src in srcs:
        src_path = src.short_path if src.short_path.startswith("bazel-out/") else "_main/{}".format(src.short_path)
        copy_commands.append('cp "$RUNFILES/{}" "$WORK_DIR/{}"'.format(src_path, src.basename))

    if check_only:
        # Check formatting only
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
if {sentinel_bin} fmt -check *.sentinel; then
    echo "✓ Sentinel files are properly formatted"
    exit 0
else
    echo "✗ Sentinel files need formatting. Run 'bazel run' on the format target to fix."
    exit 1
fi
'''.format(
            copy_commands = "\n".join(copy_commands),
            sentinel_bin = sentinel_bin,
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
{sentinel_bin} fmt -check *.sentinel >/dev/null 2>&1
NEEDS_FORMAT=$?
set -e

if [ $NEEDS_FORMAT -eq 0 ]; then
    echo "✓ Sentinel files are already properly formatted"
    exit 0
fi

# Format files
echo "Formatting sentinel files..."
{sentinel_bin} fmt *.sentinel

# Copy formatted files back to source
echo "Copying formatted files back to source..."
for f in *.sentinel; do
    cp "$f" "$WORKSPACE_DIR/{package}/$f"
done
echo "✓ Sentinel files formatted"
'''.format(
            copy_commands = "\n".join(copy_commands),
            sentinel_bin = sentinel_bin,
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
