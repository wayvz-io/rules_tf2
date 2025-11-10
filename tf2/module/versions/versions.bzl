"""Terraform versions checking and generation rules"""

load("//tf2/providers/core:info.bzl", "TfProviderConfigurationsInfo", "TfProviderMirrorInfo", "TfProviderAliasInfo", "TfModuleInfo")
load("//tf2/tools/runners:shell_utils.bzl", "get_runfiles_dir_script", "get_workspace_dir_script")

def _tf_versions_check_test_impl(ctx):
    """Implementation of tf_versions_check_test rule"""

    # Get the generated versions file from provider_configurations
    if not ctx.attr.provider_configurations:
        fail("provider_configurations is required")

    provider_info = ctx.attr.provider_configurations[TfProviderConfigurationsInfo]
    if not provider_info.versions_file:
        fail("provider_configurations must generate a versions_file")

    generated_file = provider_info.versions_file
    
    # Get the hcl_tool binary
    hcl_tool = ctx.executable._hcl_tool

    # Create test executable that validates versions using HCL tool
    test_file = ctx.actions.declare_file(ctx.label.name + "_test.sh")
    
    # The source directory is where the .tf files are
    # We'll validate that the HCL content matches expected versions
    ctx.actions.write(
        output = test_file,
        content = """#!/usr/bin/env bash
set -euo pipefail

# Get the directory containing the source files
SOURCE_DIR="$(dirname "{srcs_0}")"

# Run the hcl_tool validate-versions command
# The generated_file contains the expected JSON configuration
if ! "{hcl_tool}" validate-versions "$SOURCE_DIR" < "{generated}"; then
    echo "" >&2
    echo "ERROR: Terraform versions do not match expected values" >&2
    echo "Run 'bazel run //{package}:{target_base}_generate_versions' to update them" >&2
    exit 1
fi

echo "Terraform versions are up to date"
exit 0
""".format(
            hcl_tool = hcl_tool.short_path,
            generated = generated_file.short_path,
            srcs_0 = ctx.files.srcs[0].short_path if ctx.files.srcs else ".",
            package = ctx.label.package,
            target_base = ctx.label.name.replace("_versions_check_test", ""),
        ),
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([test_file]),
            executable = test_file,
            runfiles = ctx.runfiles(
                files = [test_file, generated_file, hcl_tool] + ctx.files.srcs,
                transitive_files = ctx.attr._hcl_tool[DefaultInfo].default_runfiles.files,
            ),
        ),
    ]

def _tf_generate_versions_impl(ctx):
    """Implementation of tf_generate_versions rule"""

    # Get the generated versions file from provider_configurations
    if not ctx.attr.provider_configurations:
        fail("provider_configurations is required")

    provider_info = ctx.attr.provider_configurations[TfProviderConfigurationsInfo]
    if not provider_info.versions_file:
        fail("provider_configurations must generate a versions_file")

    # Get the hcl_tool binary
    hcl_tool = ctx.executable._hcl_tool

    # Create a symlink to the generated file for easier access
    versions_link = ctx.actions.declare_file("generated_versions.json")
    ctx.actions.symlink(
        output = versions_link,
        target_file = provider_info.versions_file,
    )

    # Create script to update versions in source directory using HCL tool
    script = ctx.actions.declare_file(ctx.label.name + "_generate.sh")

    script_content = """#!/usr/bin/env bash
set -euo pipefail

{workspace_script}

# Source and target paths
SOURCE_FILE="$0.runfiles/{versions_link}"
TARGET_DIR="$WORKSPACE_DIR/{package}"
HCL_TOOL="$0.runfiles/{hcl_tool}"

# Check if the source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "ERROR: Cannot find generated versions file at $SOURCE_FILE"
    exit 1
fi

# Create directory if needed
mkdir -p "$TARGET_DIR"

# Use hcl_tool to update versions in the directory
# This will either update existing .tf files or create versions.tf
"$HCL_TOOL" update-versions "$TARGET_DIR" < "$SOURCE_FILE"

echo "Updated Terraform versions in $TARGET_DIR"
""".format(
        workspace_script = get_workspace_dir_script(),
        versions_link = versions_link.short_path if versions_link.short_path.startswith("bazel-out/") else "_main/{}".format(versions_link.short_path),
        hcl_tool = hcl_tool.short_path if hcl_tool.short_path.startswith("bazel-out/") else "_main/{}".format(hcl_tool.short_path),
        package = ctx.label.package,
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([script, versions_link, hcl_tool]),
            executable = script,
            runfiles = ctx.runfiles(
                files = [versions_link, hcl_tool],
                transitive_files = ctx.attr._hcl_tool[DefaultInfo].default_runfiles.files,
            ),
        ),
    ]

tf_versions_check_test = rule(
    implementation = _tf_versions_check_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files",
            mandatory = True,
        ),
        "provider_configurations": attr.label(
            doc = "Provider configurations to validate against",
            providers = [TfProviderConfigurationsInfo],
        ),
        "_hcl_tool": attr.label(
            default = "@rules_tf2//hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
    doc = "Tests that Terraform versions match provider configurations",
)

tf_generate_versions = rule(
    implementation = _tf_generate_versions_impl,
    attrs = {
        "provider_configurations": attr.label(
            doc = "Provider configurations to generate versions from",
            providers = [TfProviderConfigurationsInfo],
            mandatory = True,
        ),
        "_hcl_tool": attr.label(
            default = "@rules_tf2//hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
    doc = "Updates Terraform versions in source directory",
)

def _tf_generate_versions_from_mirrors_impl(ctx):
    """Generate provider configurations from provider mirrors"""

    # Collect DIRECT provider information from mirrors or aliases
    direct_providers = {}
    for provider in ctx.attr.providers:
        if TfProviderMirrorInfo in provider:
            mirror_info = provider[TfProviderMirrorInfo]
            direct_providers[mirror_info.provider_name] = mirror_info.provider + ":" + mirror_info.version
        elif TfProviderAliasInfo in provider:
            alias_info = provider[TfProviderAliasInfo]
            direct_providers[alias_info.provider_name] = alias_info.provider + ":" + alias_info.version
        else:
            fail("Provider {} must be either a provider_mirror or provider_alias rule".format(provider.label))

    # Start with direct providers for aggregated providers
    aggregated_providers = dict(direct_providers)

    # Collect providers from modules (transitive dependencies) for aggregated list
    for module in ctx.attr.modules:
        if TfModuleInfo in module:
            module_info = module[TfModuleInfo]
            if module_info.provider_configurations:
                # The provider_configurations is a label to another tf_generate_versions_from_mirrors target
                if TfProviderConfigurationsInfo in module_info.provider_configurations:
                    config_info = module_info.provider_configurations[TfProviderConfigurationsInfo]
                    # Merge module providers into our aggregated providers dict
                    for name, spec in config_info.providers.items():
                        if name not in aggregated_providers:
                            aggregated_providers[name] = spec

    # Use the configured terraform version instead of detecting it
    # The version is passed from the tf_tools configuration in MODULE.bazel
    tf_version = ctx.attr.terraform_version or "1.0.0"
    
    # Declare output for terraform version
    tf_version_file = ctx.actions.declare_file(ctx.label.name + "_tf_version.txt")

    # Write the configured version to the file
    ctx.actions.write(
        output = tf_version_file,
        content = tf_version,
    )

    # Generate versions configuration JSON for HCL tool (using AGGREGATED providers with transitive deps)
    versions_file = ctx.actions.declare_file(ctx.label.name + "_versions.json")

    # Build the providers structure using AGGREGATED providers for terraform.tf validation
    required_providers = {}
    for name, spec in aggregated_providers.items():
        parts = spec.split(":")
        source = parts[0]
        version = parts[1]
        required_providers[name] = {
            "source": source,
            "version": version,
        }

    # Create an action to read version and generate JSON
    # This JSON will be consumed by the HCL tool to generate/update .tf files
    ctx.actions.run_shell(
        outputs = [versions_file],
        inputs = [tf_version_file],
        command = """
TF_VERSION=$(cat {version_file})
cat > {output} << EOF
{{
  "required_version": ">= $TF_VERSION",
  "required_providers": {providers}
}}
EOF
""".format(
            version_file = tf_version_file.path,
            output = versions_file.path,
            providers = json.encode_indent(required_providers, indent = "  "),
        ),
        mnemonic = "GenerateVersionsConfig",
    )

    return [
        DefaultInfo(files = depset([versions_file])),
        TfProviderConfigurationsInfo(
            providers = aggregated_providers,
            tf_version_constraint = ">= detected",
            versions_file = versions_file,
        ),
    ]

def _tf_versions_negative_test_impl(ctx):
    """Implementation of tf_versions_negative_test rule that expects version mismatches"""

    # Get the generated versions file from provider_configurations
    if not ctx.attr.provider_configurations:
        fail("provider_configurations is required")

    provider_info = ctx.attr.provider_configurations[TfProviderConfigurationsInfo]
    if not provider_info.versions_file:
        fail("provider_configurations must generate a versions_file")

    generated_file = provider_info.versions_file
    
    # Get the hcl_tool binary
    hcl_tool = ctx.executable._hcl_tool

    # Create test executable that validates versions mismatch is detected
    test_file = ctx.actions.declare_file(ctx.label.name + "_test.sh")
    
    ctx.actions.write(
        output = test_file,
        content = """#!/usr/bin/env bash
set -euo pipefail

# Get the directory containing the source files
SOURCE_DIR="$(dirname "{srcs_0}")"

# Run the hcl_tool validate-versions command
# We expect this to fail (exit code != 0) for a negative test
if "{hcl_tool}" validate-versions "$SOURCE_DIR" < "{generated}"; then
    echo "" >&2
    echo "✗ Expected version mismatch but versions matched (negative test failed)" >&2
    exit 1
else
    echo "✓ Found version mismatch as expected (negative test passed)"
    exit 0
fi
""".format(
            hcl_tool = hcl_tool.short_path,
            generated = generated_file.short_path,
            srcs_0 = ctx.files.srcs[0].short_path if ctx.files.srcs else ".",
        ),
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([test_file]),
            executable = test_file,
            runfiles = ctx.runfiles(
                files = [test_file, generated_file, hcl_tool] + ctx.files.srcs,
                transitive_files = ctx.attr._hcl_tool[DefaultInfo].default_runfiles.files,
            ),
        ),
    ]

tf_versions_negative_test = rule(
    implementation = _tf_versions_negative_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files with intentional version mismatches",
            mandatory = True,
        ),
        "provider_configurations": attr.label(
            doc = "Provider configurations to validate against",
            providers = [TfProviderConfigurationsInfo],
        ),
        "_hcl_tool": attr.label(
            default = "@rules_tf2//hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
    doc = "Tests that Terraform version mismatches are detected",
)

tf_generate_versions_from_mirrors = rule(
    implementation = _tf_generate_versions_from_mirrors_impl,
    attrs = {
        "providers": attr.label_list(
            doc = "List of provider_mirror or provider_alias targets",
            mandatory = True,
        ),
        "modules": attr.label_list(
            doc = "List of tf_module targets to collect transitive providers from",
            providers = [TfModuleInfo],
            default = [],
        ),
        "terraform_version": attr.string(
            doc = "Terraform version to use in required_version constraint",
            default = "1.0.0",
        ),
    },
    doc = "Generates provider configurations from provider mirrors",
)
