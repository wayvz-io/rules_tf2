"""Terraform validation test rule"""

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

    # Debug: print what files we got
    # print("DEBUG: validate_test {} got {} source files".format(ctx.label.name, len(source_files)))
    # for f in source_files:
    #     if "modules/" in f.short_path or f.basename.startswith("."):
    #         print("  - {}".format(f.short_path))

    # Import the staging function from tf_runner
    # We need to create a compatible context
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.label.name))

    # Build commands to create the staging directory
    copy_commands = []
    all_inputs = list(source_files)

    # Add lockfile if present
    if ctx.attr.lock_file and ctx.files.lock_file:
        lock_file = ctx.files.lock_file[0]
        copy_commands.append("cp -L '{}' '{}/.terraform.lock.hcl'".format(
            lock_file.path,
            staging_dir.path,
        ))
        all_inputs.append(lock_file)

    # Process source files - copy them to staging directory
    # Track directories we've created to avoid duplicate mkdir commands
    created_dirs = {}

    for src_file in source_files:
        src_path = src_file.short_path

        # Determine the destination path based on the source file location
        dest_path = src_file.basename  # Default to just the filename

        # Determine if this is a nested module file
        # Nested modules ONLY exist when:
        # 1. A module has been processed to include nested dependencies
        # 2. The nested modules are placed in a modules/ subdirectory WITHIN the package
        #
        # For example, if we're testing //iac/stacks/nw_lab:
        # - "iac/stacks/nw_lab/main.tf" -> main file, goes to root
        # - "iac/stacks/nw_lab/modules/workspace/main.tf" -> nested module, preserve modules/ structure
        #
        # But if we're testing //iac/modules/aws/flow_logs:
        # - "iac/modules/aws/flow_logs/main.tf" -> main file, goes to root
        # - There are no nested modules for this case

        test_package = ctx.label.package  # e.g., "iac/modules/aws/flow_logs" or "iac/stacks/nw_lab"

        # Check if this file is within the test package and has subdirectories
        if src_path.startswith(test_package + "/"):
            # Extract everything after the test package
            relative_path = src_path[len(test_package) + 1:]  # Remove package and leading /

            # If the file is in a subdirectory, preserve the directory structure
            if "/" in relative_path:
                dest_path = relative_path

                # Create parent directories if needed
                parts = relative_path.split("/")
                if len(parts) > 1:
                    dest_dir = "/".join(parts[:-1])
                    if dest_dir not in created_dirs:
                        copy_commands.append("mkdir -p '{}/{}'".format(staging_dir.path, dest_dir))
                        created_dirs[dest_dir] = True
            else:
                # File is directly in the package root
                dest_path = relative_path

        # Check if this is a bazel-out processed file with nested modules
        elif "bazel-out" in src_path and "/modules/" in src_path:
            # This is a processed file - extract the module structure
            parts = src_path.split("/")
            for i, part in enumerate(parts):
                if part == "modules" and i < len(parts) - 1:
                    # Found the modules directory, preserve structure from here
                    module_path = "/".join(parts[i:])
                    dest_path = module_path
                    # Create parent directories
                    dest_dir = "/".join(parts[i:-1])
                    if dest_dir not in created_dirs:
                        copy_commands.append("mkdir -p '{}/{}'".format(staging_dir.path, dest_dir))
                        created_dirs[dest_dir] = True
                    break

        # Otherwise, it's a file from outside the package - use just basename

        copy_commands.append("cp -L '{}' '{}/{}'".format(
            src_file.path,
            staging_dir.path,
            dest_path,
        ))

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

# Run terraform validate
$TERRAFORM_BIN validate -no-color
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
