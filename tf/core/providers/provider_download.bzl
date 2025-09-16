"""BUILD rule for downloading individual Terraform provider binaries"""

def _provider_download_impl(ctx):
    """Download and extract a single provider binary."""
    
    # Declare the output directory for the extracted provider
    provider_dir = ctx.actions.declare_directory(ctx.label.name)
    
    # Create a script to download and extract the provider
    script = ctx.actions.declare_file(ctx.label.name + "_download.sh")
    script_content = """#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="$1"
URL="$2"
SHA256="$3"

# Create temp directory for download
TEMP_DIR="${TMPDIR:-/tmp}/provider_download_$$"
mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

# Download the provider archive
echo "Downloading provider from $URL..."
curl -sSL "$URL" -o "$TEMP_DIR/provider.zip"

# Verify checksum if provided
if [ -n "$SHA256" ]; then
    echo "Verifying SHA256 checksum..."
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$SHA256  $TEMP_DIR/provider.zip" | sha256sum -c -
    elif command -v shasum >/dev/null 2>&1; then
        echo "$SHA256  $TEMP_DIR/provider.zip" | shasum -a 256 -c -
    else
        echo "WARNING: Cannot verify checksum - no sha256sum or shasum available"
    fi
fi

# Extract the provider
echo "Extracting provider..."
mkdir -p "$OUTPUT_DIR"
unzip -q "$TEMP_DIR/provider.zip" -d "$OUTPUT_DIR"

# Make the provider executable
chmod +x "$OUTPUT_DIR"/terraform-provider-* 2>/dev/null || true

echo "Provider downloaded successfully"
"""
    
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )
    
    # Run the download script
    ctx.actions.run(
        outputs = [provider_dir],
        inputs = [],
        executable = script,
        arguments = [
            provider_dir.path,
            ctx.attr.url,
            ctx.attr.sha256 or "",
        ],
        mnemonic = "ProviderDownload",
        progress_message = "Downloading provider {}".format(ctx.label.name),
        execution_requirements = {
            "no-sandbox": "1",  # Network access required
            "no-remote-cache": "1",  # Don't cache large binaries remotely
        },
    )
    
    return [DefaultInfo(
        files = depset([provider_dir]),
        runfiles = ctx.runfiles(files = [provider_dir]),
    )]

provider_download = rule(
    implementation = _provider_download_impl,
    attrs = {
        "url": attr.string(
            mandatory = True,
            doc = "URL to download the provider from",
        ),
        "sha256": attr.string(
            doc = "SHA256 hash of the provider archive",
        ),
        "provider": attr.string(
            doc = "Provider source (e.g., hashicorp/aws)",
        ),
        "version": attr.string(
            doc = "Provider version",
        ),
        "platform": attr.string(
            doc = "Platform (e.g., linux_amd64)",
        ),
    },
    doc = """Downloads a single Terraform provider binary.
    
    This rule downloads a provider archive from the specified URL,
    verifies its checksum, and extracts it to a directory.
    
    Example:
        provider_download(
            name = "aws_6_12_0_linux_amd64",
            url = "https://releases.hashicorp.com/terraform-provider-aws/6.12.0/terraform-provider-aws_6.12.0_linux_amd64.zip",
            sha256 = "abc123...",
            provider = "hashicorp/aws",
            version = "6.12.0",
            platform = "linux_amd64",
        )
    """,
)