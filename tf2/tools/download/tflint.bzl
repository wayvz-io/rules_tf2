"""TFLint tool and plugins download rules"""

load(":platform.bzl", "get_platform_info")

# TFLint configuration
TFLINT_CONFIG = {
    "base_url": "https://github.com/terraform-linters/tflint/releases/download",
    "archive_format": "zip",
    "binary_name": "tflint",
    "fallback_version": "0.59.1",
}

# TFLint plugin configuration
TFLINT_PLUGIN_CONFIG = {
    "aws": {
        "repo": "terraform-linters/tflint-ruleset-aws",
        "binary_name": "tflint-ruleset-aws",
    },
    "azurerm": {
        "repo": "terraform-linters/tflint-ruleset-azurerm",
        "binary_name": "tflint-ruleset-azurerm",
    },
    "google": {
        "repo": "terraform-linters/tflint-ruleset-google",
        "binary_name": "tflint-ruleset-google",
    },
    "opa": {
        "repo": "terraform-linters/tflint-ruleset-opa",
        "binary_name": "tflint-ruleset-opa",
    },
    "terraform": {
        "repo": "terraform-linters/tflint-ruleset-terraform",
        "binary_name": "tflint-ruleset-terraform",
    },
}

def _get_latest_tflint_version(repository_ctx):
    """Get the latest version of TFLint from GitHub API.

    Args:
        repository_ctx: Repository rule context

    Returns:
        String version number
    """
    result = repository_ctx.execute([
        "curl",
        "-s",
        "-L",
        "https://api.github.com/repos/terraform-linters/tflint/releases/latest",
    ])
    if result.return_code != 0:
        return TFLINT_CONFIG["fallback_version"]

    # Parse JSON to get tag_name
    response_data = json.decode(result.stdout)
    latest_version = response_data["tag_name"].lstrip("v")
    return latest_version

def _build_tflint_download_url(version, platform):
    """Build the download URL for TFLint.

    Args:
        version: TFLint version to download
        platform: Platform identifier (e.g., "linux_amd64")

    Returns:
        String download URL
    """
    base_url = TFLINT_CONFIG["base_url"]
    archive_format = TFLINT_CONFIG["archive_format"]

    return "{base_url}/v{version}/tflint_{platform}.{format}".format(
        base_url = base_url,
        version = version,
        platform = platform,
        format = archive_format,
    )

def _download_tflint_impl(repository_ctx):
    """Implementation of TFLint download repository rule.

    Args:
        repository_ctx: Repository rule context
    """
    version = repository_ctx.attr.version
    if not version:
        version = _get_latest_tflint_version(repository_ctx)

    platform = get_platform_info(repository_ctx)

    # Build download URL
    download_url = _build_tflint_download_url(version, platform)
    binary_name = TFLINT_CONFIG["binary_name"]

    # Download and extract
    repository_ctx.download_and_extract(
        url = download_url,
        type = "zip",
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

download_tflint = repository_rule(
    implementation = _download_tflint_impl,
    attrs = {
        "version": attr.string(doc = "TFLint version to download (latest if not specified)"),
    },
    doc = "Downloads TFLint binary from GitHub releases",
)

def _build_plugin_download_url(plugin_name, version, platform):
    """Build the download URL for a TFLint plugin.

    Args:
        plugin_name: Name of the plugin (aws, azurerm, google, opa)
        version: Plugin version to download
        platform: Platform identifier (e.g., "linux_amd64")

    Returns:
        String download URL
    """
    if plugin_name not in TFLINT_PLUGIN_CONFIG:
        fail("Unknown tflint plugin: {}".format(plugin_name))

    config = TFLINT_PLUGIN_CONFIG[plugin_name]
    repo = config["repo"]
    binary_name = config["binary_name"]

    return "https://github.com/{repo}/releases/download/v{version}/{binary_name}_{platform}.zip".format(
        repo = repo,
        version = version,
        binary_name = binary_name,
        platform = platform,
    )

def _download_tflint_plugin_impl(repository_ctx):
    """Implementation of TFLint plugin download repository rule.

    Args:
        repository_ctx: Repository rule context
    """
    plugin_name = repository_ctx.attr.plugin_name
    version = repository_ctx.attr.version
    platform = get_platform_info(repository_ctx)

    if plugin_name not in TFLINT_PLUGIN_CONFIG:
        fail("Unknown tflint plugin: {}. Supported plugins: {}".format(
            plugin_name,
            ", ".join(TFLINT_PLUGIN_CONFIG.keys()),
        ))

    config = TFLINT_PLUGIN_CONFIG[plugin_name]
    binary_name = config["binary_name"]

    # Build download URL
    download_url = _build_plugin_download_url(plugin_name, version, platform)

    # Download and extract the plugin
    repository_ctx.download_and_extract(
        url = download_url,
        type = "zip",
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

    # Create plugin info file
    repository_ctx.file("PLUGIN_NAME", plugin_name)

download_tflint_plugin = repository_rule(
    implementation = _download_tflint_plugin_impl,
    attrs = {
        "plugin_name": attr.string(mandatory = True, doc = "Name of the tflint plugin to download"),
        "version": attr.string(mandatory = True, doc = "Version of the plugin to download"),
    },
    doc = "Downloads a TFLint plugin binary from its GitHub releases",
)
