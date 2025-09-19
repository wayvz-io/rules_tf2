"""Terraform command execution utilities"""

load(":shell_utils.bzl", "get_runfiles_dir_script", "create_temp_dir_script")
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
        name_suffix = "_format"
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
        "_init"
    )

    # Then run terraform validate (depends on init)
    validate_inputs = copied_srcs + ([init_result] if init_result else [])
    validate_result = _run_terraform_action(
        ctx,
        terraform_binary,
        ["validate", "-no-color"],
        validate_inputs,
        config_file,
        "_validate"
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

def _copy_module_files_script(ctx, module_dir):
    """Generates script to copy module files to work directory.

    Args:
        ctx: Rule context
        module_dir: Module directory path

    Returns:
        Shell script string
    """
    repo_name = ctx.label.workspace_name
    if repo_name:
        return """
# Copy all files from the module directory (external repository)
MODULE_DIR="$RUNFILES/{repo_name}/{module_dir}"
if [ ! -d "$MODULE_DIR" ]; then
    # Try with ~~ separator (newer bazel versions)
    MODULE_DIR="$RUNFILES/{repo_name}~/{module_dir}"
fi
if [ -d "$MODULE_DIR" ]; then
    cp -r "$MODULE_DIR"/* "$WORK_DIR/" 2>/dev/null || true
    # Also copy hidden files (like .terraform.lock.hcl)
    cp -r "$MODULE_DIR"/.[^.]* "$WORK_DIR/" 2>/dev/null || true
else
    echo "ERROR: Module directory not found at $MODULE_DIR"
    ls -la "$RUNFILES/{repo_name}/" | head -20 || true
    ls -la "$RUNFILES/{repo_name}~/" | head -20 || true
fi
""".format(repo_name = repo_name, module_dir = module_dir)
    else:
        return """
# Copy all files from the module directory
MODULE_DIR="$RUNFILES/_main/{module_dir}"
if [ -d "$MODULE_DIR" ]; then
    cp -r "$MODULE_DIR"/* "$WORK_DIR/" 2>/dev/null || true
    # Also copy hidden files (like .terraform.lock.hcl)
    cp -r "$MODULE_DIR"/.[^.]* "$WORK_DIR/" 2>/dev/null || true
fi
""".format(module_dir = module_dir)

def _copy_source_files_script(ctx, srcs):
    """Generates script to copy individual source files to work directory.

    Args:
        ctx: Rule context
        srcs: List of source files to copy

    Returns:
        Shell script string
    """
    if not srcs:
        return "# No source files to copy"

    copy_commands = []
    seen_basenames = {}
    module_package = ctx.label.package

    for src in srcs:
        # Skip files that are in the module package directory
        if src.short_path.startswith(module_package + "/"):
            continue

        # Also skip files from the same package in external repositories
        if "/" + module_package + "/" in src.short_path:
            continue

        src_path = src.short_path if src.short_path.startswith("bazel-out/") else "_main/{}".format(src.short_path)
        basename = src.basename

        if basename in seen_basenames:
            fail("File name conflict: '{}' appears in both '{}' and '{}'".format(
                basename,
                seen_basenames[basename],
                src.short_path
            ))
        seen_basenames[basename] = src.short_path

        copy_commands.append("""
# Copy {short_path} to working directory
SRC_FILE="$RUNFILES/{src_path}"
if [ -f "$SRC_FILE" ]; then
    cp "$SRC_FILE" "$WORK_DIR/{basename}"
else
    echo "WARNING: Source file not found: $SRC_FILE"
fi""".format(
            short_path = src.short_path,
            src_path = src_path,
            basename = basename
        ))

    if not copy_commands:
        return "# All source files are from the module directory"

    return "\n".join(copy_commands)

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
    if hasattr(ctx.attr, '_tools') and ctx.files._tools:
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

def _read_provider_marker_action(ctx, plugin_dir, name_suffix = ""):
    """Reads provider marker file content at build time.

    Args:
        ctx: Rule context
        plugin_dir: Plugin marker file
        name_suffix: Optional suffix for output file name

    Returns:
        File containing the provider directory name
    """
    marker_content = ctx.actions.declare_file(ctx.label.name + name_suffix + "_provider_marker")

    ctx.actions.run_shell(
        outputs = [marker_content],
        inputs = [plugin_dir],
        command = "cat %s > %s" % (plugin_dir.path, marker_content.path),
        mnemonic = "ReadProviderMarker",
        progress_message = "Reading provider marker",
    )

    return marker_content

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

def _create_module_directory_action(ctx, srcs, module_files, name_suffix = ""):
    """Creates a working directory with all module files using Starlark actions."""
    work_dir = ctx.label.name + name_suffix + "_workspace"
    workspace_files = []

    # Copy source files
    for src in srcs:
        dest_file = ctx.actions.declare_file(work_dir + "/" + src.basename)
        ctx.actions.symlink(output = dest_file, target_file = src)
        workspace_files.append(dest_file)

    # Copy module files if different from source files
    for module_file in module_files:
        # Check if already copied as source file
        already_copied = False
        for src in srcs:
            if src.basename == module_file.basename:
                already_copied = True
                break

        if not already_copied:
            dest_file = ctx.actions.declare_file(work_dir + "/" + module_file.basename)
            ctx.actions.symlink(output = dest_file, target_file = module_file)
            workspace_files.append(dest_file)

    return workspace_files

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
            output_file.path
        ),
        env = env,
        mnemonic = "TerraformRun",
        progress_message = "Running terraform %s" % " ".join(args),
    )

    return output_file


def _generate_provider_search_candidates(provider_dir_name):
    """Generate provider search path candidates in Starlark.

    Args:
        provider_dir_name: Placeholder for provider directory name

    Returns:
        List of candidate path patterns with placeholder
    """
    prefixes = ["_main/external", "external", "../external"]
    repos = ["rules_tf2~~tf_providers~tf_provider_registry", "tf2~~tf_providers~tf_provider_registry", "tf_provider_registry"]

    candidates = []
    for prefix in prefixes:
        for repo in repos:
            candidates.append("$RUNFILES/{}/{}/{}".format(prefix, repo, provider_dir_name))

    return candidates

def _create_cli_config_content(path_placeholder):
    """Create terraform CLI configuration content.

    Args:
        path_placeholder: Placeholder for the path

    Returns:
        CLI configuration template string
    """
    return """provider_installation {{
  filesystem_mirror {{
    path = "{}"
  }}
}}
disable_checkpoint = true
""".format(path_placeholder)