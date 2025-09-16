"""TFLint command execution utilities"""

load("//tf/utilities/utils:runfiles.bzl", "get_runfiles_dir_script", "create_temp_dir_script", "create_runfiles_path")

def create_tflint_script(ctx, name, srcs, config = None):
    """Creates a script that runs tflint.
    
    Args:
        ctx: Rule context
        name: Script name
        srcs: Source files to lint
        config: Optional tflint configuration file
        
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
tflint --call-module-type=none --minimum-failure-severity=warning
""".format(
        runfiles_script = get_runfiles_dir_script(),
        temp_dir_script = create_temp_dir_script(),
        module_dir = ctx.label.package,
        copy_config = copy_config,
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