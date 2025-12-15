"""Repository rule for generating provider hashes using terraform providers lock.

This rule downloads terraform, runs `terraform providers lock` for a specific provider,
and extracts the h1/zh hashes from the generated .terraform.lock.hcl file.

The hashes are output as a JSON file that can be read by the tf_providers extension
and stored in module_ctx.facts for persistence across builds.
"""

load("//tf2/providers/repository:hcl_parser.bzl", "parse_lock_hcl", "sanitize_provider_key")
load("//tf2/tools/download:platform.bzl", "get_platform_info")

# Terraform download configuration
_TERRAFORM_BASE_URL = "https://releases.hashicorp.com/terraform"
_DEFAULT_TERRAFORM_VERSION = "1.14.2"

# Platforms to generate hashes for
_TARGET_PLATFORMS = [
    "linux_amd64",
    "linux_arm64",
    "darwin_amd64",
    "darwin_arm64",
    "windows_amd64",
]

def _get_terraform_download_url(version, platform):
    """Build download URL for terraform.

    Args:
        version: Terraform version (e.g., "1.14.2")
        platform: Platform string (e.g., "linux_amd64")

    Returns:
        Download URL string
    """
    return "{base}/{version}/terraform_{version}_{platform}.zip".format(
        base = _TERRAFORM_BASE_URL,
        version = version,
        platform = platform,
    )

def _download_terraform(repository_ctx, version):
    """Download terraform binary for hash generation.

    Args:
        repository_ctx: Repository rule context
        version: Terraform version to download

    Returns:
        Path to terraform binary
    """
    platform = get_platform_info(repository_ctx)
    url = _get_terraform_download_url(version, platform)

    # Download and extract to terraform_bin directory
    repository_ctx.download_and_extract(
        url = url,
        output = "terraform_bin",
        type = "zip",
    )

    terraform_path = repository_ctx.path("terraform_bin/terraform")

    # Make executable
    result = repository_ctx.execute(["chmod", "+x", str(terraform_path)])
    if result.return_code != 0:
        fail("Failed to make terraform executable: {}".format(result.stderr))

    return terraform_path

def _create_provider_terraform_config(repository_ctx, provider_source, version):
    """Create terraform configuration files for the provider.

    Args:
        repository_ctx: Repository rule context
        provider_source: Provider source (e.g., "hashicorp/aws")
        version: Provider version (e.g., "6.26.0")
    """
    provider_name = provider_source.split("/")[-1]

    # Create main.tf
    repository_ctx.file("work/main.tf", """terraform {
  required_version = ">= 1.0"
}
""")

    # Create versions.tf with the provider requirement
    versions_tf = """terraform {{
  required_providers {{
    {name} = {{
      source  = "{source}"
      version = "= {version}"
    }}
  }}
}}
""".format(name = provider_name, source = provider_source, version = version)

    repository_ctx.file("work/versions.tf", versions_tf)

def _run_terraform_providers_lock(repository_ctx, terraform_path, provider_source, version):
    """Run terraform init and providers lock to generate hashes.

    Args:
        repository_ctx: Repository rule context
        terraform_path: Path to terraform binary
        provider_source: Provider source (e.g., "hashicorp/aws")
        version: Provider version

    Returns:
        Dict with h1 and zh hashes
    """
    work_dir = str(repository_ctx.path("work"))

    # Run terraform init
    result = repository_ctx.execute(
        [str(terraform_path), "init", "-backend=false"],
        working_directory = work_dir,
        timeout = 600,
        environment = {
            "TF_LOG": "",  # Disable verbose logging
            "TF_PLUGIN_CACHE_DIR": "",  # Don't use cache for determinism
        },
    )
    if result.return_code != 0:
        fail("terraform init failed for {}:{}\nstdout: {}\nstderr: {}".format(
            provider_source,
            version,
            result.stdout,
            result.stderr,
        ))

    # Build platform arguments
    platform_args = []
    for platform in _TARGET_PLATFORMS:
        platform_args.extend(["-platform=" + platform])

    # Run terraform providers lock
    lock_cmd = [str(terraform_path), "providers", "lock"] + platform_args
    result = repository_ctx.execute(
        lock_cmd,
        working_directory = work_dir,
        timeout = 1800,  # 30 minutes for large providers
        environment = {
            "TF_LOG": "",
        },
    )
    if result.return_code != 0:
        fail("terraform providers lock failed for {}:{}\nstdout: {}\nstderr: {}".format(
            provider_source,
            version,
            result.stdout,
            result.stderr,
        ))

    # Read and parse the lock file
    lock_file_path = repository_ctx.path("work/.terraform.lock.hcl")
    if not lock_file_path.exists:
        fail("No .terraform.lock.hcl generated for {}:{}".format(provider_source, version))

    lock_content = repository_ctx.read(lock_file_path)
    return parse_lock_hcl(lock_content)

def _find_downloaded_provider(repository_ctx, provider_source, version):
    """Find the provider binary that was downloaded during terraform init.

    Args:
        repository_ctx: Repository rule context
        provider_source: Provider source (e.g., "hashicorp/aws")
        version: Provider version

    Returns:
        Path to the provider binary, or None if not found
    """

    # Provider binaries are in .terraform/providers/registry.terraform.io/{namespace}/{name}/{version}/{platform}/
    provider_dir = repository_ctx.path("work/.terraform/providers")

    # Use find to locate the provider binary
    result = repository_ctx.execute([
        "find",
        str(provider_dir),
        "-name",
        "terraform-provider-*",
        "-type",
        "f",
    ])

    if result.return_code == 0 and result.stdout.strip():
        # Return the first match (there should be one per platform, we pick the host platform)
        found = result.stdout.strip().split("\n")[0]
        return repository_ctx.path(found)

    return None

def _provider_hash_generator_impl(repository_ctx):
    """Implementation of provider hash generator repository rule.

    This rule:
    1. Downloads terraform
    2. Creates a minimal terraform config for the provider
    3. Runs terraform init + providers lock
    4. Parses the generated lock file for hashes
    5. Outputs hashes.json and optionally the provider binary
    """
    provider_source = repository_ctx.attr.provider_source
    version = repository_ctx.attr.version
    terraform_version = repository_ctx.attr.terraform_version or _DEFAULT_TERRAFORM_VERSION

    # Download terraform
    terraform_path = _download_terraform(repository_ctx, terraform_version)

    # Create terraform configuration
    _create_provider_terraform_config(repository_ctx, provider_source, version)

    # Run terraform providers lock to generate hashes
    hashes = _run_terraform_providers_lock(repository_ctx, terraform_path, provider_source, version)

    # Find the downloaded provider binary (optimization: avoid re-download)
    provider_binary_path = None
    if repository_ctx.attr.include_binary:
        provider_binary_path = _find_downloaded_provider(repository_ctx, provider_source, version)

    # Write hashes.json
    hashes_json = json.encode_indent(hashes, indent = "  ")
    repository_ctx.file("hashes.json", hashes_json)

    # Create BUILD.bazel
    build_content = """package(default_visibility = ["//visibility:public"])

exports_files(["hashes.json"])

filegroup(
    name = "hashes",
    srcs = ["hashes.json"],
)
"""

    # If we have the provider binary, export it too
    if provider_binary_path:
        provider_name = provider_source.split("/")[-1]
        binary_name = "terraform-provider-{}_v{}".format(provider_name, version)

        # Copy the binary to the repository root
        repository_ctx.symlink(provider_binary_path, binary_name)

        build_content += """
exports_files(["{binary}"])

filegroup(
    name = "provider_binary",
    srcs = ["{binary}"],
)

filegroup(
    name = "files",
    srcs = ["{binary}"],
)
""".format(binary = binary_name)

    repository_ctx.file("BUILD.bazel", build_content)

    # Write metadata for debugging
    metadata = {
        "provider_source": provider_source,
        "version": version,
        "terraform_version": terraform_version,
        "hashes": hashes,
    }
    repository_ctx.file("metadata.json", json.encode_indent(metadata, indent = "  "))

provider_hash_generator = repository_rule(
    implementation = _provider_hash_generator_impl,
    attrs = {
        "provider_source": attr.string(
            mandatory = True,
            doc = "Provider source (e.g., 'hashicorp/aws')",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "Provider version (e.g., '6.26.0')",
        ),
        "terraform_version": attr.string(
            default = "",
            doc = "Terraform version to use for hash generation (defaults to {}".format(_DEFAULT_TERRAFORM_VERSION),
        ),
        "include_binary": attr.bool(
            default = True,
            doc = "Whether to include the downloaded provider binary in the output",
        ),
    },
    doc = """Generates provider hashes by running terraform providers lock.

This repository rule:
1. Downloads terraform binary
2. Creates minimal terraform config for the provider
3. Runs `terraform init` and `terraform providers lock`
4. Parses .terraform.lock.hcl to extract h1/zh hashes
5. Outputs hashes.json (and optionally the provider binary)

The hashes are used by tf_providers extension and stored in MODULE.bazel.lock.

Example:
    provider_hash_generator(
        name = "tf_hash_gen_hashicorp_aws_6_26_0",
        provider_source = "hashicorp/aws",
        version = "6.26.0",
    )
""",
)
