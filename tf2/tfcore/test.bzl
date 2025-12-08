"""Terraform test execution rule"""

load("//tf2/internal:file_ops.bzl", "build_staging_copy_commands")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")
load("//tf2/tools/runners:tool_paths.bzl", "get_terraform_path")

def _tf_test_impl(ctx):
    """Implementation of tf_test rule.

    Creates a test that runs terraform test against a module.
    Uses TfModuleInfo to get staged module files, then adds test files.
    """
    module = ctx.attr.module
    if TfModuleInfo not in module:
        fail("module must be a tf_module target")

    module_info = module[TfModuleInfo]

    # Get terraform source files from the module
    module_files = module_info.srcs.to_list()

    # Get the lockfile
    lock_file = module_info.lock_file

    # Get test files
    test_files = ctx.files.test_files

    # Create staging directory
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.label.name))

    # Get module package for path calculation
    module_package = ctx.attr.module.label.package

    # Build copy commands using shared utility
    copy_commands = build_staging_copy_commands(
        source_files = module_files,
        staging_dir_path = staging_dir.path,
        package_path = module_package,
        lock_file = lock_file,
    )

    # Copy test files to staging root (flat copy - test-specific behavior)
    for test_file in test_files:
        copy_commands.append("cp -L '{}' '{}/{}'".format(
            test_file.path,
            staging_dir.path,
            test_file.basename,
        ))

    # Create the staging directory action
    all_inputs = module_files + test_files
    if lock_file:
        all_inputs = all_inputs + [lock_file]

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
        mnemonic = "PrepareTerraformTestStaging",
        progress_message = "Preparing Terraform test staging for %s" % ctx.label,
    )

    # Get terraform binary path
    terraform_bin = get_terraform_path(ctx)

    # Create the test script
    script = ctx.actions.declare_file("{}_test.sh".format(ctx.label.name))

    # Get provider registry path
    provider_mirror_path = ""
    if ctx.files.provider_registry:
        for f in ctx.files.provider_registry:
            if "mirror_linux" in f.path or "mirror_darwin" in f.path:
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

# CD to work directory
cd "$WORK_DIR"

# Set Terraform environment
export TF_DISABLE_CHECKPOINT=true
export CHECKPOINT_DISABLE=true
export TF_IN_AUTOMATION=true
export TF_INPUT=false

# Set up provider mirror if available
{provider_setup}

# Run terraform init and capture output for error detection
INIT_OUTPUT=$($TERRAFORM_BIN init -backend=false -upgrade=false -lockfile=readonly -no-color 2>&1) || true
INIT_EXIT_CODE=$?
echo "$INIT_OUTPUT"

# Check for empty directory initialization - this indicates a configuration problem
if echo "$INIT_OUTPUT" | grep -q "Terraform initialized in an empty directory"; then
    echo ""
    echo "ERROR: Terraform reports empty directory - no configuration files found"
    echo "This indicates the tf_test rule failed to stage source files correctly."
    echo ""
    echo "Debug info:"
    echo "  Staging directory: $STAGING_DIR"
    echo "  Work directory contents:"
    ls -la "$WORK_DIR" || true
    exit 1
fi

# Check if init failed for other reasons
if [ $INIT_EXIT_CODE -ne 0 ]; then
    echo "ERROR: terraform init failed with exit code $INIT_EXIT_CODE"
    exit $INIT_EXIT_CODE
fi

# Run terraform test
$TERRAFORM_BIN test -no-color
""".format(
        staging_basename = staging_dir.basename,
        terraform_bin = terraform_bin,
        provider_setup = """
if [ -d "$RUNFILES/{provider_mirror_path}" ]; then
    cat > "$WORK_DIR/.terraformrc" <<EOF
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
    runfiles_files = [staging_dir, script] + ctx.files._tools + ctx.files.provider_registry

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

tf_test = rule(
    implementation = _tf_test_impl,
    attrs = {
        "module": attr.label(
            doc = "The tf_module target to test",
            providers = [TfModuleInfo],
            mandatory = True,
        ),
        "test_files": attr.label_list(
            allow_files = True,
            doc = "Test files (.tftest.hcl, .json, or any supporting data)",
            mandatory = True,
        ),
        "provider_registry": attr.label(
            doc = "Provider registry directory containing downloaded providers. If not specified, uses the global registry.",
            default = "@tf_provider_registry//:unpacked_providers",
            allow_files = True,
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = """Runs Terraform tests against a module.

This rule runs `terraform test` against a tf_module target.
It uses the module's staged files (including nested modules) and adds
test files to the working directory.

Example:
    tf_module(
        name = "my_module",
        srcs = glob(["*.tf"]) + ["README.md"],
        providers = ["@tf_provider_registry//:aws_5"],
    )

    tf_test(
        name = "my_module_test",
        module = ":my_module",
        test_files = [
            "validation.tftest.hcl",
            "test_fixtures.json",
        ],
    )
""",
)
