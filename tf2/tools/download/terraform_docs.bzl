"""terraform-docs tool download rules"""

load(":platform.bzl", "PLATFORM_IDS", "get_platform_info", "get_terraform_docs_platform")

# terraform-docs configuration
TERRAFORM_DOCS_CONFIG = {
    "base_url": "https://github.com/terraform-docs/terraform-docs/releases/download",
    "archive_format": "tar.gz",
    "binary_name": "terraform-docs",
    "default_version": "0.18.0",
}

def terraform_docs_fetch_spec(version, platform):
    """Return the hermetic-fetch spec for a terraform-docs version.

    terraform-docs attaches a combined `terraform-docs-v<v>.sha256` file (all
    platforms) to each GitHub release. Note its assets use dash-style platform
    names (e.g. `linux-amd64`).
    """
    v = version or TERRAFORM_DOCS_CONFIG["default_version"]
    return struct(
        version = v,
        sums_url = "{base}/v{v}/terraform-docs-v{v}.sha256sum".format(base = TERRAFORM_DOCS_CONFIG["base_url"], v = v),
        platform_files = {
            p: "terraform-docs-v{v}-{pd}.tar.gz".format(v = v, pd = get_terraform_docs_platform(p))
            for p in PLATFORM_IDS
        },
        artifact_url = _build_terraform_docs_download_url(v, platform),
    )

def _build_terraform_docs_download_url(version, platform):
    """Build the download URL for terraform-docs.

    Args:
        version: terraform-docs version to download
        platform: Platform identifier (e.g., "linux_amd64")

    Returns:
        String download URL
    """
    base_url = TERRAFORM_DOCS_CONFIG["base_url"]
    archive_format = TERRAFORM_DOCS_CONFIG["archive_format"]

    # terraform-docs uses different platform naming (dashes instead of underscores)
    tf_docs_platform = get_terraform_docs_platform(platform)

    return "{base_url}/v{version}/terraform-docs-v{version}-{platform}.{format}".format(
        base_url = base_url,
        version = version,
        platform = tf_docs_platform,
        format = archive_format,
    )

def _download_terraform_docs_impl(repository_ctx):
    """Implementation of terraform-docs download repository rule.

    Args:
        repository_ctx: Repository rule context
    """
    version = repository_ctx.attr.version or TERRAFORM_DOCS_CONFIG["default_version"]

    platform = get_platform_info(repository_ctx)

    # Build download URL
    download_url = _build_terraform_docs_download_url(version, platform)
    binary_name = TERRAFORM_DOCS_CONFIG["binary_name"]

    # Download and extract, verifying the locked checksum when one was resolved.
    repository_ctx.download_and_extract(
        url = download_url,
        type = "tar.gz",
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

download_terraform_docs = repository_rule(
    implementation = _download_terraform_docs_impl,
    attrs = {
        "version": attr.string(doc = "terraform-docs version to download (uses default if not specified)"),
        "sha256": attr.string(doc = "Expected sha256 of the platform archive; verified on download when set"),
    },
    doc = "Downloads terraform-docs binary from GitHub releases",
)
