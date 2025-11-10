"""TFLint command execution utilities"""

load(":tool_paths.bzl", "get_tflint_path")

def create_tflint_test(ctx, name, srcs, config = None, expect_issues = False, plugins = None):
    """Creates a TFLint test.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Source files to lint
        config: Optional tflint configuration file
        expect_issues: If True, the test passes when issues are found
        plugins: Optional list of tflint plugin files

    Returns:
        Script file and runfiles
    """
    return _create_tflint_test_action(ctx, name, srcs, config, expect_issues, plugins)

def create_tflint_autofix(ctx, name, srcs, config = None, plugins = None):
    """Creates a TFLint autofix runner.

    Args:
        ctx: Rule context
        name: Runner name
        srcs: Source files to lint and fix
        config: Optional tflint configuration file
        plugins: Optional list of tflint plugin files

    Returns:
        Script file and runfiles
    """
    return _create_tflint_autofix_action(ctx, name, srcs, config, plugins)

# Private functions merged from tflint_actions.bzl

def _create_tflint_test_action(ctx, name, srcs, config = None, expect_issues = False, plugins = None):
    """Creates a streamlined TFLint test action.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Source files to lint
        config: Optional tflint configuration file
        expect_issues: If True, the test passes when issues are found
        plugins: Optional list of tflint plugin files

    Returns:
        Script file and runfiles
    """
    tflint_bin = get_tflint_path(ctx)
    script = ctx.actions.declare_file(name + ".sh")

    # Setup config copy if provided
    config_setup = ""
    if config:
        config_path = config.short_path if config.short_path.startswith("bazel-out/") else "_main/{}".format(config.short_path)
        config_setup = '''cp "$RUNFILES/{config_path}" "$WORK_DIR/.tflint.hcl"'''.format(
            config_path = config_path,
        )

    # Setup plugins if provided
    plugins_setup = ""
    if plugins:
        plugins_setup = '''mkdir -p "$WORK_DIR/.tflint.d/plugins"'''
        for plugin in plugins:
            plugin_path = plugin.short_path if plugin.short_path.startswith("bazel-out/") else "_main/{}".format(plugin.short_path)
            plugin_name = plugin.basename
            plugins_setup += '''
cp "$RUNFILES/{plugin_path}" "$WORK_DIR/.tflint.d/plugins/{plugin_name}"
chmod +x "$WORK_DIR/.tflint.d/plugins/{plugin_name}"'''.format(
                plugin_path = plugin_path,
                plugin_name = plugin_name,
            )

    # Build test logic based on expect_issues
    if expect_issues:
        test_logic = '''
# Expecting issues to be found (negative test)
set +e
{tflint_bin} --call-module-type=none --minimum-failure-severity=warning
TFLINT_EXIT_CODE=$?
set -e

if [ $TFLINT_EXIT_CODE -ne 0 ]; then
    echo "✓ Found lint issues as expected (negative test passed)"
    exit 0
else
    echo "✗ Expected lint issues but none were found (negative test failed)"
    exit 1
fi'''.format(tflint_bin = tflint_bin)
    else:
        test_logic = '''
# Expecting no issues (positive test)
if {tflint_bin} --call-module-type=none --minimum-failure-severity=warning; then
    echo "✓ No lint issues found (positive test passed)"
    exit 0
else
    echo "✗ Found lint issues (positive test failed)"
    exit 1
fi'''.format(tflint_bin = tflint_bin)

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

{plugins_setup}

# Initialize TFLint
{tflint_bin} --init >/dev/null 2>&1

{test_logic}
'''.format(
        copy_commands = "\n".join(copy_commands),
        config_setup = config_setup,
        plugins_setup = plugins_setup,
        tflint_bin = tflint_bin,
        test_logic = test_logic,
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
    if plugins:
        runfiles_files.extend(plugins)
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return script, ctx.runfiles(files = runfiles_files)

def _create_tflint_autofix_action(ctx, name, srcs, config = None, plugins = None):
    """Creates a TFLint autofix action.

    Args:
        ctx: Rule context
        name: Action name
        srcs: Source files to lint and fix
        config: Optional tflint configuration file
        plugins: Optional list of tflint plugin files

    Returns:
        Script file and runfiles
    """
    tflint_bin = get_tflint_path(ctx)
    script = ctx.actions.declare_file(name + ".sh")

    # Setup config copy if provided
    config_setup = ""
    if config:
        config_path = config.short_path if config.short_path.startswith("bazel-out/") else "_main/{}".format(config.short_path)
        config_setup = '''cp "$RUNFILES/{config_path}" "$WORK_DIR/.tflint.hcl"'''.format(
            config_path = config_path,
        )

    # Setup plugins if provided
    plugins_setup = ""
    if plugins:
        plugins_setup = '''mkdir -p "$WORK_DIR/.tflint.d/plugins"'''
        for plugin in plugins:
            plugin_path = plugin.short_path if plugin.short_path.startswith("bazel-out/") else "_main/{}".format(plugin.short_path)
            plugin_name = plugin.basename
            plugins_setup += '''
cp "$RUNFILES/{plugin_path}" "$WORK_DIR/.tflint.d/plugins/{plugin_name}"
chmod +x "$WORK_DIR/.tflint.d/plugins/{plugin_name}"'''.format(
                plugin_path = plugin_path,
                plugin_name = plugin_name,
            )

    # Build source file copy commands
    autofix_copy_commands = []
    for src in srcs:
        src_path = src.short_path if src.short_path.startswith("bazel-out/") else "_main/{}".format(src.short_path)
        autofix_copy_commands.append('cp "$RUNFILES/{}" "$WORK_DIR/{}"'.format(src_path, src.basename))

    # Create autofix script
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

{config_setup}

{plugins_setup}

# Initialize TFLint
{tflint_bin} --init >/dev/null 2>&1

# Check for issues first
echo "Checking for lint issues..."
set +e
INITIAL_OUTPUT=$({tflint_bin} --call-module-type=none --minimum-failure-severity=warning 2>&1)
INITIAL_EXIT_CODE=$?
set -e

if [ $INITIAL_EXIT_CODE -eq 0 ]; then
    echo "✓ No lint issues found"
    exit 0
fi

echo "Found lint issues. Attempting autofix..."
echo "$INITIAL_OUTPUT"
echo ""

# Create checksums before fix
find "$WORK_DIR" -name "*.tf" -exec md5sum {{}} \\; > "$WORK_DIR/before_checksums.txt" 2>/dev/null || true

# Run autofix
set +e
{tflint_bin} --call-module-type=none --minimum-failure-severity=warning --fix 2>&1
set -e

# Create checksums after fix
find "$WORK_DIR" -name "*.tf" -exec md5sum {{}} \\; > "$WORK_DIR/after_checksums.txt" 2>/dev/null || true

# Check if files were changed
if diff -q "$WORK_DIR/before_checksums.txt" "$WORK_DIR/after_checksums.txt" >/dev/null 2>&1; then
    echo "ℹ TFLint autofix found no automatically fixable issues"
    echo "The reported issues require manual intervention"
else
    echo "✓ TFLint autofix applied automatic fixes"
    # Copy fixed files back to source
    echo "Copying fixed files back to source..."
    cp -r "$WORK_DIR"/* "$WORKSPACE_DIR/{package}/" 2>/dev/null || true
    echo "✓ Fixed files copied back to source"
fi
'''.format(
        copy_commands = "\n".join(autofix_copy_commands),
        config_setup = config_setup,
        plugins_setup = plugins_setup,
        tflint_bin = tflint_bin,
        package = ctx.label.package,
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
    if plugins:
        runfiles_files.extend(plugins)
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return script, ctx.runfiles(files = runfiles_files)
