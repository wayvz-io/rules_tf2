"""Sentinel tool download rules"""

load(":platform.bzl", "PLATFORM_IDS", "get_platform_info")

# Sentinel-specific configuration
SENTINEL_CONFIG = {
    "base_url": "https://releases.hashicorp.com/sentinel",
    "archive_format": "zip",
    "binary_name": "sentinel",
    "default_version": "0.40.0",
}

def sentinel_fetch_spec(version, platform):
    """Return the hermetic-fetch spec for a Sentinel version.

    HashiCorp publishes a `sentinel_<v>_SHA256SUMS` file covering all platforms.
    """
    v = version or SENTINEL_CONFIG["default_version"]
    return struct(
        version = v,
        sums_url = "{base}/{v}/sentinel_{v}_SHA256SUMS".format(base = SENTINEL_CONFIG["base_url"], v = v),
        platform_files = {p: "sentinel_{v}_{p}.zip".format(v = v, p = p) for p in PLATFORM_IDS},
        artifact_url = _build_sentinel_download_url(v, platform),
    )

def _build_sentinel_download_url(version, platform):
    """Build the download URL for Sentinel.

    Args:
        version: Sentinel version to download
        platform: Platform identifier (e.g., "linux_amd64")

    Returns:
        String download URL
    """
    base_url = SENTINEL_CONFIG["base_url"]
    archive_format = SENTINEL_CONFIG["archive_format"]

    return "{base_url}/{version}/sentinel_{version}_{platform}.{format}".format(
        base_url = base_url,
        version = version,
        platform = platform,
        format = archive_format,
    )

def _download_sentinel_impl(repository_ctx):
    """Implementation of sentinel download repository rule.

    Args:
        repository_ctx: Repository rule context
    """
    version = repository_ctx.attr.version or SENTINEL_CONFIG["default_version"]
    platform = get_platform_info(repository_ctx)

    # Build download URL
    download_url = _build_sentinel_download_url(version, platform)
    binary_name = SENTINEL_CONFIG["binary_name"]

    # Download and extract, verifying the locked checksum when one was resolved.
    repository_ctx.download_and_extract(
        url = download_url,
        type = "zip",
        sha256 = repository_ctx.attr.sha256,
    )

    # Make binary executable
    repository_ctx.execute(["chmod", "+x", binary_name])

    # Create BUILD file
    build_content = '''load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//visibility:public"])

exports_files(["{binary_name}"])

sh_binary(
    name = "bin",
    srcs = ["{binary_name}"],
)
'''.format(binary_name = binary_name)

    repository_ctx.file("BUILD.bazel", build_content)

    # Create version info file
    repository_ctx.file("VERSION", version)

download_sentinel = repository_rule(
    implementation = _download_sentinel_impl,
    attrs = {
        "version": attr.string(doc = "Sentinel version to download (uses default if not specified)"),
        "sha256": attr.string(doc = "Expected sha256 of the platform archive; verified on download when set"),
    },
    doc = "Downloads Sentinel binary from HashiCorp releases",
)
