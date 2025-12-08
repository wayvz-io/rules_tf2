"""Repository rules for Terraform provider management"""

load("//tf2/providers/download:provider_http_files.bzl", "parse_terraform_lock_file")

def _generate_lock_hcl_from_json(lock_json):
    """Generate HCL content from parsed lock file JSON."""
    lines = [
        '# This file is maintained automatically by "terraform init".',
        "# Manual edits may be lost in future updates.",
        "",
    ]

    for provider_name, data in lock_json.items():
        # Ensure we have the full registry path
        full_name = provider_name
        if not full_name.startswith("registry.terraform.io/"):
            full_name = "registry.terraform.io/" + full_name

        lines.append('provider "{}" {{'.format(full_name))

        if data.get("version"):
            lines.append('  version     = "{}"'.format(data["version"]))

        if data.get("constraints"):
            lines.append('  constraints = "{}"'.format(data["constraints"]))

        hashes = data.get("hashes", [])
        if hashes:
            lines.append("  hashes = [")

            # Handle both list and dict formats
            if type(hashes) == "list":
                for hash_val in hashes:
                    lines.append('    "{}",'.format(hash_val))
            elif type(hashes) == "dict":
                # Combine all hashes from dict format
                all_hashes = []
                for hash_type, hash_list in hashes.items():
                    if hash_type != "platforms":  # Skip platform-specific mapping
                        for h in hash_list:
                            if hash_type in ["h1", "zh"]:
                                all_hashes.append("{}:{}".format(hash_type, h))
                            else:
                                all_hashes.append(h)
                for hash_val in all_hashes:
                    lines.append('    "{}",'.format(hash_val))
            lines.append("  ]")

        lines.append("}")
        lines.append("")

    return "\n".join(lines)

def _terraform_providers_impl(ctx):
    """Implementation of terraform_providers repository rule.

    This rule creates a BUILD file that references provider download repositories.
    Each provider/platform combination is a separate repository created by the module extension.
    """

    # Use provider hashes if provided, otherwise parse raw content
    provider_info = {}
    lock_file_content = ""
    if ctx.attr.provider_hashes:
        # Reconstruct provider_info from flattened hashes
        for key, hashes in ctx.attr.provider_hashes.items():
            if ":" in key:
                _, version = key.rsplit(":", 1)
                provider_info[key] = {
                    "version": version,
                    "hashes": hashes,
                }

        # Generate HCL from reconstructed data for writing to file
        lock_file_content = _generate_lock_hcl_from_json(provider_info)
    elif ctx.attr.lock_file_content:
        # Fall back to parsing raw content (deprecated path)
        provider_info = parse_terraform_lock_file(ctx.attr.lock_file_content)
        lock_file_content = ctx.attr.lock_file_content

    # Write the lock file for reference
    if lock_file_content:
        ctx.file(".terraform.lock.hcl", lock_file_content)

    # Start building the BUILD file content
    build_content = [
        'package(default_visibility = ["//visibility:public"])',
        "",
        'load("@bazel_skylib//:bzl_library.bzl", "bzl_library")',
        'load("@rules_tf2//tf2/providers/registry:provider_metadata.bzl", "provider_metadata")',
        'load("@rules_tf2//tf2/providers/registry:filesystem_mirror.bzl", "filesystem_mirror")',
        "",
        "# Individual provider targets (references to provider repositories)",
        "# These reference external repositories that download providers during loading phase",
        "",
    ]

    # Track which providers we've created targets for
    provider_downloads = {}  # provider:version -> {platform: target_name}

    # Create references to provider repositories
    # ctx.attr.provider_repositories is a dict like:
    # {"hashicorp/aws": {"6.12.0": {"linux_amd64": "tf_provider_aws_6_12_0_linux_amd64", ...}}}
    provider_repositories = {}
    if hasattr(ctx.attr, "provider_repositories_json") and ctx.attr.provider_repositories_json:
        provider_repositories = json.decode(ctx.attr.provider_repositories_json)

    for provider_source, versions in provider_repositories.items():
        _, name = provider_source.split("/") if "/" in provider_source else ("", provider_source)

        if provider_source not in provider_downloads:
            provider_downloads[provider_source] = {}

        for version, platforms in versions.items():
            if version not in provider_downloads[provider_source]:
                provider_downloads[provider_source][version] = {}

            # Create alias targets for each platform that point to the provider repository
            for platform, repo_name in platforms.items():
                target_name = "download_{}_{}_{}".format(
                    name,
                    version.replace(".", "_"),
                    platform,
                )

                provider_downloads[provider_source][version][platform] = target_name

                # Create an alias that points to the provider repository
                build_content.extend([
                    "alias(",
                    '    name = "{}",'.format(target_name),
                    '    actual = "@{}//:files",'.format(repo_name),
                    ")",
                    "",
                ])

    # Create provider aliases based on providers found in lock file
    build_content.extend([
        "# Provider aliases for major versions",
        "# These reference the download targets above",
        "",
    ])

    # Create provider aliases from the aliases dict
    if ctx.attr.aliases:
        for alias_name, provider_spec in ctx.attr.aliases.items():
            if len(provider_spec) >= 2:
                provider_source = provider_spec[0]
                provider_version = provider_spec[1]

                build_content.extend([
                    "provider_metadata(",
                    '    name = "{}",'.format(alias_name),
                    '    provider = "{}",'.format(provider_source),
                    '    version = "{}",'.format(provider_version),
                    ")",
                    "",
                ])

    # Create filesystem mirrors for each platform
    build_content.extend([
        "",
        "# Filesystem mirrors for each platform",
        "# These aggregate all provider downloads for a specific platform",
        "",
    ])

    # Create a filesystem_mirror for each platform (even if empty)
    mirror_exists = {}
    for platform in ["linux_amd64", "linux_arm64", "darwin_amd64", "darwin_arm64"]:
        # Collect all downloads for this platform
        platform_providers = []
        for source, versions in provider_downloads.items():
            for version, platforms in versions.items():
                if platform in platforms:
                    platform_providers.append('":{}",'.format(platforms[platform]))

        # Always create mirror, even if empty (for consistent target availability)
        build_content.extend([
            "filesystem_mirror(",
            '    name = "mirror_{}",'.format(platform),
            "    providers = [",
        ])
        for provider_ref in platform_providers:
            build_content.append("        {}".format(provider_ref))
        build_content.extend([
            "    ],",
            ")",
            "",
        ])
        mirror_exists[platform] = True

    # Create platform-aware unpacked_providers using select()
    # Note: alias() doesn't support select(), so we use filegroup instead
    build_content.extend([
        "",
        "# Platform-aware provider mirror selection",
        "# Automatically selects the correct platform's providers based on execution platform",
        "filegroup(",
        '    name = "unpacked_providers",',
        "    srcs = select({",
        '        ":linux_x86_64": [":mirror_linux_amd64"],',
        '        ":linux_aarch64": [":mirror_linux_arm64"],',
        '        ":macos_x86_64": [":mirror_darwin_amd64"],',
        '        ":macos_aarch64": [":mirror_darwin_arm64"],',
        "    }),",
        ")",
        "",
    ])

    # Create platform config settings and select-based unpacked_providers target
    build_content.extend([
        "",
        "# Platform config settings",
        "config_setting(",
        '    name = "linux_x86_64",',
        "    constraint_values = [",
        '        "@platforms//os:linux",',
        '        "@platforms//cpu:x86_64",',
        "    ],",
        ")",
        "",
        "config_setting(",
        '    name = "linux_aarch64",',
        "    constraint_values = [",
        '        "@platforms//os:linux",',
        '        "@platforms//cpu:aarch64",',
        "    ],",
        ")",
        "",
        "config_setting(",
        '    name = "macos_x86_64",',
        "    constraint_values = [",
        '        "@platforms//os:macos",',
        '        "@platforms//cpu:x86_64",',
        "    ],",
        ")",
        "",
        "config_setting(",
        '    name = "macos_aarch64",',
        "    constraint_values = [",
        '        "@platforms//os:macos",',
        '        "@platforms//cpu:aarch64",',
        "    ],",
        ")",
        "",
        "# Lock file for provider hashes",
        "exports_files([",
        '    ".terraform.lock.hcl",',
        '    "provider_locks.bzl",',
        '    "provider_locks.json",',
        "])",
        "",
        "# bzl_library for stardoc integration",
        "bzl_library(",
        '    name = "provider_locks",',
        '    srcs = ["provider_locks.bzl"],',
        ")",
    ])

    # Write the BUILD file
    ctx.file("BUILD.bazel", "\n".join(build_content))

    # Create provider_locks.bzl file with lock data
    locks_dict = {}
    for provider_key, data in provider_info.items():
        if ":" in provider_key:
            # Already in the right format
            locks_dict[provider_key] = data.get("hashes", [])
        else:
            # Add version to key
            version = data.get("version", "")
            if version:
                key = "{}:{}".format(provider_key, version)

                # Extract just the hash strings if hashes is a dict
                hashes = data.get("hashes", [])
                if type(hashes) == "dict":
                    # Combine all hashes from dict format
                    combined = []
                    for hash_type, hash_list in hashes.items():
                        if hash_type != "platforms":  # Skip platform-specific mapping
                            for h in hash_list:
                                if hash_type in ["h1", "zh"]:
                                    combined.append("{}:{}".format(hash_type, h))
                                else:
                                    combined.append(h)
                    locks_dict[key] = combined
                else:
                    locks_dict[key] = hashes

    # Build alias mapping for macro-time lookup
    # Format: {"aws_6": {"provider": "hashicorp/aws", "version": "6.14.0"}, ...}
    alias_mapping = {}
    if ctx.attr.aliases:
        for alias_name, provider_spec in ctx.attr.aliases.items():
            if len(provider_spec) >= 2:
                alias_mapping[alias_name] = {
                    "provider": provider_spec[0],
                    "version": provider_spec[1],
                }

    locks_content = [
        '"""Provider lock file information and alias mappings"""',
        "",
        "# This file provides lock file information for provider hashes",
        "# and alias-to-version mappings for per-module provider filtering",
        "# It is auto-generated from the terraform.lock.hcl file",
        "",
        "PROVIDER_LOCKS = " + str(locks_dict),
        "",
        "# Alias to provider/version mapping",
        "# Used by tf_module macro to compute download targets at macro time",
        "PROVIDER_ALIASES = " + str(alias_mapping),
        "",
    ]
    ctx.file("provider_locks.bzl", "\n".join(locks_content))

    # Generate JSON in the format expected by hcl_tool (expanded format)
    # From: {"hashicorp/aws:6.13.0": ["hash1", "hash2"]}
    # To: {"hashicorp/aws:6.13.0": {"provider": "hashicorp/aws", "version": "6.13.0", "hashes": [...]}}
    expanded_locks = {}
    for key, hashes in locks_dict.items():
        if ":" in key:
            provider, version = key.rsplit(":", 1)
            expanded_locks[key] = {
                "provider": provider,
                "version": version,
                "hashes": hashes,
            }
    ctx.file("provider_locks.json", json.encode(expanded_locks))

    # Also create a manifest of all providers for debugging
    manifest = {
        "providers": ctx.attr.providers,
        "aliases": ctx.attr.aliases,
        "downloads": provider_downloads,
        "lock_info": provider_info,
    }
    ctx.file("manifest.json", json.encode_indent(manifest, indent = "  "))

terraform_providers = repository_rule(
    implementation = _terraform_providers_impl,
    attrs = {
        "providers": attr.string_list_dict(
            doc = "Map of provider sources to list of versions",
            mandatory = True,
        ),
        "aliases": attr.string_list_dict(
            doc = "Map of alias names to [provider, version] pairs",
            default = {},
        ),
        "lock_file_content": attr.string(
            doc = "Content of the terraform.lock.hcl file (deprecated, use lock_file_json)",
            mandatory = False,
        ),
        "provider_hashes": attr.string_list_dict(
            doc = "Provider hashes: provider:version -> [hashes]",
            mandatory = False,
            default = {},
        ),
        "provider_repositories_json": attr.string(
            doc = "JSON-encoded map of provider repositories: provider -> version -> platform -> repo_name",
            default = "{}",
        ),
    },
)

def terraform_providers_from_mirror_declarations(providers, _versions_file = None, _lock_file = None):
    """Helper to convert provider mirror declarations to providers dict.

    Args:
        providers: Dict of provider aliases to "source:version" strings
        _versions_file: Path to versions.json file (unused, for compatibility)
        _lock_file: Path to terraform.lock.hcl file (unused, for compatibility)

    Returns:
        Dict suitable for terraform_providers rule
    """
    result = {}
    for _, spec in providers.items():
        if ":" in spec:
            source, version = spec.rsplit(":", 1)
            if source not in result:
                result[source] = []
            if version not in result[source]:
                result[source].append(version)
    return result
