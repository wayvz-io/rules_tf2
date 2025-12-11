"""Terraform Stacksplugin download rules"""

load(":platform.bzl", "get_platform_info")

# Stacksplugin-specific configuration
STACKSPLUGIN_CONFIG = {
    "base_url": "https://releases.hashicorp.com/tfstacks",
    "archive_format": "zip",
    "binary_name": "tfstacks",
    "default_version": "1.1.1",
}

def _build_stacksplugin_download_url(version, platform):
    """Build the download URL for Stacksplugin.

    Args:
        version: Stacksplugin version to download
        platform: Platform identifier (e.g., "linux_amd64")

    Returns:
        String download URL
    """
    base_url = STACKSPLUGIN_CONFIG["base_url"]
    archive_format = STACKSPLUGIN_CONFIG["archive_format"]

    return "{base_url}/{version}/tfstacks_{version}_{platform}.{format}".format(
        base_url = base_url,
        version = version,
        platform = platform,
        format = archive_format,
    )

def _download_stacksplugin_impl(repository_ctx):
    """Implementation of stacksplugin download repository rule.

    Args:
        repository_ctx: Repository rule context
    """
    version = repository_ctx.attr.version or STACKSPLUGIN_CONFIG["default_version"]
    platform = get_platform_info(repository_ctx)

    # Build download URL
    download_url = _build_stacksplugin_download_url(version, platform)
    binary_name = STACKSPLUGIN_CONFIG["binary_name"]

    # Download and extract
    repository_ctx.download_and_extract(
        url = download_url,
        type = "zip",
    )

    # Make binary executable
    repository_ctx.execute(["chmod", "+x", binary_name])

    # Create BUILD file
    build_content = '''package(default_visibility = ["//visibility:public"])

exports_files(["{binary_name}"])

sh_binary(
    name = "bin",
    srcs = ["{binary_name}"],
)
'''.format(binary_name = binary_name)

    repository_ctx.file("BUILD.bazel", build_content)

    # Create version info file
    repository_ctx.file("VERSION", version)

download_stacksplugin = repository_rule(
    implementation = _download_stacksplugin_impl,
    attrs = {
        "version": attr.string(doc = "Stacksplugin version to download (uses default if not specified)"),
    },
    doc = "Downloads Terraform stacksplugin binary from HashiCorp releases",
)
