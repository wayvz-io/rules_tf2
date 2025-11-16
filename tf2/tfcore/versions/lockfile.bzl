"""Rules for Terraform lock file management"""

def _tf_no_lockfile_check_test_impl(ctx):
    """Check that no .terraform.lock.hcl file exists in sources."""

    test_script = ctx.actions.declare_file(ctx.label.name + "_test.sh")

    # Check if any source file is a terraform.lock.hcl
    has_lockfile = False
    for src in ctx.files.srcs:
        if src.basename == ".terraform.lock.hcl":
            has_lockfile = True
            break

    if has_lockfile:
        script_content = """#!/usr/bin/env bash
set -euo pipefail

echo "ERROR: .terraform.lock.hcl should not be committed"
echo ""
echo "Terraform lock files are managed by Bazel versioning and should not be"
echo "committed to the repository. Please delete the .terraform.lock.hcl file."
echo ""
echo "The lockfile is automatically generated during build and test time."
exit 1
"""
    else:
        script_content = """#!/usr/bin/env bash
set -euo pipefail

echo "✓ No .terraform.lock.hcl file found in sources (correct)"
"""

    ctx.actions.write(
        output = test_script,
        content = script_content,
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = test_script,
            runfiles = ctx.runfiles(),
        ),
    ]

tf_no_lockfile_check_test = rule(
    implementation = _tf_no_lockfile_check_test_impl,
    test = True,
    attrs = {
        "srcs": attr.label_list(
            doc = "Source files to check for .terraform.lock.hcl",
            allow_files = True,
            mandatory = True,
        ),
    },
    doc = """Test that checks no .terraform.lock.hcl file exists in sources.""",
)

def _tf_generate_lock_file_impl(ctx):
    """Generate a .terraform.lock.hcl file from the uber lock file."""

    # Get the providers from Bazel module definitions
    providers_json = ctx.file.providers_json

    # Output lock file
    output_lock = ctx.actions.declare_file(".terraform.lock.hcl")

    # Use provider_locks.json directly (already in the format expected by hcl_tool)
    uber_lock_json = ctx.file.provider_locks

    # Use the hcl_tool with the converted JSON file
    args = ctx.actions.args()
    args.add("extract-module-lock")
    args.add("--versions", providers_json)
    args.add("--output", output_lock)
    args.add(uber_lock_json)

    ctx.actions.run(
        outputs = [output_lock],
        inputs = [uber_lock_json, providers_json],
        executable = ctx.executable._hcl_tool,
        arguments = [args],
        mnemonic = "GenerateLockFile",
        progress_message = "Generating .terraform.lock.hcl from uber lock file",
    )

    return [
        DefaultInfo(files = depset([output_lock])),
    ]

tf_generate_lock_file = rule(
    implementation = _tf_generate_lock_file_impl,
    attrs = {
        "provider_locks": attr.label(
            doc = "The provider_locks.json file with lock data",
            allow_single_file = [".json"],
            mandatory = True,
        ),
        "providers_json": attr.label(
            doc = "The provider specifications from Bazel module system",
            allow_single_file = [".json"],
            mandatory = True,
        ),
        "_hcl_tool": attr.label(
            default = "@rules_tf2//go/hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = """Generate a .terraform.lock.hcl file filtered to specific providers.""",
)

# Per-workspace lockfile management removed - lockfiles are now generated at build time only

def tf_generate_lockfile_for_validation(name, provider_locks = None, versions_json = None, **kwargs):
    """Generate a lockfile for validation purposes.

    This creates one target that generates a lockfile from the uber lock:
    - name: Generates the lockfile for use in validation

    Args:
        name: Name for the generated lockfile target
        provider_locks: The provider_locks.bzl file (defaults to centralized location)
        versions_json: The provider specifications from Bazel module system
        **kwargs: Additional arguments passed to rule
    """

    if not versions_json:
        fail("versions_json parameter is required")

    # Default provider locks location
    if not provider_locks:
        provider_locks = "@tf_provider_registry//:provider_locks.json"

    # Generate the lockfile for validation
    tf_generate_lock_file(
        name = name,
        provider_locks = provider_locks,
        providers_json = versions_json,
        **kwargs
    )
