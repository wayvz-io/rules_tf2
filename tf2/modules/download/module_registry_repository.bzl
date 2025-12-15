"""Repository rule for downloading Terraform modules from the Terraform Registry."""

def _parse_registry_source(source):
    """Parse a registry source into components.

    Args:
        source: Registry source string (e.g., "terraform-aws-modules/vpc/aws")

    Returns:
        Tuple of (namespace, name, provider)
    """
    parts = source.split("/")
    if len(parts) != 3:
        fail("Invalid registry source format '{}'. Expected 'namespace/name/provider'.".format(source))
    return parts[0], parts[1], parts[2]

def _parse_private_source(source):
    """Parse a private registry source into components.

    Args:
        source: Private registry source (e.g., "app.terraform.io/my-org/my-module/aws")

    Returns:
        Tuple of (hostname, organization, name, provider)
    """
    parts = source.split("/")
    if len(parts) != 4:
        fail("Invalid private registry source format '{}'. Expected 'hostname/org/name/provider'.".format(source))
    return parts[0], parts[1], parts[2], parts[3]

def _extract_download_url(json_content):
    """Extract download URL from registry API response.

    The Terraform Registry API returns a JSON response that we need to parse
    to find the actual download URL.
    """
    # Look for download_url in the JSON
    for line in json_content.split("\n"):
        line = line.strip()
        if '"download_url"' in line or '"source"' in line:
            # Extract URL from line like: "download_url": "https://..."
            # or "source": "https://..."
            parts = line.split('"')
            for i, part in enumerate(parts):
                if (part == "download_url" or part == "source") and i + 2 < len(parts):
                    url = parts[i + 2]
                    if url.startswith("http"):
                        return url
    return None

def _module_registry_repository_impl(repository_ctx):
    """Download a Terraform module from the Terraform Registry.

    Supports both public (registry.terraform.io) and private registries (app.terraform.io).
    Private registries require TFE_TOKEN environment variable.
    """
    source = repository_ctx.attr.source
    version = repository_ctx.attr.version
    source_type = repository_ctx.attr.source_type
    registry_host = repository_ctx.attr.registry_host

    # Parse source based on type
    if source_type == "private":
        hostname, organization, name, provider = _parse_private_source(source)
        # For private registries, use the API path
        api_url = "https://{}/api/registry/v1/modules/{}/{}/{}/{}/download".format(
            hostname,
            organization,
            name,
            provider,
            version,
        )
        namespace = organization
    else:
        namespace, name, provider = _parse_registry_source(source)
        # Public registry API
        api_url = "https://{}/v1/modules/{}/{}/{}/{}/download".format(
            registry_host,
            namespace,
            name,
            provider,
            version,
        )

    # Step 1: Get download URL from registry API
    # The Terraform Registry returns 204 No Content with X-Terraform-Get header
    # We need to use curl with GET request and capture headers (HEAD returns 405)

    curl_args = [
        "curl",
        "-s",  # Silent mode
        "-D", "-",  # Dump headers to stdout
        "-o", "/dev/null",  # Discard body
        "--connect-timeout", "30",  # Connection timeout in seconds
        "--max-time", "60",  # Total operation timeout in seconds
        "-f",  # Fail on HTTP errors (4xx, 5xx)
        api_url,
    ]

    # Add auth header for private registries
    if source_type == "private":
        tfe_token = repository_ctx.os.environ.get("TFE_TOKEN", "")
        if not tfe_token:
            fail(
                "TFE_TOKEN environment variable is required for private registry modules.\n" +
                "Set it with: export TFE_TOKEN=<your-token>\n" +
                "Module: {}:{}".format(source, version),
            )
        curl_args.extend(["-H", "Authorization: Bearer " + tfe_token])

    result = repository_ctx.execute(curl_args, quiet = True, timeout = 120)

    download_url = None

    if result.return_code == 0:
        # Parse headers to find X-Terraform-Get
        for line in result.stdout.split("\n"):
            line = line.strip()
            if line.lower().startswith("x-terraform-get:"):
                download_url = line.split(":", 1)[1].strip()
                break
            # Also check for Location header (redirect)
            if line.lower().startswith("location:"):
                download_url = line.split(":", 1)[1].strip()

    if not download_url:
        error_msg = "Could not determine download URL for module {}:{}\n".format(source, version)
        if result.return_code != 0:
            error_msg += "Registry API request failed (exit code {}).\n".format(result.return_code)
            if "curl: (28)" in result.stderr:
                error_msg += "Connection timed out. Check your network connection.\n"
            elif "curl: (22)" in result.stderr:
                error_msg += "HTTP error returned. The module or version may not exist.\n"
            error_msg += "stderr: {}\n".format(result.stderr)
        else:
            error_msg += "Registry API did not return X-Terraform-Get header.\n"
        error_msg += "API URL: {}\n".format(api_url)
        error_msg += "Response headers:\n{}\n".format(result.stdout[:500] if len(result.stdout) > 500 else result.stdout)
        fail(error_msg)

    # Transform git-style URLs to downloadable archive URLs
    # git::https://github.com/owner/repo?ref=abc123 -> https://github.com/owner/repo/archive/abc123.tar.gz
    if download_url.startswith("git::"):
        git_url = download_url[5:]  # Remove git:: prefix
        if "?" in git_url:
            base_url, query = git_url.split("?", 1)
            ref = None
            for param in query.split("&"):
                if param.startswith("ref="):
                    ref = param[4:]
                    break
            if ref and "github.com" in base_url:
                # Transform to GitHub archive URL
                download_url = "{}/archive/{}.tar.gz".format(base_url.rstrip("/"), ref)
            else:
                fail("Cannot transform git URL to archive URL: {}".format(download_url))
        else:
            fail("Git URL missing ref parameter: {}".format(download_url))

    # Step 2: Download and extract the module
    archive_type = "tar.gz"
    if download_url.endswith(".zip"):
        archive_type = "zip"

    # Prepare auth headers for private registries
    download_headers = {}
    if source_type == "private":
        tfe_token = repository_ctx.os.environ.get("TFE_TOKEN", "")
        if tfe_token:
            download_headers = {"Authorization": "Bearer " + tfe_token}

    result = repository_ctx.download_and_extract(
        url = download_url,
        headers = download_headers,
        type = archive_type,
        stripPrefix = "",  # Will handle prefix detection below
    )

    # Handle common archive structures where module is in a subdirectory
    # e.g., terraform-aws-vpc-5.0.0/
    result = repository_ctx.execute(["sh", "-c", "ls -d */ 2>/dev/null || true"])
    dirs = []
    for line in result.stdout.split("\n"):
        line = line.strip()
        if line and line.endswith("/"):
            dir_name = line[:-1]  # Remove trailing /
            if dir_name not in [".", ".."]:
                dirs.append(dir_name)

    # If there's exactly one directory and no .tf files at root, use that directory
    result = repository_ctx.execute(["find", ".", "-maxdepth", "1", "-name", "*.tf"])
    has_tf_at_root = result.return_code == 0 and result.stdout.strip()

    if len(dirs) == 1 and not has_tf_at_root:
        # Move contents from subdirectory to root
        subdir = dirs[0]
        repository_ctx.execute(["sh", "-c", """
            mv {subdir} _temp_module
            mv _temp_module/* . 2>/dev/null || true
            mv _temp_module/.* . 2>/dev/null || true
            rm -rf _temp_module
        """.format(subdir = subdir)])

    # Clean up unnecessary files and directories
    # - exports/ contains template files for copying (e.g., cloudposse context.tf)
    # - docs/ contains documentation assets
    repository_ctx.execute(["rm", "-rf", ".git", ".github", ".gitignore", "examples", "tests", "test", "exports", "docs"])

    # Verify we have .tf files
    result = repository_ctx.execute(["find", ".", "-name", "*.tf", "-type", "f"])
    if result.return_code != 0 or not result.stdout.strip():
        fail("No .tf files found in module {} version {}".format(source, version))

    # Create BUILD.bazel
    build_content = '''package(default_visibility = ["//visibility:public"])

filegroup(
    name = "module",
    srcs = glob(["**/*.tf"]) + glob(["**/*.tf.json"], allow_empty = True),
)

filegroup(
    name = "all_files",
    srcs = glob(["**/*"]),
)
'''

    repository_ctx.file("BUILD.bazel", build_content)

    # Create metadata file
    metadata = """{{
  "source": "{source}",
  "source_type": "{source_type}",
  "namespace": "{namespace}",
  "name": "{name}",
  "provider": "{provider}",
  "version": "{version}",
  "registry_host": "{registry_host}",
  "download_url": "{download_url}"
}}""".format(
        source = source,
        source_type = source_type,
        namespace = namespace,
        name = name,
        provider = provider,
        version = version,
        registry_host = registry_host,
        download_url = download_url,
    )
    repository_ctx.file("metadata.json", metadata)

module_registry_repository = repository_rule(
    implementation = _module_registry_repository_impl,
    attrs = {
        "source": attr.string(
            mandatory = True,
            doc = "Module source: 'namespace/name/provider' or 'hostname/org/name/provider'",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "Module version (e.g., '5.0.0')",
        ),
        "source_type": attr.string(
            default = "registry",
            doc = "Source type: 'registry' for public, 'private' for private registries",
            values = ["registry", "private"],
        ),
        "registry_host": attr.string(
            default = "registry.terraform.io",
            doc = "Registry hostname for public modules",
        ),
    },
    environ = ["TFE_TOKEN"],
    doc = """Downloads a Terraform module from the Terraform Registry.

    Supports both public (registry.terraform.io) and private (app.terraform.io) registries.
    Private registries require the TFE_TOKEN environment variable to be set.

    Examples:
        # Public registry module
        module_registry_repository(
            name = "tf_module_vpc_aws_5",
            source = "terraform-aws-modules/vpc/aws",
            version = "5.0.0",
        )

        # Private registry module
        module_registry_repository(
            name = "tf_module_mymod_1",
            source = "app.terraform.io/my-org/my-module/aws",
            version = "1.0.0",
            source_type = "private",
        )
    """,
)
