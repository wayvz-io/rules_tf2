"""Repository rules for downloading external tools like terraform, tflint, and terraform-docs"""

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

# Tool-specific configuration
TOOL_CONFIG = {
    "terraform": {
        "base_url": "https://releases.hashicorp.com/terraform",
        "archive_format": "zip",
        "binary_name": "terraform",
    },
    "tflint": {
        "base_url": "https://github.com/terraform-linters/tflint/releases/download",
        "archive_format": "zip", 
        "binary_name": "tflint",
    },
    "terraform-docs": {
        "base_url": "https://github.com/terraform-docs/terraform-docs/releases/download",
        "archive_format": "tar.gz",
        "binary_name": "terraform-docs",
    },
}

def _get_platform_info(repository_ctx):
    """Determine the current platform for tool downloads."""
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

def _get_terraform_docs_platform(standard_platform):
    """Convert standard platform format to terraform-docs platform format."""
    # terraform-docs uses dashes instead of underscores
    return standard_platform.replace("_", "-")

def _get_latest_version(repository_ctx, tool_name):
    """Get the latest version of a tool from its release API."""
    if tool_name == "terraform":
        # HashiCorp doesn't have a simple API, use a reasonable default
        return "1.12.2"
    elif tool_name == "tflint":
        # GitHub releases API
        result = repository_ctx.execute([
            "curl", "-s", "-L", 
            "https://api.github.com/repos/terraform-linters/tflint/releases/latest"
        ])
        if result.return_code != 0:
            return "0.54.0"  # fallback
        # Parse JSON to get tag_name using Starlark's json module
        response_data = json.decode(result.stdout)
        latest_version = response_data["tag_name"].lstrip("v")
        return latest_version
    elif tool_name == "terraform-docs":
        # GitHub releases API
        result = repository_ctx.execute([
            "curl", "-s", "-L",
            "https://api.github.com/repos/terraform-docs/terraform-docs/releases/latest"
        ])
        if result.return_code != 0:
            return "0.18.0"  # fallback
        # Parse JSON to get tag_name using Starlark's json module
        response_data = json.decode(result.stdout)
        latest_version = response_data["tag_name"].lstrip("v")
        return latest_version
    else:
        fail("Unknown tool: {}".format(tool_name))

def _build_download_url(tool_name, version, platform):
    """Build the download URL for a specific tool version and platform."""
    config = TOOL_CONFIG[tool_name]
    base_url = config["base_url"]
    archive_format = config["archive_format"]
    
    if tool_name == "terraform":
        return "{base_url}/{version}/terraform_{version}_{platform}.{format}".format(
            base_url = base_url,
            version = version,
            platform = platform,
            format = archive_format,
        )
    elif tool_name == "tflint":
        return "{base_url}/v{version}/tflint_{platform}.{format}".format(
            base_url = base_url,
            version = version,
            platform = platform,
            format = archive_format,
        )
    elif tool_name == "terraform-docs":
        # terraform-docs uses different platform naming (dashes instead of underscores)
        tf_docs_platform = _get_terraform_docs_platform(platform)
        return "{base_url}/v{version}/terraform-docs-v{version}-{platform}.{format}".format(
            base_url = base_url,
            version = version,
            platform = tf_docs_platform,
            format = archive_format,
        )
    else:
        fail("Unknown tool: {}".format(tool_name))

def _download_tool_impl(repository_ctx):
    """Implementation of tool download repository rule."""
    tool_name = repository_ctx.attr.tool_name
    version = repository_ctx.attr.version
    platform = _get_platform_info(repository_ctx)
    
    # Use latest version if not specified
    if not version:
        version = _get_latest_version(repository_ctx, tool_name)
    
    # Build download URL
    download_url = _build_download_url(tool_name, version, platform)
    
    # Download and extract the tool
    config = TOOL_CONFIG[tool_name]
    archive_format = config["archive_format"]
    binary_name = config["binary_name"]
    
    print("Downloading {} version {} from {}".format(tool_name, version, download_url))
    
    if archive_format == "zip":
        repository_ctx.download_and_extract(
            url = download_url,
            type = "zip",
        )
    elif archive_format == "tar.gz":
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
'''.format(
        tool_name = tool_name,
        binary_name = binary_name,
    )
    
    repository_ctx.file("BUILD.bazel", build_content)
    
    # Create version info file
    repository_ctx.file("VERSION", version)

download_tool = repository_rule(
    implementation = _download_tool_impl,
    attrs = {
        "tool_name": attr.string(mandatory = True, doc = "Name of the tool to download"),
        "version": attr.string(doc = "Version to download (latest if not specified)"),
    },
    doc = "Downloads a tool binary from its official releases",
)

def _tool_registry_impl(repository_ctx):
    """Implementation of tool registry repository rule."""
    # This rule just creates aliases to the individual tool repositories
    # The actual tool downloading is handled by the module extension
    
    # Create registry BUILD file with aliases
    build_content = '''package(default_visibility = ["//visibility:public"])

alias(
    name = "terraform",
    actual = "@terraform_tool//:bin",
)

alias(
    name = "tflint", 
    actual = "@tflint_tool//:bin",
)

alias(
    name = "terraform-docs",
    actual = "@terraform_docs_tool//:bin", 
)

# Export tool binaries for direct access
alias(
    name = "terraform_bin",
    actual = "@terraform_tool//:bin",
)

alias(
    name = "tflint_bin",
    actual = "@tflint_tool//:bin",
)

alias(
    name = "terraform_docs_bin",
    actual = "@terraform_docs_tool//:bin",
)

# Filegroup to include all tools
filegroup(
    name = "all",
    srcs = [
        "@terraform_tool//:bin",
        "@tflint_tool//:bin", 
        "@terraform_docs_tool//:bin",
    ],
)
'''
    
    repository_ctx.file("BUILD.bazel", build_content)

tool_registry = repository_rule(
    implementation = _tool_registry_impl,
    attrs = {},
    doc = "Creates a registry of downloaded tools with aliases",
)