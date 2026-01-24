"""Rule to create filtered provider mirrors for TFC agent images.

This module provides rules to filter the full provider mirror to only include
specific providers, either by explicit alias list or by extracting providers
from a tf_module's dependencies.
"""

load("//tf2/providers/core:info.bzl", "TfModuleInfo", "TfProviderConfigurationsInfo")
load("//tf2/tools/runners:sh_toolchain.bzl", "SH_TOOLCHAIN_TYPE", "run_shell")

def _parse_provider_alias(alias):
    """Parse a provider alias to extract name and major version.

    Args:
        alias: Provider alias like "aws_6" or "random_3"

    Returns:
        Tuple of (provider_name, major_version) or None if invalid
    """
    parts = alias.rsplit("_", 1)
    if len(parts) != 2:
        return None
    return (parts[0], parts[1])

def _spec_to_alias(provider_name, spec):
    """Convert provider spec to alias.

    Args:
        provider_name: Provider name (e.g., "aws")
        spec: Spec string (e.g., "hashicorp/aws:6.26.0")

    Returns:
        Alias like "aws_6"
    """
    # spec format: "namespace/provider:version" or just "version"
    if ":" in spec:
        version = spec.split(":")[-1]
    else:
        version = spec
    major_version = version.split(".")[0]
    return "{}_{}".format(provider_name, major_version)

def _file_matches_provider(file_path, provider_name, major_version):
    """Check if a provider file path matches the expected provider/version.

    Args:
        file_path: Full path to provider zip file
        provider_name: Provider name (e.g., "aws")
        major_version: Major version (e.g., "6")

    Returns:
        True if file matches, False otherwise
    """
    # Files are like: registry.terraform.io/hashicorp/aws/terraform-provider-aws_6.26.0_linux_amd64.zip
    # Check if path contains the provider name directory
    if "/{}/".format(provider_name) not in file_path:
        return False

    # Extract filename and check version
    filename = file_path.split("/")[-1]

    # Expected format: terraform-provider-{name}_{version}_{platform}.zip
    if not filename.startswith("terraform-provider-{}".format(provider_name)):
        return False

    # Extract version from filename
    # terraform-provider-aws_6.26.0_linux_amd64.zip
    version_part = filename.split("_")[1] if "_" in filename else ""
    if not version_part:
        return False

    file_major = version_part.split(".")[0]
    return file_major == major_version

def _filtered_provider_mirror_impl(ctx):
    """Implementation of filtered_provider_mirror rule.

    Filters the full provider mirror to only include specified providers.
    """
    staging_dir = ctx.actions.declare_directory("{}_filtered".format(ctx.attr.name))

    # Determine which provider aliases to include
    aliases = []

    if ctx.attr.provider_aliases:
        # Explicit list provided
        aliases = ctx.attr.provider_aliases
    elif ctx.attr.module:
        # Extract from tf_module
        module_info = ctx.attr.module[TfModuleInfo]

        # Get provider configurations - provider_configurations is a label to a target
        # that provides TfProviderConfigurationsInfo
        if module_info.provider_configurations:
            # Access the TfProviderConfigurationsInfo provider from the target
            if TfProviderConfigurationsInfo in module_info.provider_configurations:
                config_info = module_info.provider_configurations[TfProviderConfigurationsInfo]
                # config_info.providers is Dict[name, spec] like {"aws": "hashicorp/aws:6.26.0"}
                for provider_name, spec in config_info.providers.items():
                    alias = _spec_to_alias(provider_name, spec)
                    aliases.append(alias)

    if not aliases and not ctx.attr.module:
        fail("Must specify either provider_aliases or module")

    # Collect all provider files from the full mirror
    provider_files = ctx.files.full_mirror
    included_files = []

    # Build shell commands to copy matching files
    commands = ["set -e", "mkdir -p '{}'".format(staging_dir.path)]

    # Track which providers we found
    found_providers = {}

    for f in provider_files:
        src_path = f.path

        # Skip non-registry files
        if "registry.terraform.io" not in src_path:
            continue

        # Check if this file matches any of our aliases
        matched = False

        # Match by alias (works for both explicit list and module extraction)
        for alias in aliases:
            parsed = _parse_provider_alias(alias)
            if parsed:
                name, major = parsed
                if _file_matches_provider(src_path, name, major):
                    matched = True
                    found_providers[alias] = True
                    break

        if matched:
            # Extract relative path from registry.terraform.io onwards
            idx = src_path.find("registry.terraform.io")
            rel_path = src_path[idx:]
            dest_dir = staging_dir.path + "/" + rel_path.rsplit("/", 1)[0]
            commands.append("mkdir -p '{}'".format(dest_dir))
            commands.append("cp -L '{}' '{}/{}'".format(f.path, staging_dir.path, rel_path))
            included_files.append(f)

    # Verify we found all requested providers
    if aliases:
        missing = [a for a in aliases if a not in found_providers]
        if missing:
            fail("Could not find providers for aliases: {}. Available providers may not include these versions.".format(missing))

    # If no files matched, create an empty directory
    if not included_files:
        commands.append("# No providers matched, creating empty staging")

    run_shell(
        ctx,
        inputs = included_files if included_files else provider_files,
        outputs = [staging_dir],
        command = "\n".join(commands),
        mnemonic = "FilterProviderMirror",
        progress_message = "Filtering provider mirror for %s" % ctx.label,
    )

    return [DefaultInfo(files = depset([staging_dir]))]

filtered_provider_mirror = rule(
    implementation = _filtered_provider_mirror_impl,
    attrs = {
        "full_mirror": attr.label(
            mandatory = True,
            allow_files = True,
            doc = "Full provider mirror to filter from (e.g., @tf_provider_registry//:mirror_linux_amd64)",
        ),
        "provider_aliases": attr.string_list(
            doc = "List of provider aliases to include (e.g., ['aws_6', 'random_3'])",
        ),
        "module": attr.label(
            providers = [TfModuleInfo],
            doc = "tf_module to extract providers from",
        ),
    },
    toolchains = [SH_TOOLCHAIN_TYPE],
    doc = """Creates a filtered provider mirror containing only specified providers.

Accepts either:
- provider_aliases: Explicit list of provider aliases like ["aws_6", "random_3"]
- module: A tf_module label to extract providers from

The output is a directory with the same structure as the full mirror, but
containing only the matching provider files.
""",
)
