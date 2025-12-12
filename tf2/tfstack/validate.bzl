"""Terraform Stack validation test rule"""

load("//tf2/internal:file_ops.bzl", "build_staging_copy_commands")
load("//tf2/providers/core:info.bzl", "TfModuleInfo", "TfStackInfo")
load("//tf2/tfstack:nested.bzl", "process_stack_modules")
load("//tf2/tools/runners:tool_paths.bzl", "TOOLS_ATTR", "get_stacksplugin_path", "get_terraform_path")

def _tf_stack_validate_test_impl(ctx):
    """Implementation of tf_stack_validate_test rule"""

    stack_info = ctx.attr.stack[TfStackInfo]

    # Get component and deploy files
    component_files = stack_info.component_files.to_list()
    deploy_files = stack_info.deploy_files.to_list()
    data_files = stack_info.data_files.to_list()

    # Process modules and rewrite paths
    all_processed_files, _ = process_stack_modules(
        ctx,
        component_files,
        deploy_files,
        data_files,
        ctx.attr.stack[TfStackInfo].modules,
    )

    # Create staging directory
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.label.name))

    # Build copy commands for processed files
    copy_commands = []
    all_inputs = []
    created_dirs = {}

    for f in all_processed_files:
        # Determine destination path
        if f.path.endswith(".tfcomponent.hcl") or f.path.endswith(".tfdeploy.hcl") or f.path.endswith(".json"):
            # Root level files
            dest_path = f.basename
        elif "/components/" in f.path:
            # Extract components/... structure
            idx = f.path.find("/components/")
            dest_path = f.path[idx + 1:]  # Include "components/..."

            # Create parent directory
            parts = dest_path.split("/")
            if len(parts) > 1:
                dest_dir = "/".join(parts[:-1])
                if dest_dir not in created_dirs:
                    copy_commands.append("mkdir -p '{}/{}'".format(staging_dir.path, dest_dir))
                    created_dirs[dest_dir] = True
        else:
            dest_path = f.basename

        copy_commands.append("cp -L '{}' '{}/{}'".format(f.path, staging_dir.path, dest_path))
        all_inputs.append(f)

    # Add lockfile if present
    if stack_info.lock_file:
        copy_commands.insert(0, "cp -L '{}' '{}/.terraform.lock.hcl'".format(
            stack_info.lock_file.path,
            staging_dir.path,
        ))
        all_inputs.append(stack_info.lock_file)

    # Add .terraform-version file
    version_content = stack_info.terraform_version or "1.14.1"
    copy_commands.append("echo '{}' > '{}/.terraform-version'".format(version_content, staging_dir.path))

    # Create the staging directory
    ctx.actions.run_shell(
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
        mnemonic = "PrepareStackValidationStaging",
        progress_message = "Preparing Terraform Stack validation staging for %s" % ctx.label,
    )

    # Get terraform binary path
    terraform_bin = get_terraform_path(ctx)
    stacksplugin_bin = get_stacksplugin_path(ctx)

    # Create the validation script
    script = ctx.actions.declare_file("{}_test.sh".format(ctx.label.name))

    # Get provider registry path if available
    provider_mirror_path = ""
    if ctx.attr.provider_registry and ctx.files.provider_registry:
        for f in ctx.files.provider_registry:
            if "mirror_linux" in f.path:
                provider_mirror_path = f.dirname
                break

    script_content = """#!/usr/bin/env bash
set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_DIR="$SCRIPT_DIR/{staging_basename}"

# Set up runfiles
if [ -n "${{RUNFILES_DIR:-}}" ]; then
    RUNFILES="$RUNFILES_DIR"
elif [ -f "$0.runfiles_manifest" ]; then
    RUNFILES="$0.runfiles"
else
    RUNFILES="$0.runfiles"
fi

# Use terraform binary from runfiles
TERRAFORM_BIN="{terraform_bin}"

# Create a temporary work directory (staging dir is read-only)
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Copy all files from staging directory to work directory (with write permissions)
cp -r "$STAGING_DIR"/. "$WORK_DIR/"
chmod -R u+w "$WORK_DIR"

# Set up stacksplugin for terraform stacks commands
PLUGIN_DIR="$WORK_DIR/.terraform.d/stacksplugin"
mkdir -p "$PLUGIN_DIR"
cp "{stacksplugin_bin}" "$PLUGIN_DIR/tfstacks"
chmod +x "$PLUGIN_DIR/tfstacks"

# Point terraform to use our plugin directory
export HOME="$WORK_DIR"

# CD to work directory
cd "$WORK_DIR"

# Set Terraform environment
export TF_DISABLE_CHECKPOINT=true
export CHECKPOINT_DISABLE=true
export TF_IN_AUTOMATION=true
export TF_INPUT=false

# Set up provider mirror if available
{provider_setup}

# Run terraform stacks init
echo "Initializing Terraform Stack..."
$TERRAFORM_BIN stacks init -no-color

# Run terraform stacks validate
echo "Validating Terraform Stack..."
$TERRAFORM_BIN stacks validate -no-color

echo "Terraform Stack validation passed"
""".format(
        staging_basename = staging_dir.basename,
        terraform_bin = terraform_bin,
        stacksplugin_bin = stacksplugin_bin,
        provider_setup = """
if [ -d "$RUNFILES/{provider_mirror_path}" ]; then
    cat > "$WORK_DIR/.terraformrc" <<'EOF'
provider_installation {{
  filesystem_mirror {{
    path = "$RUNFILES/{provider_mirror_path}"
  }}
}}
disable_checkpoint = true
EOF
    export TF_CLI_CONFIG_FILE="$WORK_DIR/.terraformrc"
fi
""".format(provider_mirror_path = provider_mirror_path) if provider_mirror_path else "",
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Build runfiles
    runfiles_files = [staging_dir, script] + ctx.files._tools
    if ctx.attr.provider_registry:
        runfiles_files.extend(ctx.files.provider_registry)

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

tf_stack_validate_test = rule(
    implementation = _tf_stack_validate_test_impl,
    attrs = dict({
        "stack": attr.label(
            mandatory = True,
            providers = [TfStackInfo],
            doc = "The tf_stack target to validate",
        ),
        "provider_registry": attr.label(
            doc = "Provider registry directory containing downloaded providers",
            allow_files = True,
        ),
    }, **TOOLS_ATTR),
    test = True,
    doc = "Validates Terraform Stack configuration using terraform stacks validate",
)
