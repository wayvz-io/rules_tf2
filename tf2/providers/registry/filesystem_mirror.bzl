"""BUILD rule for creating a Terraform provider filesystem mirror"""

load("@bazel_skylib//lib:paths.bzl", "paths")

# Known platform suffixes
_PLATFORMS = ["linux_amd64", "linux_arm64", "darwin_amd64", "darwin_arm64"]

def _parse_provider_from_label(label):
    """Parse provider metadata from a label.

    Handles both:
    - Alias names like "download_aws_6_12_0_linux_amd64"
    - Repository names like "_main~tf_providers~tf_provider_aws_6_12_0_linux_arm64"

    Args:
        label: Bazel label object

    Returns:
        Dict with name, version, platform, or None if parsing fails
    """

    # First, try to parse from the repository name (works when alias is resolved)
    # Repository names look like: _main~tf_providers~tf_provider_NAME_VERSION_PLATFORM
    repo_name = label.workspace_name

    # Look for "tf_provider_" prefix in repository name
    provider_marker = "tf_provider_"
    if provider_marker in repo_name:
        # Extract the part after "tf_provider_"
        idx = repo_name.find(provider_marker)
        name_version_platform = repo_name[idx + len(provider_marker):]
    elif label.name.startswith("download_"):
        # Fallback: try to parse from target name (direct reference, not alias)
        name_version_platform = label.name[9:]  # Remove "download_" prefix
    else:
        return None

    # Find and extract the platform suffix
    platform = None
    name_version = None
    for p in _PLATFORMS:
        suffix = "_" + p
        if name_version_platform.endswith(suffix):
            platform = p
            name_version = name_version_platform[:-len(suffix)]
            break

    if not platform or not name_version:
        return None

    # Extract provider name and version from name_version
    # Format: NAME_MAJOR_MINOR_PATCH (e.g., "aws_6_12_0" or "palo_alto_2_0_5")
    # Version is always the last 3 underscore-separated parts
    parts = name_version.split("_")
    if len(parts) < 4:
        # Not enough parts for name + version
        return None

    # Last 3 parts are version components
    version = "{}.{}.{}".format(parts[-3], parts[-2], parts[-1])
    name = "_".join(parts[:-3])

    if not name:
        return None

    return {
        "name": name,
        "version": version,
        "platform": platform,
    }

def _filesystem_mirror_impl(ctx):
    """Implementation of filesystem_mirror rule.

    This rule aggregates individual provider downloads and creates a filesystem
    mirror structure that Terraform can use with the filesystem_mirror configuration.

    Uses the "packed" layout with zip files for checksum verification:
        registry.terraform.io/
            hashicorp/
                aws/
                    terraform-provider-aws_6.12.0_linux_amd64.zip

    The packed layout uses zh: (zip hash) checksums from the lockfile, which
    Terraform can verify directly against the zip files.
    """

    # Collect all provider zip files and create symlinks
    symlink_outputs = []

    # Process each provider dependency
    for provider_dep in ctx.attr.providers:
        label = provider_dep.label

        # Extract repo_name from workspace_name
        # Handles both formats:
        #   - Older: "_main~tf_providers~tf_provider_aws_6_12_0_linux_arm64" (~ separator)
        #   - Newer: "+tf_providers+tf_provider_aws_6_26_0_linux_arm64" (+ separator)
        workspace = label.workspace_name
        repo_name = None

        # Try both separators
        if "+" in workspace:
            parts = workspace.split("+")
        elif "~" in workspace:
            parts = workspace.split("~")
        else:
            parts = []

        for part in reversed(parts):
            if part.startswith("tf_provider_"):
                repo_name = part
                break

        # Get provider source from explicit attribute using repo_name as key
        provider_source = None
        if repo_name and repo_name in ctx.attr.provider_sources:
            provider_source = ctx.attr.provider_sources[repo_name]
        elif label.name in ctx.attr.provider_sources:
            # Fallback to target name (for direct references without aliases)
            provider_source = ctx.attr.provider_sources[label.name]

        if provider_source:
            namespace, provider_name = provider_source.split("/")
        else:
            # Without provider_sources, we can't determine namespace - skip
            continue

        # Get the files from the provider download - look for zip files
        for file in provider_dep.files.to_list():
            # For packed layout, we only want zip files
            if not file.basename.endswith(".zip"):
                continue

            # Build the target path in the packed mirror structure
            # Structure: registry.terraform.io/namespace/name/terraform-provider-name_version_os_arch.zip
            target_path = "registry.terraform.io/{}/{}".format(
                namespace,
                provider_name,
            )

            # Declare the symlink output file
            output_path = paths.join(ctx.label.name, target_path, file.basename)
            symlink_file = ctx.actions.declare_file(output_path)

            # Create symlink to the provider zip
            ctx.actions.symlink(
                output = symlink_file,
                target_file = file,
            )

            symlink_outputs.append(symlink_file)

    # If no providers were processed, create an empty marker file
    if not symlink_outputs:
        empty_marker = ctx.actions.declare_file(paths.join(ctx.label.name, ".empty"))
        ctx.actions.write(
            output = empty_marker,
            content = "# Empty provider mirror\n",
        )
        symlink_outputs.append(empty_marker)

    return [
        DefaultInfo(
            files = depset(symlink_outputs),
            runfiles = ctx.runfiles(files = symlink_outputs),
        ),
    ]

filesystem_mirror = rule(
    implementation = _filesystem_mirror_impl,
    attrs = {
        "providers": attr.label_list(
            doc = "List of provider_download targets to include in the mirror",
            allow_files = True,
        ),
        "provider_sources": attr.string_dict(
            doc = "Mapping of provider target names to their full provider source (e.g., 'download_okta_0_68_0_linux_arm64': 'okta/okta')",
            default = {},
        ),
    },
    doc = """Creates a filesystem mirror for Terraform providers.
    
    This rule aggregates individual provider downloads and creates the directory
    structure expected by Terraform's filesystem_mirror configuration.
    
    Example:
        filesystem_mirror(
            name = "my_mirror",
            providers = [
                ":download_aws_6_12_0_linux_amd64",
                ":download_azurerm_4_43_0_linux_amd64",
            ],
        )
    
    The output will be a directory structure like:
        registry.terraform.io/
            hashicorp/
                aws/
                    6.12.0/
                        linux_amd64/
                            terraform-provider-aws_v6.12.0_x5
    """,
)
