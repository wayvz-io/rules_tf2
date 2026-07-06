"""Terraform tool download rules"""

load(":platform.bzl", "PLATFORM_IDS", "get_platform_info")

# Terraform-specific configuration
TERRAFORM_CONFIG = {
    "base_url": "https://releases.hashicorp.com/terraform",
    "archive_format": "zip",
    "binary_name": "terraform",
    "default_version": "1.12.2",  # HashiCorp doesn't have a simple API, use reasonable default
}

def terraform_fetch_spec(version, platform):
    """Return the hermetic-fetch spec (checksums + URLs) for a Terraform version.

    HashiCorp publishes a `terraform_<v>_SHA256SUMS` file listing every
    platform, so one fetch locks a portable lockfile.
    """
    v = version or TERRAFORM_CONFIG["default_version"]
    return struct(
        version = v,
        sums_url = "{base}/{v}/terraform_{v}_SHA256SUMS".format(base = TERRAFORM_CONFIG["base_url"], v = v),
        platform_files = {p: "terraform_{v}_{p}.zip".format(v = v, p = p) for p in PLATFORM_IDS},
        artifact_url = _build_terraform_download_url(v, platform),
    )

def _build_terraform_download_url(version, platform):
    """Build the download URL for Terraform.

    Args:
        version: Terraform version to download
        platform: Platform identifier (e.g., "linux_amd64")

    Returns:
        String download URL
    """
    base_url = TERRAFORM_CONFIG["base_url"]
    archive_format = TERRAFORM_CONFIG["archive_format"]

    return "{base_url}/{version}/terraform_{version}_{platform}.{format}".format(
        base_url = base_url,
        version = version,
        platform = platform,
        format = archive_format,
    )

def _download_terraform_impl(repository_ctx):
    """Implementation of terraform download repository rule.

    Args:
        repository_ctx: Repository rule context
    """
    version = repository_ctx.attr.version or TERRAFORM_CONFIG["default_version"]
    platform = get_platform_info(repository_ctx)

    # Build download URL
    download_url = _build_terraform_download_url(version, platform)
    binary_name = TERRAFORM_CONFIG["binary_name"]

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

download_terraform = repository_rule(
    implementation = _download_terraform_impl,
    attrs = {
        "version": attr.string(doc = "Terraform version to download (uses default if not specified)"),
        "sha256": attr.string(doc = "Expected sha256 of the platform archive; verified on download when set"),
    },
    doc = "Downloads Terraform binary from HashiCorp releases",
)
