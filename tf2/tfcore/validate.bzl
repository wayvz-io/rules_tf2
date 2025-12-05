"""Terraform validation test rule"""

load("//tf2/internal:file_ops.bzl", "build_staging_copy_commands")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")
load("//tf2/tools/runners:tool_paths.bzl", "get_terraform_path")

def _tf_validate_test_impl(ctx):
    """Implementation of tf_validate_test rule"""

    # Get the actual source files
    # If srcs contains a tf_module (via _processed filegroup), get files from TfModuleInfo
    # Otherwise use ctx.files.srcs directly
    source_files = []

    # Check if any of the srcs has TfModuleInfo (this happens when srcs = [":name_processed"])
    # Note: When srcs is a filegroup, the files won't have TfModuleInfo and we'll use ctx.files.srcs
    has_module_info = False
    for src in ctx.attr.srcs:
        if TfModuleInfo in src:
            # This is a tf_module - get all files from its srcs depset
            source_files.extend(src[TfModuleInfo].srcs.to_list())
            has_module_info = True

    # If no TfModuleInfo found, use all files from srcs
    # This handles both regular file lists and filegroups
    if not has_module_info:
        source_files = ctx.files.srcs

    # Create staging directory
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.label.name))

    # Build copy commands using shared utility
    copy_commands = build_staging_copy_commands(source_files, staging_dir.path, ctx.label.package)
    all_inputs = list(source_files)

    # Add lockfile if present (handled separately since it has special naming)
    if ctx.attr.lock_file and ctx.files.lock_file:
        lock_file = ctx.files.lock_file[0]
        copy_commands.insert(0, "cp -L '{}' '{}/.terraform.lock.hcl'".format(
            lock_file.path,
            staging_dir.path,
        ))
        all_inputs.append(lock_file)

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
        mnemonic = "PrepareTerraformValidationStaging",
        progress_message = "Preparing Terraform validation staging for %s" % ctx.label,
    )

    # Get terraform binary path
    terraform_bin = get_terraform_path(ctx)

    # Create the validation script
    script = ctx.actions.declare_file("{}_test.sh".format(ctx.label.name))

    # Get provider registry path if available
    provider_mirror_path = ""
    if ctx.attr.provider_registry and ctx.files.provider_registry:
        # Find the mirror directory in the provider registry files
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
# Use /. pattern to include hidden files like .terraform.lock.hcl
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

# Run terraform init with backend disabled for validation
$TERRAFORM_BIN init -backend=false -upgrade=false -lockfile=readonly -no-color

# Run terraform validate with JSON output to detect warnings
VALIDATE_OUTPUT=$($TERRAFORM_BIN validate -json -no-color 2>&1) || true

# Check if we got valid JSON
if ! echo "$VALIDATE_OUTPUT" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: Terraform validate did not return valid JSON"
    echo "Output was:"
    echo "$VALIDATE_OUTPUT"
    exit 1
fi

VALIDATE_VALID=$(echo "$VALIDATE_OUTPUT" | jq -r '.valid // "false"')

# Filter out known acceptable warnings:
# - "Redundant empty provider block" is expected for modules with provider aliases
FILTERED_WARNINGS=$(echo "$VALIDATE_OUTPUT" | jq '[.diagnostics[]? | select(.severity == "warning") | select(.summary != "Redundant empty provider block")]')
VALIDATE_WARNINGS=$(echo "$FILTERED_WARNINGS" | jq 'length')
VALIDATE_ERRORS=$(echo "$VALIDATE_OUTPUT" | jq '[.diagnostics[]? | select(.severity == "error")] | length')

# Show any diagnostics (including filtered ones for visibility)
ALL_DIAGNOSTICS=$(echo "$VALIDATE_OUTPUT" | jq '[.diagnostics[]?] | length')
if [ "$ALL_DIAGNOSTICS" -gt 0 ]; then
    echo "Terraform validation diagnostics:"
    echo "$VALIDATE_OUTPUT" | jq -r '.diagnostics[] | "  \\(.severity | ascii_upcase): \\(.summary)\\n    \\(.detail // "No details")\\n    at \\(.range.filename // "unknown"):\\(.range.start.line // 0)"'

    # Note if we filtered any warnings
    SKIPPED=$((ALL_DIAGNOSTICS - VALIDATE_WARNINGS - VALIDATE_ERRORS))
    if [ "$SKIPPED" -gt 0 ]; then
        echo ""
        echo "Note: $SKIPPED warning(s) were skipped (known acceptable patterns)"
    fi
fi

# Fail on errors
if [ "$VALIDATE_VALID" != "true" ]; then
    echo "ERROR: Terraform validation failed with errors"
    exit 1
fi

# Fail on actionable warnings (after filtering)
if [ "$VALIDATE_WARNINGS" -gt 0 ]; then
    echo "ERROR: Terraform validation produced $VALIDATE_WARNINGS actionable warning(s)"
    exit 1
fi

echo "Terraform validation passed (no errors or warnings)"
""".format(
        staging_basename = staging_dir.basename,
        terraform_bin = terraform_bin,
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

tf_validate_test = rule(
    implementation = _tf_validate_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files",
            mandatory = True,
        ),
        "versions_file": attr.label(
            allow_single_file = [".tf", ".tf.json"],
            doc = "terraform.tf versions file",
        ),
        "lock_file": attr.label(
            allow_single_file = [".terraform.lock.hcl"],
            doc = "Terraform lock file",
        ),
        "provider_registry": attr.label(
            doc = "Provider registry directory containing downloaded providers",
            allow_files = True,
        ),
        "_tools": attr.label(
            default = "@tf_tool_registry//:all",
            allow_files = True,
        ),
    },
    test = True,
    doc = "Validates Terraform configuration",
)
