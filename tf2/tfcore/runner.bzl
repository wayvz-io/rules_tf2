"""Terraform runner rule for executing terraform commands"""

load("//tf2/internal:staging.bzl", "prepare_staging_directory")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")
load(":variables.bzl", "TfVariablesInfo")

def _tf_runner_impl(ctx):
    """Implementation of tf_runner rule."""

    # Get the stack's files
    stack_info = ctx.attr.stack[TfModuleInfo]

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

    # Prepare staging directory with proper structure
    staging_dir, _ = prepare_staging_directory(ctx, stack_info, var_files, backend_config)

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

# Set Terraform environment
export TF_DISABLE_CHECKPOINT=true
export CHECKPOINT_DISABLE=true
export TF_IN_AUTOMATION=true
export TF_INPUT=false

# Set TFE host if using cloud backend
if [ "$BACKEND_TYPE" = "cloud" ] || [ "$BACKEND_TYPE" = "remote" ]; then
    export TFE_HOST="$TFE_HOST"
fi

cd "$STAGING_DIR"

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

# Run terraform command
case "$COMMAND" in
    init)
        terraform init $INIT_ARGS "$@"
        ;;
    plan)
        terraform plan $DEFAULT_PLAN_ARGS "$@"
        ;;
    apply)
        terraform apply $DEFAULT_APPLY_ARGS "$@"
        ;;
    *)
        terraform "$COMMAND" "$@"
        ;;
esac
"""

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

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_DIR="$SCRIPT_DIR/{staging_basename}"
RUNNER_SCRIPT="$SCRIPT_DIR/{runner_basename}"

# Check if runner script exists
if [ ! -f "$RUNNER_SCRIPT" ]; then
    echo "Error: Runner script not found at $RUNNER_SCRIPT"
    exit 1
fi

# Call the runner script with parameters
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
        default_command = '"%s"' % ctx.attr.default_command if ctx.attr.default_command else "",
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
            runfiles = ctx.runfiles(files = [staging_dir, runner_copy]),
        ),
    ]

tf_runner = rule(
    implementation = _tf_runner_impl,
    attrs = {
        "stack": attr.label(
            mandatory = True,
            providers = [TfModuleInfo],
            doc = "The tf_module target to run terraform commands against",
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
    },
    executable = True,
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
