"""General-purpose Terraform runner rule for executing terraform commands."""

load("//tf2/internal:file_ops.bzl", "build_staging_copy_commands")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")
load("//tf2/tfcore:variables.bzl", "TfVariablesInfo")
load("//tf2/tools/runners:sh_toolchain.bzl", "SH_TOOLCHAIN_TYPE", "run_shell")
load("//tf2/tools/runners:tool_paths.bzl", "get_terraform_path")

def _tf_runner_impl(ctx):
    """Implementation of tf_runner rule."""

    # Get the stack's files
    stack_info = ctx.attr.stack[TfModuleInfo]
    srcs = stack_info.srcs.to_list()

    # Get variable files if provided
    var_files = []
    if ctx.attr.variables:
        variables_info = ctx.attr.variables[TfVariablesInfo]
        var_files = variables_info.all_files

    # Generate backend configuration if needed
    backend_config = None
    if ctx.attr.backend_type == "cloud":
        backend_config = """terraform {{
  cloud {{
    organization = "{organization}"

    workspaces {{
      name = "{workspace}"
    }}
  }}
}}""".format(
            organization = ctx.attr.backend_organization,
            workspace = ctx.attr.backend_workspace,
        )
    elif ctx.attr.backend_type == "remote":
        backend_config = """terraform {{
  backend "remote" {{
    organization = "{organization}"

    workspaces {{
      name = "{workspace}"
    }}
  }}
}}""".format(
            organization = ctx.attr.backend_organization,
            workspace = ctx.attr.backend_workspace,
        )

    # Create staging directory
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.attr.name))

    # Build copy commands using shared utility
    copy_commands = build_staging_copy_commands(
        source_files = srcs,
        staging_dir_path = staging_dir.path,
        package_path = ctx.attr.stack.label.package,
        var_files = var_files,
        lock_file = stack_info.lock_file,
        rename_tfvars = True,  # TFC compatibility
    )

    # Create backend file if config provided (handled separately since it needs to be written)
    backend_file = None
    if backend_config:
        backend_file = ctx.actions.declare_file("{}_backend_override.tf".format(ctx.attr.name))
        ctx.actions.write(
            output = backend_file,
            content = backend_config,
        )
        copy_commands.append("cp -L '{}' '{}/backend_override.tf'".format(
            backend_file.path,
            staging_dir.path,
        ))

    # Prepare all inputs
    all_inputs = srcs + var_files
    if backend_file:
        all_inputs = all_inputs + [backend_file]
    if stack_info.lock_file:
        all_inputs = all_inputs + [stack_info.lock_file]

    # Create the staging directory
    run_shell(
        ctx,
        inputs = all_inputs,
        outputs = [staging_dir],
        command = """
set -euo pipefail
mkdir -p '{staging_dir}'
{copy_commands}
""".format(
            staging_dir = staging_dir.path,
            copy_commands = "\n".join(copy_commands),
        ),
        mnemonic = "PrepareTerraformStaging",
        progress_message = "Preparing Terraform staging for %s" % ctx.label,
    )

    # Get terraform binary path
    terraform_bin = get_terraform_path(ctx)

    # Generate the terraform runner script inline
    runner_copy = ctx.actions.declare_file("{}_terraform_runner.sh".format(ctx.attr.name))

    # Create embedded terraform runner script
    runner_content = """#!/usr/bin/env bash
set -euo pipefail

STAGING_DIR="$1"
BACKEND_TYPE="$2"
TFE_HOST="$3"
INIT_ARGS="$4"
DEFAULT_PLAN_ARGS="$5"
DEFAULT_APPLY_ARGS="$6"
DEFAULT_COMMAND="$7"
shift 7

# Use terraform binary from runfiles (RUNFILES env var is set by wrapper)
TERRAFORM_BIN="{terraform_bin}"

# Set Terraform environment
export TF_DISABLE_CHECKPOINT=true
export CHECKPOINT_DISABLE=true
export TF_IN_AUTOMATION=true
export TF_INPUT=false

# Set TFE host if using cloud backend
if [ "$BACKEND_TYPE" = "cloud" ] || [ "$BACKEND_TYPE" = "remote" ]; then
    export TFE_HOST="$TFE_HOST"
fi

# Create a temporary work directory (staging dir is read-only)
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Copy all files from staging directory to work directory (with write permissions)
# Use /. pattern to include hidden files like .terraform.lock.hcl
cp -r "$STAGING_DIR"/. "$WORK_DIR/"
# Make all copied files writable
chmod -R u+w "$WORK_DIR"

# CD to work directory
cd "$WORK_DIR"

# Determine command to run
if [ $# -eq 0 ] && [ -n "$DEFAULT_COMMAND" ]; then
    set -- "$DEFAULT_COMMAND"
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <terraform-command> [args...]"
    echo "Available commands: init, plan, apply, destroy, validate, fmt, etc."
    exit 1
fi

COMMAND="$1"
shift

# Run terraform command (always init first for commands that need it)
case "$COMMAND" in
    init)
        $TERRAFORM_BIN init $INIT_ARGS "$@"
        ;;
    plan|apply|validate)
        # Always init first for these commands
        $TERRAFORM_BIN init $INIT_ARGS
        case "$COMMAND" in
            plan)
                $TERRAFORM_BIN plan $DEFAULT_PLAN_ARGS "$@"
                ;;
            apply)
                $TERRAFORM_BIN apply $DEFAULT_APPLY_ARGS "$@"
                ;;
            validate)
                $TERRAFORM_BIN validate "$@"
                ;;
        esac
        ;;
    *)
        # Other commands don't need init
        $TERRAFORM_BIN "$COMMAND" "$@"
        ;;
esac
""".format(
        terraform_bin = terraform_bin,
    )

    ctx.actions.write(
        output = runner_copy,
        content = runner_content,
        is_executable = True,
    )

    # Create the wrapper script
    runner_script = ctx.actions.declare_file("{}_runner.sh".format(ctx.attr.name))

    # Build a wrapper script that calls the copied runner script
    wrapper_content = """#!/usr/bin/env bash
set -euo pipefail

# Get the script directory and name
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
STAGING_DIR="$SCRIPT_DIR/{staging_basename}"
RUNNER_SCRIPT="$SCRIPT_DIR/{runner_basename}"

# Set up runfiles (based on script name, not directory)
export RUNFILES="${{RUNFILES:-$SCRIPT_DIR/$SCRIPT_NAME.runfiles}}"

# Check if runner script exists
if [ ! -f "$RUNNER_SCRIPT" ]; then
    echo "Error: Runner script not found at $RUNNER_SCRIPT"
    exit 1
fi

# Call the runner script with parameters (RUNFILES is exported above)
exec "$RUNNER_SCRIPT" \\
    "$STAGING_DIR" \\
    "{backend_type}" \\
    "{tfe_host}" \\
    "{init_args}" \\
    "{default_plan_args}" \\
    "{default_apply_args}" \\
    {default_command} "$@"
""".format(
        staging_basename = staging_dir.basename,
        runner_basename = runner_copy.basename,
        backend_type = ctx.attr.backend_type or "",
        tfe_host = ctx.attr.tfe_host or "app.terraform.io",
        init_args = ctx.attr.init_args or "",
        default_plan_args = ctx.attr.default_plan_args or "",
        default_apply_args = ctx.attr.default_apply_args or "",
        default_command = '"%s"' % ctx.attr.default_command if ctx.attr.default_command else '""',
    )

    ctx.actions.write(
        output = runner_script,
        content = wrapper_content,
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([runner_script, staging_dir, runner_copy]),
            executable = runner_script,
            runfiles = ctx.runfiles(
                files = [staging_dir, runner_copy] + ctx.files._tools,
            ),
        ),
    ]

tf_runner = rule(
    implementation = _tf_runner_impl,
    attrs = {
        "stack": attr.label(
            mandatory = True,
            providers = [TfModuleInfo],
            doc = "The tf_stack target to run terraform commands against",
        ),
        "variables": attr.label(
            providers = [TfVariablesInfo],
            doc = "tf_variables target containing tfvars files",
        ),
        "backend_type": attr.string(
            values = ["cloud", "remote", "local", ""],
            default = "",
            doc = "Type of backend to configure (cloud, remote, local, or empty for no backend)",
        ),
        "backend_organization": attr.string(
            doc = "Organization for cloud/remote backend",
        ),
        "backend_workspace": attr.string(
            doc = "Workspace name for cloud/remote backend",
        ),
        "tfe_host": attr.string(
            default = "app.terraform.io",
            doc = "Terraform Enterprise/Cloud hostname",
        ),
        "init_args": attr.string(
            doc = "Additional arguments to pass to terraform init",
        ),
        "default_plan_args": attr.string(
            doc = "Default arguments for terraform plan when no args provided",
        ),
        "default_apply_args": attr.string(
            doc = "Default arguments for terraform apply when no args provided",
        ),
        "default_command": attr.string(
            doc = "Default command to run (e.g., 'plan' or 'apply') when no command is specified",
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    executable = True,
    toolchains = [SH_TOOLCHAIN_TYPE],
    doc = """General-purpose Terraform runner for executing terraform commands.
    
    This rule creates an executable target that can run any terraform command
    against the provided stack and variables.
    
    Example:
        tf_runner(
            name = "my_stack_runner",
            stack = ":my_stack",
            variables = ":my_vars",
            backend_type = "cloud",
            backend_organization = "my-org",
            backend_workspace = "my-workspace",
        )
        
        # Then run:
        # bazel run //path:my_stack_runner -- plan
        # bazel run //path:my_stack_runner -- apply
        # bazel run //path:my_stack_runner -- state list
        # bazel run //path:my_stack_runner -- taint resource.name
    """,
)
