"""TFLint command execution utilities"""

load("//tf2/utilities/utils:runfiles.bzl", "get_runfiles_dir_script", "create_temp_dir_script", "create_runfiles_path")

def create_tflint_script(ctx, name, srcs, config = None, expect_issues = False):
    """Creates a script that runs tflint.
    
    Args:
        ctx: Rule context
        name: Script name
        srcs: Source files to lint
        config: Optional tflint configuration file
        expect_issues: If True, the test passes when issues are found
        
    Returns:
        Script file and runfiles
    """
    script = ctx.actions.declare_file(name)
    
    copy_config = ""
    if config:
        config_path = create_runfiles_path(ctx, config)
        copy_config = """
# Copy config if provided
cp "$RUNFILES/{config_path}" "$WORK_DIR/.tflint.hcl"
""".format(config_path = config_path)
    
    script_content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}
{temp_dir_script}

# Copy all files from the module directory
MODULE_DIR="$RUNFILES/_main/{module_dir}"
if [ -d "$MODULE_DIR" ]; then
    cp -r "$MODULE_DIR"/* "$WORK_DIR/" 2>/dev/null || true
fi

{copy_config}

# Run tflint
cd "$WORK_DIR"
tflint --init >/dev/null 2>&1
# Run tflint with minimum-failure-severity to fail on warnings
# Disable errexit temporarily to capture exit code
set +e
tflint --call-module-type=none --minimum-failure-severity=warning
TFLINT_EXIT_CODE=$?
set -e

# Handle expected behavior based on test type
if [ "{expect_issues}" = "True" ]; then
    # Negative test: expecting issues to be found
    if [ $TFLINT_EXIT_CODE -ne 0 ]; then
        echo "✓ Found lint issues as expected (negative test passed)"
        exit 0
    else
        echo "✗ Expected lint issues but none were found (negative test failed)"
        exit 1
    fi
else
    # Positive test: expecting no issues
    if [ $TFLINT_EXIT_CODE -eq 0 ]; then
        echo "✓ No lint issues found (positive test passed)"
        exit 0
    else
        echo "✗ Found lint issues (positive test failed)"
        exit $TFLINT_EXIT_CODE
    fi
fi
""".format(
        runfiles_script = get_runfiles_dir_script(),
        temp_dir_script = create_temp_dir_script(),
        module_dir = ctx.label.package,
        copy_config = copy_config,
        expect_issues = str(expect_issues),
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