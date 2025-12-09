"""OPA tool download rules"""

load(":platform.bzl", "get_platform_info")

# OPA-specific configuration
OPA_CONFIG = {
    "base_url": "https://github.com/open-policy-agent/opa/releases/download",
    "binary_name": "opa",
    "default_version": "1.4.2",
}

def _build_opa_download_url(version, platform):
    """Build the download URL for OPA.

    Args:
        version: OPA version to download
        platform: Platform identifier (e.g., "linux_amd64")

    Returns:
        String download URL
    """
    base_url = OPA_CONFIG["base_url"]

    # OPA uses format: opa_{os}_{arch} (single binary, not archive)
    # For Linux, use _static suffix as some platforms only have static builds
    suffix = "_static" if platform.startswith("linux") else ""

    return "{base_url}/v{version}/opa_{platform}{suffix}".format(
        base_url = base_url,
        version = version,
        platform = platform,
        suffix = suffix,
    )

def _download_opa_impl(repository_ctx):
    """Implementation of OPA download repository rule.

    Args:
        repository_ctx: Repository rule context
    """
    version = repository_ctx.attr.version or OPA_CONFIG["default_version"]
    platform = get_platform_info(repository_ctx)

    # Build download URL
    download_url = _build_opa_download_url(version, platform)
    binary_name = OPA_CONFIG["binary_name"]

    # Download single binary (OPA releases are not archives)
    repository_ctx.download(
        url = download_url,
        output = binary_name,
        executable = True,
    )

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

download_opa = repository_rule(
    implementation = _download_opa_impl,
    attrs = {
        "version": attr.string(doc = "OPA version to download (uses default if not specified)"),
    },
    doc = "Downloads OPA binary from GitHub releases",
)
