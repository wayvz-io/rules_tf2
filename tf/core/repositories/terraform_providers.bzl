"""Repository rules for Terraform provider management"""

load(":provider_http_files.bzl", "parse_terraform_lock_file", "get_provider_download_info")

def _generate_lock_hcl_from_json(lock_json):
    """Generate HCL content from parsed lock file JSON."""
    lines = [
        '# This file is maintained automatically by "terraform init".',
        '# Manual edits may be lost in future updates.',
        '',
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
            lines.append('  hashes = [')
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
            lines.append('  ]')
        
        lines.append('}')
        lines.append('')
    
    return '\n'.join(lines)

def _terraform_providers_impl(ctx):
    """Implementation of terraform_providers repository rule.
    
    This rule creates a BUILD file with individual provider download targets.
    Each provider/platform combination gets its own target that downloads on demand.
    """
    
    # Use provider hashes if provided, otherwise parse raw content
    provider_info = {}
    lock_file_content = ""
    if ctx.attr.provider_hashes:
        # Reconstruct provider_info from flattened hashes
        for key, hashes in ctx.attr.provider_hashes.items():
            if ":" in key:
                provider, version = key.rsplit(":", 1)
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
        '',
        'load("@rules_tf2//tf/core/providers:provider_download_action.bzl", "provider_download_action")',
        'load("@rules_tf2//tf/core/providers:provider_alias_simple.bzl", "provider_alias_simple")',
        'load("@rules_tf2//tf/core/providers:filesystem_mirror.bzl", "filesystem_mirror")',
        '',
        '# Individual provider download targets',
        '# These are only fetched when actually needed by a build',
        '',
    ]
    
    # Track which downloads we've created for use in aliases
    provider_downloads = {}  # provider:version -> {platform: target_name}
    
    # Create download targets for each provider/version/platform
    for provider_key, data in provider_info.items():
        # Handle both formats: provider_key might be the full source or need extraction
        if ":" in provider_key:
            # Format: "hashicorp/aws:6.12.0"
            source = provider_key.split(":")[0]
        else:
            # Format: "hashicorp/aws" with version in data
            source = provider_key
        
        version = data.get("version", "")
        if not version:
            continue
            
        namespace, name = source.split("/") if "/" in source else ("", source)
        
        if source not in provider_downloads:
            provider_downloads[source] = {}
        if version not in provider_downloads[source]:
            provider_downloads[source][version] = {}
        
        # Get hashes for verification
        # Collect zh hashes (hex SHA256) - these are the actual provider zip file hashes
        zh_hashes = []
        if "hashes" in data:
            # Handle both formats: list of strings or dict with h1/zh keys
            if type(data["hashes"]) == "list":
                # List format - extract zh hashes (hex format)
                for hash_val in data["hashes"]:
                    if hash_val.startswith("zh:"):
                        zh_hashes.append(hash_val[3:])  # Remove "zh:" prefix
            elif type(data["hashes"]) == "dict":
                # Dict format from our parsed JSON
                if "zh" in data["hashes"]:
                    zh_hashes.extend(data["hashes"]["zh"])
        
        # Create download target for each platform
        platforms = ["linux_amd64", "linux_arm64", "darwin_amd64", "darwin_arm64"]
        for platform in platforms:
            os_name, arch = platform.split("_")
            url, filename = get_provider_download_info(source, version, os_name, arch)
            
            target_name = "download_{}_{}_{}".format(
                name,
                version.replace(".", "_"),
                platform
            )
            
            provider_downloads[source][version][platform] = target_name
            
            build_content.extend([
                'provider_download_action(',
                '    name = "{}",'.format(target_name),
                '    url = "{}",'.format(url),
            ])
            
            # Pass zh hashes as comma-separated list (these are hex SHA256)
            # The download script will verify against any of them
            if zh_hashes:
                build_content.append('    sha256 = "{}",'.format(",".join(zh_hashes)))
            
            build_content.extend([
                '    provider = "{}",'.format(source),
                '    version = "{}",'.format(version),
                '    platform = "{}",'.format(platform),
                ')',
                '',
            ])
    
    # Create provider aliases based on providers found in lock file
    build_content.extend([
        '# Provider aliases for major versions',
        '# These reference the download targets above',
        '',
    ])
    
    # Create provider aliases from the aliases dict
    if ctx.attr.aliases:
        for alias_name, provider_spec in ctx.attr.aliases.items():
            if len(provider_spec) >= 2:
                provider_source = provider_spec[0]
                provider_version = provider_spec[1]
                
                build_content.extend([
                    'provider_alias_simple(',
                    '    name = "{}",'.format(alias_name),
                    '    provider = "{}",'.format(provider_source),
                    '    version = "{}",'.format(provider_version),
                    ')',
                    '',
                ])
    
    # Create filesystem mirrors for each platform
    build_content.extend([
        '',
        '# Filesystem mirrors for each platform',
        '# These aggregate all provider downloads for a specific platform',
        '',
    ])
    
    # Create a filesystem_mirror for each platform
    for platform in ["linux_amd64", "linux_arm64", "darwin_amd64", "darwin_arm64"]:
        # Collect all downloads for this platform
        platform_providers = []
        for source, versions in provider_downloads.items():
            for version, platforms in versions.items():
                if platform in platforms:
                    platform_providers.append('":{}",'.format(platforms[platform]))
        
        if platform_providers:
            build_content.extend([
                'filesystem_mirror(',
                '    name = "mirror_{}",'.format(platform),
                '    providers = [',
            ])
            for provider_ref in platform_providers:
                build_content.append('        {}'.format(provider_ref))
            build_content.extend([
                '    ],',
                ')',
                '',
            ])
    
    # For backward compatibility, create an alias
    build_content.extend([
        '',
        '# Create unpacked_providers alias for backward compatibility',  
        'alias(',
        '    name = "unpacked_providers",',
        '    actual = ":mirror_linux_arm64",',  # Use current platform directly for now
        ')',
        '',
    ])
    
    # Create platform config settings and select-based unpacked_providers target
    build_content.extend([
        '',
        '# Platform config settings',
        'config_setting(',
        '    name = "linux_x86_64",',
        '    constraint_values = [',
        '        "@platforms//os:linux",',
        '        "@platforms//cpu:x86_64",',
        '    ],',
        ')',
        '',
        'config_setting(',
        '    name = "linux_aarch64",',
        '    constraint_values = [',
        '        "@platforms//os:linux",',
        '        "@platforms//cpu:aarch64",',
        '    ],',
        ')',
        '',
        'config_setting(',
        '    name = "macos_x86_64",',
        '    constraint_values = [',
        '        "@platforms//os:macos",',
        '        "@platforms//cpu:x86_64",',
        '    ],',
        ')',
        '',
        'config_setting(',
        '    name = "macos_aarch64",',
        '    constraint_values = [',
        '        "@platforms//os:macos",',
        '        "@platforms//cpu:aarch64",',
        '    ],',
        ')',
        '',
        '# Lock file for provider hashes',
        'exports_files([',
        '    ".terraform.lock.hcl",',
        '    "provider_locks.bzl",',
        '])',
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
    
    locks_content = [
        '"""Provider lock file information"""',
        '',
        '# This file provides lock file information for provider hashes',
        '# It is auto-generated from the terraform.lock.hcl file',
        '',
        'PROVIDER_LOCKS = ' + str(locks_dict),
        '',
    ]
    ctx.file("provider_locks.bzl", "\n".join(locks_content))
    
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
    },
)

def terraform_providers_from_mirror_declarations(providers, versions_file = None, lock_file = None):
    """Helper to convert provider mirror declarations to providers dict.
    
    Args:
        providers: Dict of provider aliases to "source:version" strings
        versions_file: Path to versions.json file (unused, for compatibility)
        lock_file: Path to terraform.lock.hcl file (unused, for compatibility)
    
    Returns:
        Dict suitable for terraform_providers rule
    """
    result = {}
    for alias, spec in providers.items():
        if ":" in spec:
            source, version = spec.rsplit(":", 1)
            if source not in result:
                result[source] = []
            if version not in result[source]:
                result[source].append(version)
    return result