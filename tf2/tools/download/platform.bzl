"""Platform detection utilities for tool downloads"""

# Flat list of the platform identifiers tools publish binaries for. Used when
# locking every platform's checksum from a publisher's SHA256SUMS file so the
# committed lockfile is portable across the platforms devs and CI build on.
PLATFORM_IDS = ["linux_amd64", "linux_arm64", "darwin_amd64", "darwin_arm64"]

# Platform detection mapping
PLATFORMS = {
    "linux": {
        "amd64": "linux_amd64",
        "arm64": "linux_arm64",
    },
    "macos": {
        "amd64": "darwin_amd64",
        "arm64": "darwin_arm64",
    },
}

# Tool-specific platform mappings (for tools with different naming conventions)
TERRAFORM_DOCS_PLATFORMS = {
    "linux": {
        "amd64": "linux-amd64",
        "arm64": "linux-arm64",
    },
    "macos": {
        "amd64": "darwin-amd64",
        "arm64": "darwin-arm64",
    },
}

def get_platform_info(repository_ctx):
    """Determine the current platform for tool downloads.

    Args:
        repository_ctx: Repository rule context

    Returns:
        String platform identifier (e.g., "linux_amd64")
    """
    os_name = repository_ctx.os.name.lower()
    arch = repository_ctx.os.arch.lower()

    # Normalize OS name
    if os_name.startswith("mac") or os_name == "darwin":
        os_key = "macos"
    elif os_name.startswith("linux"):
        os_key = "linux"
    else:
        fail("Unsupported OS: {}".format(os_name))

    # Normalize architecture
    if arch in ["x86_64", "amd64"]:
        arch_key = "amd64"
    elif arch in ["aarch64", "arm64"]:
        arch_key = "arm64"
    else:
        fail("Unsupported architecture: {}".format(arch))

    if os_key not in PLATFORMS or arch_key not in PLATFORMS[os_key]:
        fail("Unsupported platform: {}_{}".format(os_key, arch_key))

    return PLATFORMS[os_key][arch_key]

def get_terraform_docs_platform(standard_platform):
    """Convert standard platform format to terraform-docs platform format.

    Args:
        standard_platform: Standard platform string (e.g., "linux_amd64")

    Returns:
        String platform identifier with dashes (e.g., "linux-amd64")
    """

    # terraform-docs uses dashes instead of underscores
    return standard_platform.replace("_", "-")
