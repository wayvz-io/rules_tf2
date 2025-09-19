"""Terraform validation and organization rules using tflint"""

load("//tf2/core/rules:info.bzl", "TfProviderConfigurationsInfo")
load("//tf2/utilities/utils:runfiles.bzl", "get_runfiles_dir_script", "get_workspace_dir_script", "create_runfiles_path")
load("//tf2/testing:tflint_defaults.bzl", "get_base_rules", "get_tagged_overrides", "merge_rule_configs")

def _generate_tflint_config_content(module_tags = None):
    """Generate tflint configuration content using the defaults system

    Args:
        module_tags: List of tags to apply rule overrides (e.g., ["test_module"])

    Returns:
        String containing the tflint configuration
    """
    # Start with base rules
    rules = get_base_rules()

    # Apply tagged overrides if provided
    if module_tags:
        for tag in module_tags:
            tag_overrides = get_tagged_overrides(tag)
            if tag_overrides:
                rules = merge_rule_configs(rules, tag_overrides)

    # Build config content
    config_lines = []

    # Add global config
    config_lines.append("# Auto-generated tflint configuration for tf2")
    config_lines.append("")
    config_lines.append("config {")
    config_lines.append("  call_module_type = \"none\"  # Don't validate module calls since Bazel handles module processing")
    config_lines.append("  force = false")
    config_lines.append("}")
    config_lines.append("")

    # Add rule blocks
    for rule_name, rule_config in rules.items():
        config_lines.append("rule \"{}\" {{".format(rule_name))
        for key, value in rule_config.items():
            if type(value) == "bool":
                config_lines.append("  {} = {}".format(key, "true" if value else "false"))
            elif type(value) == "string":
                config_lines.append("  {} = \"{}\"".format(key, value))
            else:
                config_lines.append("  {} = {}".format(key, value))
        config_lines.append("}")
        config_lines.append("")

    return "\n".join(config_lines)

def _tf_tflint_validate_test_impl(ctx):
    """Implementation of tf_tflint_validate_test rule using hybrid hcl_tool + tflint approach"""

    # Get the generated versions file from provider_configurations if provided
    versions_file = None
    if ctx.attr.provider_configurations:
        provider_info = ctx.attr.provider_configurations[TfProviderConfigurationsInfo]
        if provider_info.versions_file:
            versions_file = provider_info.versions_file

    # Get binaries
    tflint = ctx.attr._tflint[DefaultInfo].files_to_run.executable
    hcl_tool = ctx.attr._hcl_tool[DefaultInfo].files_to_run.executable

    # Create .tflint.hcl configuration file
    tflint_config = ctx.actions.declare_file(ctx.label.name + "_tflint.hcl")

    # Generate configuration content using defaults system
    # Apply test_module tag for more relaxed rules since these are validation tests
    config_content = _generate_tflint_config_content(module_tags = ["test_module"])

    ctx.actions.write(
        output = tflint_config,
        content = config_content,
    )

    # Create test executable that runs both hcl_tool validation and tflint
    test_file = ctx.actions.declare_file(ctx.label.name + "_test.sh")

    # Find a main module file (not from nested modules) to determine SOURCE_DIR
    main_file = None
    terraform_tf_file = None
    package_prefix = ctx.label.package + "/"
    for src_file in ctx.files.srcs:
        path = src_file.short_path
        # Look for terraform.tf or main.tf that's not in a modules/ subdirectory relative to package root
        if (path.endswith("/terraform.tf") or path.endswith("terraform.tf") or path.endswith("/main.tf") or path.endswith("main.tf")):
            # Get the relative path from the package root
            if path.startswith(package_prefix):
                relative_path = path[len(package_prefix):]
                # Check if it's not in a modules/ subdirectory
                if "/modules/" not in relative_path:
                    if path.endswith("terraform.tf"):
                        terraform_tf_file = path
                    elif not main_file:  # Only set main_file if we haven't found terraform.tf
                        main_file = path
    # Prefer terraform.tf over main.tf
    if terraform_tf_file:
        main_file = terraform_tf_file
    if not main_file and ctx.files.srcs:
        # Fallback to first file if no main file found
        main_file = ctx.files.srcs[0].short_path
    srcs_0 = main_file if main_file else "."

    # Build script content
    script_content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}

# Get the directory containing the source files
SOURCE_DIR="$(dirname "{srcs_0}")"
CONFIG_FILE="$RUNFILES/_main/{config_file}"
TFLINT="$RUNFILES/_main/{tflint}"
HCL_TOOL="$RUNFILES/_main/{hcl_tool}"

# Run hcl_tool validation for versions and organization if we have expected versions
{version_validation}

{organization_validation}

# Run tflint for standard checks
if ! "$TFLINT" --config="$CONFIG_FILE" --chdir="$SOURCE_DIR"; then
    echo "" >&2
    echo "ERROR: TFLint standard validation failed" >&2
    exit 1
fi

echo "All validations passed"
exit 0
""".format(
        runfiles_script = get_runfiles_dir_script(),
        tflint = tflint.short_path,
        hcl_tool = hcl_tool.short_path,
        config_file = tflint_config.short_path,
        srcs_0 = srcs_0,
        versions_file = versions_file.short_path if versions_file else "/dev/null",
        version_validation = (
            ('if ! "$HCL_TOOL" tflint-validate-versions "$SOURCE_DIR" < "$RUNFILES/_main/{versions_file}"; then\n' +
            '    echo "" >&2\n' +
            '    echo "ERROR: Terraform version validation failed" >&2\n' +
            '    echo "Run \'bazel run //{package}:{target_base}_generate_versions\' to update them" >&2\n' +
            '    exit 1\n' +
            'fi\n').format(
                versions_file = versions_file.short_path if versions_file else "/dev/null",
                package = ctx.label.package,
                target_base = ctx.label.name.replace("_tflint_validate_test", ""),
            ) if versions_file else "# No version validation (no provider_configurations specified)"
        ),
        organization_validation = (
            ('if ! "$HCL_TOOL" tflint-validate-organization "$SOURCE_DIR"; then\n' +
            '    echo "" >&2\n' +
            '    echo "ERROR: Terraform file organization validation failed" >&2\n' +
            '    echo "Run \'bazel run //{package}:{target_base}_reorganize\' to fix organization" >&2\n' +
            '    exit 1\n' +
            'fi\n').format(
                package = ctx.label.package,
                target_base = ctx.label.name.replace("_tflint_validate_test", ""),
            )
        )
    )

    ctx.actions.write(
        output = test_file,
        content = script_content,
        is_executable = True,
    )

    runfiles = [test_file, tflint_config, tflint, hcl_tool] + ctx.files.srcs
    if versions_file:
        runfiles.append(versions_file)

    tflint_runfiles = ctx.attr._tflint[DefaultInfo].default_runfiles.files
    hcl_tool_runfiles = ctx.attr._hcl_tool[DefaultInfo].default_runfiles.files

    return [
        DefaultInfo(
            files = depset([test_file]),
            executable = test_file,
            runfiles = ctx.runfiles(
                files = runfiles,
                transitive_files = depset(transitive = [tflint_runfiles, hcl_tool_runfiles]),
            ),
        ),
    ]

def _tf_tflint_fix_impl(ctx):
    """Implementation of tf_tflint_fix rule"""

    # Get the generated versions file from provider_configurations if provided
    versions_file = None
    if ctx.attr.provider_configurations:
        provider_info = ctx.attr.provider_configurations[TfProviderConfigurationsInfo]
        if provider_info.versions_file:
            versions_file = provider_info.versions_file

    # Get binaries
    tflint = ctx.attr._tflint[DefaultInfo].files_to_run.executable
    hcl_tool = ctx.attr._hcl_tool[DefaultInfo].files_to_run.executable

    # Create .tflint.hcl configuration file (same as validation)
    tflint_config = ctx.actions.declare_file(ctx.label.name + "_tflint.hcl")

    # Generate configuration content using defaults system
    # Apply test_module tag for more relaxed rules since these are fixing tests
    config_content = _generate_tflint_config_content(module_tags = ["test_module"])

    ctx.actions.write(
        output = tflint_config,
        content = config_content,
    )

    # Create script to fix issues in source directory
    script = ctx.actions.declare_file(ctx.label.name + "_fix.sh")

    script_content = """#!/usr/bin/env bash
set -euo pipefail

{workspace_script}

# Target directory for fixing
TARGET_DIR="$WORKSPACE_DIR/{package}"
CONFIG_FILE="{config_file}"
TFLINT="{tflint}"
HCL_TOOL="{hcl_tool}"

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: Directory $TARGET_DIR does not exist"
    exit 1
fi

echo "Fixing Terraform files in $TARGET_DIR using hybrid hcl_tool + TFLint approach..."

# Fix versions using hcl_tool if we have expected versions
{version_fix}

# Fix organization using hcl_tool
echo "Running hcl_tool reorganize..."
if "$HCL_TOOL" reorganize "$TARGET_DIR"; then
    echo "✓ Reorganized Terraform files"
else
    echo "⚠ No reorganization needed or files already organized"
fi

# Run tflint with --fix flag for standard issues
echo "Running TFLint --fix..."
if "$TFLINT" --config="$CONFIG_FILE" --fix --chdir="$TARGET_DIR"; then
    echo "✓ Applied TFLint auto-fixes"
else
    echo "⚠ No TFLint fixes needed or no auto-fixable issues found"
fi

echo "✅ Completed all fixes for $TARGET_DIR"
""".format(
        workspace_script = get_workspace_dir_script(),
        tflint = tflint.short_path,
        hcl_tool = hcl_tool.short_path,
        config_file = tflint_config.short_path,
        package = ctx.label.package,
        version_fix = (
            ('echo "Running hcl_tool update-versions..."\n' +
            'if "$HCL_TOOL" update-versions "$TARGET_DIR" < "{versions_file}"; then\n' +
            '    echo "✓ Updated Terraform versions"\n' +
            'else\n' +
            '    echo "⚠ No version updates needed or no expected versions specified"\n' +
            'fi\n').format(
                versions_file = versions_file.short_path if versions_file else "/dev/null"
            ) if versions_file else "# No version fixing (no provider_configurations specified)"
        )
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    runfiles = [script, tflint_config, tflint, hcl_tool]
    if versions_file:
        runfiles.append(versions_file)

    tflint_runfiles = ctx.attr._tflint[DefaultInfo].default_runfiles.files
    hcl_tool_runfiles = ctx.attr._hcl_tool[DefaultInfo].default_runfiles.files

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = ctx.runfiles(
                files = runfiles,
                transitive_files = depset(transitive = [tflint_runfiles, hcl_tool_runfiles]),
            ),
        ),
    ]

tf_tflint_validate_test = rule(
    implementation = _tf_tflint_validate_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files",
            mandatory = True,
        ),
        "provider_configurations": attr.label(
            doc = "Provider configurations to validate against (optional)",
            providers = [TfProviderConfigurationsInfo],
        ),
        "_tflint": attr.label(
            default = "@tf_tool_registry//:tflint",
            executable = True,
            cfg = "exec",
        ),
        "_hcl_tool": attr.label(
            default = "@rules_tf2//hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
    doc = "Tests that Terraform files pass hybrid hcl_tool + TFLint validation",
)

tf_tflint_fix = rule(
    implementation = _tf_tflint_fix_impl,
    attrs = {
        "provider_configurations": attr.label(
            doc = "Provider configurations to use for fixing (optional)",
            providers = [TfProviderConfigurationsInfo],
        ),
        "_tflint": attr.label(
            default = "@tf_tool_registry//:tflint",
            executable = True,
            cfg = "exec",
        ),
        "_hcl_tool": attr.label(
            default = "@rules_tf2//hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    executable = True,
    doc = "Fixes Terraform files using hybrid hcl_tool + TFLint approach",
)

def _tf_tflint_negative_test_impl(ctx):
    """Implementation of tf_tflint_negative_test rule that expects tflint validation to fail"""

    # Get the generated versions file from provider_configurations if provided
    versions_file = None
    if ctx.attr.provider_configurations:
        provider_info = ctx.attr.provider_configurations[TfProviderConfigurationsInfo]
        if provider_info.versions_file:
            versions_file = provider_info.versions_file

    # Get binaries
    tflint = ctx.attr._tflint[DefaultInfo].files_to_run.executable
    hcl_tool = ctx.attr._hcl_tool[DefaultInfo].files_to_run.executable

    # Create .tflint.hcl configuration file
    tflint_config = ctx.actions.declare_file(ctx.label.name + "_tflint.hcl")

    # Generate configuration content using defaults system
    # Use more strict rules for negative tests to ensure they catch issues
    config_content = _generate_tflint_config_content()  # No test_module tag for stricter rules

    ctx.actions.write(
        output = tflint_config,
        content = config_content,
    )

    # Create test executable that expects tflint validation to fail
    test_file = ctx.actions.declare_file(ctx.label.name + "_test.sh")

    # Find a main module file (not from nested modules) to determine SOURCE_DIR
    main_file = None
    terraform_tf_file = None
    package_prefix = ctx.label.package + "/"
    for src_file in ctx.files.srcs:
        path = src_file.short_path
        # Look for terraform.tf or main.tf that's not in a modules/ subdirectory relative to package root
        if (path.endswith("/terraform.tf") or path.endswith("terraform.tf") or path.endswith("/main.tf") or path.endswith("main.tf")):
            # Get the relative path from the package root
            if path.startswith(package_prefix):
                relative_path = path[len(package_prefix):]
                # Check if it's not in a modules/ subdirectory
                if "/modules/" not in relative_path:
                    if path.endswith("terraform.tf"):
                        terraform_tf_file = path
                    elif not main_file:  # Only set main_file if we haven't found terraform.tf
                        main_file = path
    # Prefer terraform.tf over main.tf
    if terraform_tf_file:
        main_file = terraform_tf_file
    if not main_file and ctx.files.srcs:
        # Fallback to first file if no main file found
        main_file = ctx.files.srcs[0].short_path
    srcs_0 = main_file if main_file else "."

    # Build script content - expects validation to FAIL
    script_content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}

# Get the directory containing the source files
SOURCE_DIR="$(dirname "{srcs_0}")"
CONFIG_FILE="$RUNFILES/_main/{config_file}"
TFLINT="$RUNFILES/_main/{tflint}"
HCL_TOOL="$RUNFILES/_main/{hcl_tool}"

# Run hcl_tool validation for versions and organization if we have expected versions
{version_validation}

{organization_validation}

# Run tflint for standard checks - EXPECT this to fail
if "$TFLINT" --config="$CONFIG_FILE" --chdir="$SOURCE_DIR"; then
    echo "" >&2
    echo "✗ Expected TFLint validation to fail but it passed (negative test failed)" >&2
    exit 1
else
    echo "✓ TFLint validation failed as expected (negative test passed)"
    exit 0
fi
""".format(
        runfiles_script = get_runfiles_dir_script(),
        tflint = tflint.short_path,
        hcl_tool = hcl_tool.short_path,
        config_file = tflint_config.short_path,
        srcs_0 = srcs_0,
        versions_file = versions_file.short_path if versions_file else "/dev/null",
        version_validation = (
            ('if ! "$HCL_TOOL" tflint-validate-versions "$SOURCE_DIR" < "$RUNFILES/_main/{versions_file}"; then\n' +
            '    echo "" >&2\n' +
            '    echo "ERROR: Terraform version validation failed" >&2\n' +
            '    echo "Run \'bazel run //{package}:{target_base}_generate_versions\' to update them" >&2\n' +
            '    exit 1\n' +
            'fi\n').format(
                versions_file = versions_file.short_path if versions_file else "/dev/null",
                package = ctx.label.package,
                target_base = ctx.label.name.replace("_tflint_negative_test", ""),
            ) if versions_file else "# No version validation (no provider_configurations specified)"
        ),
        organization_validation = (
            ('if ! "$HCL_TOOL" tflint-validate-organization "$SOURCE_DIR"; then\n' +
            '    echo "" >&2\n' +
            '    echo "ERROR: Terraform file organization validation failed" >&2\n' +
            '    echo "Run \'bazel run //{package}:{target_base}_reorganize\' to fix organization" >&2\n' +
            '    exit 1\n' +
            'fi\n').format(
                package = ctx.label.package,
                target_base = ctx.label.name.replace("_tflint_negative_test", ""),
            )
        )
    )

    ctx.actions.write(
        output = test_file,
        content = script_content,
        is_executable = True,
    )

    runfiles = [test_file, tflint_config, tflint, hcl_tool] + ctx.files.srcs
    if versions_file:
        runfiles.append(versions_file)

    tflint_runfiles = ctx.attr._tflint[DefaultInfo].default_runfiles.files
    hcl_tool_runfiles = ctx.attr._hcl_tool[DefaultInfo].default_runfiles.files

    return [
        DefaultInfo(
            files = depset([test_file]),
            executable = test_file,
            runfiles = ctx.runfiles(
                files = runfiles,
                transitive_files = depset(transitive = [tflint_runfiles, hcl_tool_runfiles]),
            ),
        ),
    ]

tf_tflint_negative_test = rule(
    implementation = _tf_tflint_negative_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files with intentional validation issues",
            mandatory = True,
        ),
        "provider_configurations": attr.label(
            doc = "Provider configurations to validate against (optional)",
            providers = [TfProviderConfigurationsInfo],
        ),
        "_tflint": attr.label(
            default = "@tf_tool_registry//:tflint",
            executable = True,
            cfg = "exec",
        ),
        "_hcl_tool": attr.label(
            default = "@rules_tf2//hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
    doc = "Tests that Terraform files with intentional issues are detected by TFLint (negative test)",
)