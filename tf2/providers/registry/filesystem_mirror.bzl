"""BUILD rule for creating a Terraform provider filesystem mirror"""

load("@bazel_skylib//lib:paths.bzl", "paths")

# Namespace mapping for provider names
_NAMESPACE_MAPPING = {
    "aws": "hashicorp",
    "azurerm": "hashicorp",
    "google": "hashicorp",
    "null": "hashicorp",
    "random": "hashicorp",
    "local": "hashicorp",
    "archive": "hashicorp",
    "time": "hashicorp",
    "tls": "hashicorp",
    "helm": "hashicorp",
    "kubernetes": "hashicorp",
    "tfe": "hashicorp",
    "panos": "paloaltonetworks",
    "onepassword": "1password",
    "flux": "fluxcd",
    "cloudflare": "cloudflare",
}

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
        Dict with name, version, platform, namespace, or None if parsing fails
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

    # Get namespace from mapping
    namespace = _NAMESPACE_MAPPING.get(name, "unknown")

    return {
        "name": name,
        "version": version,
        "platform": platform,
        "namespace": namespace,
    }

def _filesystem_mirror_impl(ctx):
    """Implementation of filesystem_mirror rule.

    This rule aggregates individual provider downloads and creates a filesystem
    mirror structure that Terraform can use with the filesystem_mirror configuration.

    Uses symlinks instead of copies to minimize disk usage and improve build times.
    """
    # Collect all provider files and their target paths
    symlink_outputs = []
    provider_inputs = []

    # Process each provider dependency
    for provider_dep in ctx.attr.providers:
        # Parse provider metadata from the label (handles aliases correctly)
        metadata = _parse_provider_from_label(provider_dep.label)
        if not metadata:
            # Skip providers we can't parse - this shouldn't happen with valid download targets
            continue

        # Get the files from the provider download
        for file in provider_dep.files.to_list():
            provider_inputs.append(file)

            # Build the target path in the mirror structure
            target_path = "registry.terraform.io/{}/{}/{}/{}".format(
                metadata["namespace"],
                metadata["name"],
                metadata["version"],
                metadata["platform"],
            )

            # Declare the symlink output file
            # Use the original file's basename to preserve the binary name
            output_path = paths.join(ctx.label.name, target_path, file.basename)
            symlink_file = ctx.actions.declare_file(output_path)

            # Create symlink to the original provider binary
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
