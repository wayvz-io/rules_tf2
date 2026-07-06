"""OPA tool download rules"""

load(":platform.bzl", "PLATFORM_IDS", "get_platform_info")

# OPA-specific configuration
OPA_CONFIG = {
    "base_url": "https://github.com/open-policy-agent/opa/releases/download",
    "binary_name": "opa",
    "default_version": "1.4.2",
}

# OPA's release asset names are irregular: static builds exist for every
# platform except darwin/amd64. Map each platform explicitly.
_OPA_ASSETS = {
    "linux_amd64": "opa_linux_amd64_static",
    "linux_arm64": "opa_linux_arm64_static",
    "darwin_amd64": "opa_darwin_amd64",
    "darwin_arm64": "opa_darwin_arm64_static",
}

def _opa_asset_name(platform):
    """Asset filename OPA publishes for a platform (single binary, not archive)."""
    if platform not in _OPA_ASSETS:
        fail("Unsupported OPA platform: {}".format(platform))
    return _OPA_ASSETS[platform]

def _build_opa_download_url(version, platform):
    """Build the download URL for OPA.

    Args:
        version: OPA version to download
        platform: Platform identifier (e.g., "linux_amd64")

    Returns:
        String download URL
    """
    return "{base_url}/v{version}/{asset}".format(
        base_url = OPA_CONFIG["base_url"],
        version = version,
        asset = _opa_asset_name(platform),
    )

def opa_fetch_spec(version, platform):
    """Return the hermetic-fetch spec for an OPA version.

    OPA ships one `<asset>.sha256` file per binary (no combined checksums file),
    so this returns a per-platform `per_file_sums` map rather than a single URL.
    """
    v = version or OPA_CONFIG["default_version"]
    base = OPA_CONFIG["base_url"]
    return struct(
        version = v,
        sums_url = None,
        per_file_sums = {
            p: struct(
                url = "{base}/v{v}/{asset}.sha256".format(base = base, v = v, asset = _opa_asset_name(p)),
                filename = _opa_asset_name(p),
            )
            for p in PLATFORM_IDS
        },
        platform_files = {p: _opa_asset_name(p) for p in PLATFORM_IDS},
        artifact_url = _build_opa_download_url(v, platform),
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

    # Download single binary (OPA releases are not archives), verifying the
    # locked checksum when one was resolved.
    repository_ctx.download(
        url = download_url,
        output = binary_name,
        executable = True,
        sha256 = repository_ctx.attr.sha256,
    )

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

download_opa = repository_rule(
    implementation = _download_opa_impl,
    attrs = {
        "version": attr.string(doc = "OPA version to download (uses default if not specified)"),
        "sha256": attr.string(doc = "Expected sha256 of the platform binary; verified on download when set"),
    },
    doc = "Downloads OPA binary from GitHub releases",
)
