"""terraform-docs tool download rules"""

load(":platform.bzl", "get_platform_info", "get_terraform_docs_platform")

# terraform-docs configuration
TERRAFORM_DOCS_CONFIG = {
    "base_url": "https://github.com/terraform-docs/terraform-docs/releases/download",
    "archive_format": "tar.gz",
    "binary_name": "terraform-docs",
    "fallback_version": "0.18.0",
}

def _get_latest_terraform_docs_version(repository_ctx):
    """Get the latest version of terraform-docs from GitHub API.

    Args:
        repository_ctx: Repository rule context

    Returns:
        String version number
    """
    result = repository_ctx.execute([
        "curl", "-s", "-L",
        "https://api.github.com/repos/terraform-docs/terraform-docs/releases/latest"
    ])
    if result.return_code != 0:
        return TERRAFORM_DOCS_CONFIG["fallback_version"]

    # Parse JSON to get tag_name
    response_data = json.decode(result.stdout)
    latest_version = response_data["tag_name"].lstrip("v")
    return latest_version

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
    version = repository_ctx.attr.version
    if not version:
        version = _get_latest_terraform_docs_version(repository_ctx)

    platform = get_platform_info(repository_ctx)

    # Build download URL
    download_url = _build_terraform_docs_download_url(version, platform)
    binary_name = TERRAFORM_DOCS_CONFIG["binary_name"]

    print("Downloading terraform-docs version {} from {}".format(version, download_url))

    # Download and extract
    repository_ctx.download_and_extract(
        url = download_url,
        type = "tar.gz",
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

download_terraform_docs = repository_rule(
    implementation = _download_terraform_docs_impl,
    attrs = {
        "version": attr.string(doc = "terraform-docs version to download (latest if not specified)"),
    },
    doc = "Downloads terraform-docs binary from GitHub releases",
)