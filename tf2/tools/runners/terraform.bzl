"""Terraform command execution utilities"""

load(":tool_paths.bzl", "get_terraform_path")

def create_terraform_format_test(ctx, name, srcs):
    """Creates a Terraform format test using Starlark actions.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Source files

    Returns:
        Terraform format result file
    """

    # Get terraform binary from tools
    terraform_binary = None
    for tool_file in ctx.files._tools:
        if tool_file.basename == "terraform":
            terraform_binary = tool_file
            break

    if not terraform_binary:
        fail("Terraform binary not found in tools")

    # Copy sources to a controlled location
    copied_srcs = _copy_sources_action(ctx, srcs, "_format")

    # Run terraform fmt in check mode
    result = _run_terraform_action(
        ctx,
        terraform_binary,
        ["fmt", "-check", "-diff", "-no-color"],
        copied_srcs,
        name_suffix = "_format",
    )

    return result

def create_terraform_validate_test(ctx, name, srcs, plugin_dir = None):
    """Creates a Terraform validate test using Starlark actions.

    Args:
        ctx: Rule context
        name: Test name
        srcs: Source files
        plugin_dir: Optional plugin directory

    Returns:
        Terraform validate result file
    """

    # Get terraform binary from tools
    terraform_binary = None
    for tool_file in ctx.files._tools:
        if tool_file.basename == "terraform":
            terraform_binary = tool_file
            break

    if not terraform_binary:
        fail("Terraform binary not found in tools")

    # Copy sources to a controlled location
    copied_srcs = _copy_sources_action(ctx, srcs, "_validate")

    # Generate config if plugin_dir is provided
    config_file = None
    if plugin_dir:
        config_file = _create_terraform_config_action(ctx, plugin_dir, "_validate")

    # First run terraform init
    init_args = ["init", "-backend=false", "-upgrade=false", "-lockfile=readonly", "-no-color"]
    init_result = _run_terraform_action(
        ctx,
        terraform_binary,
        init_args,
        copied_srcs,
        config_file,
        "_init",
    )

    # Then run terraform validate (depends on init)
    validate_inputs = copied_srcs + ([init_result] if init_result else [])
    validate_result = _run_terraform_action(
        ctx,
        terraform_binary,
        ["validate", "-no-color"],
        validate_inputs,
        config_file,
        "_validate",
    )

    return validate_result

def terraform_init_script(ctx, plugin_dir = None, backend = False, upgrade = False, lockfile_readonly = True):
    """Generates simple terraform init command.

    Args:
        ctx: Rule context
        plugin_dir: Optional plugin directory (simplified, just pass the path)
        backend: Whether to initialize backend
        upgrade: Whether to upgrade providers
        lockfile_readonly: Whether to enforce lock file as read-only (default: True)

    Returns:
        String containing terraform init command
    """
    terraform_bin = get_terraform_path(ctx)
    cmd_parts = [terraform_bin, "init"]

    if not backend:
        cmd_parts.append("-backend=false")
    if not upgrade:
        cmd_parts.append("-upgrade=false")
    if lockfile_readonly:
        cmd_parts.append("-lockfile=readonly")

    cmd_parts.append("-no-color")

    if plugin_dir:
        # Simple approach: set up CLI config if plugin_dir provided
        plugin_path = plugin_dir.short_path if plugin_dir.short_path.startswith("bazel-out/") else "_main/{}".format(plugin_dir.short_path)
        return """
# Set up Terraform with provider mirror
if [ -d "$RUNFILES/{plugin_path}" ]; then
    cat > "$WORK_DIR/.terraformrc" <<'EOF'
provider_installation {{
  filesystem_mirror {{
    path = "$RUNFILES/{plugin_path}"
  }}
}}
disable_checkpoint = true
EOF

    export TF_CLI_CONFIG_FILE="$WORK_DIR/.terraformrc"
fi

export TF_DISABLE_CHECKPOINT=true
export CHECKPOINT_DISABLE=true

{cmd}
""".format(plugin_path = plugin_path, cmd = " ".join(cmd_parts))

    return " ".join(cmd_parts)

def create_terraform_script(ctx, name, commands, srcs, extra_runfiles = None):
    """Creates a simplified terraform script.

    Args:
        ctx: Rule context
        name: Script name
        commands: List of command strings to execute
        srcs: Source files
        extra_runfiles: Additional files

    Returns:
        Script file and runfiles
    """
    script = ctx.actions.declare_file(name)

    # Simple script that copies files and runs commands
    script_content = """#!/usr/bin/env bash
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
for file in "$RUNFILES"/_main/*; do
    if [ -f "$file" ] && [[ "$file" == *.tf ]]; then
        cp "$file" "$WORK_DIR/"
    fi
done

cd "$WORK_DIR"

# Set environment
export TF_DISABLE_CHECKPOINT=true
export CHECKPOINT_DISABLE=true

# Execute commands
{commands}
""".format(commands = "\n".join(commands))

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    runfiles_files = list(srcs)
    if extra_runfiles:
        runfiles_files.extend(extra_runfiles)

    # Include tool binaries in runfiles
    if hasattr(ctx.attr, "_tools") and ctx.files._tools:
        runfiles_files.extend(ctx.files._tools)

    return script, ctx.runfiles(files = runfiles_files)

# Private functions merged from terraform_actions.bzl

# Action-based implementations (Starlark approach)

def _create_terraform_config_action(ctx, provider_mirror_path, name_suffix = ""):
    """Creates terraform CLI configuration file using Starlark action.

    Args:
        ctx: Rule context
        provider_mirror_path: Path to provider mirror directory
        name_suffix: Optional suffix for output file name

    Returns:
        Generated terraform CLI config file
    """
    config_file = ctx.actions.declare_file(ctx.label.name + name_suffix + "_terraform_config")

    config_content = """provider_installation {
  filesystem_mirror {
    path = "%s"
  }
}
disable_checkpoint = true
""" % provider_mirror_path

    ctx.actions.write(
        output = config_file,
        content = config_content,
    )

    return config_file

def _copy_sources_action(ctx, srcs, name_suffix = ""):
    """Copies source files using Starlark actions.

    Args:
        ctx: Rule context
        srcs: Source files to copy
        name_suffix: Optional suffix for output directory name

    Returns:
        List of copied files
    """
    copied_files = []
    output_dir = ctx.label.name + name_suffix + "_sources"

    for src in srcs:
        copied_file = ctx.actions.declare_file(output_dir + "/" + src.basename)
        ctx.actions.symlink(
            output = copied_file,
            target_file = src,
        )
        copied_files.append(copied_file)

    return copied_files

def _run_terraform_action(ctx, terraform_binary, args, srcs, config_file = None, name_suffix = ""):
    """Runs terraform command using simple Starlark action.

    Args:
        ctx: Rule context
        terraform_binary: Terraform binary file from tools
        args: Terraform command arguments
        srcs: Source files (for input dependencies)
        config_file: Optional terraform CLI config file
        name_suffix: Optional suffix for output file name

    Returns:
        Output file from terraform execution
    """
    output_file = ctx.actions.declare_file(ctx.label.name + name_suffix + "_output")

    inputs = list(srcs)
    if config_file:
        inputs.append(config_file)

    env = {
        "TF_DISABLE_CHECKPOINT": "true",
        "CHECKPOINT_DISABLE": "true",
        "TF_IN_AUTOMATION": "true",
        "TF_INPUT": "false",
    }
    if config_file:
        env["TF_CLI_CONFIG_FILE"] = config_file.path

    # Find working directory from sources
    work_dir = "."
    if srcs:
        work_dir = srcs[0].dirname

    ctx.actions.run_shell(
        outputs = [output_file],
        inputs = inputs,
        tools = [terraform_binary],
        command = "cd {} && {} {} > {} 2>&1".format(
            work_dir,
            terraform_binary.path,
            " ".join(args),
            output_file.path,
        ),
        env = env,
        mnemonic = "TerraformRun",
        progress_message = "Running terraform %s" % " ".join(args),
    )

    return output_file
