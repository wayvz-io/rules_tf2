"""BUILD rule for downloading individual Terraform provider binaries using actions"""

def _provider_download_action_impl(ctx):
    """Download and extract a single provider binary using Bazel actions."""
    
    # Declare the output directory for the extracted provider
    provider_dir = ctx.actions.declare_directory(ctx.label.name)
    
    # Create a script that will be run with shell access
    script = ctx.actions.declare_file(ctx.label.name + "_download.sh")
    
    # Use Bazel's download_and_extract action if available
    # Otherwise fall back to a shell script that uses system tools
    script_content = """#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="$1"
URL="$2"
SHA256="${3:-}"

# Convert OUTPUT_DIR to absolute path
OUTPUT_DIR=$(realpath "$OUTPUT_DIR" 2>/dev/null || echo "$OUTPUT_DIR")

# For non-HashiCorp providers, the URL returns JSON with the actual download URL
# Check if the URL is a registry API endpoint
if [[ "$URL" == *"registry.terraform.io/v1/providers"* ]]; then
    
    # Download the JSON response
    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_JSON=$(curl -s "$URL")
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_JSON=$(wget -q -O - "$URL")
    else
        echo "ERROR: Neither wget nor curl is available"
        exit 1
    fi
    
    # Extract the actual download URL from JSON using grep and sed
    # This is a simple approach that avoids requiring jq
    ACTUAL_URL=$(echo "$DOWNLOAD_JSON" | grep -o '"download_url":"[^"]*' | sed 's/"download_url":"//')
    
    if [ -z "$ACTUAL_URL" ]; then
        echo "ERROR: Could not extract download URL from registry response"
        echo "Response: $DOWNLOAD_JSON"
        exit 1
    fi
    
    URL="$ACTUAL_URL"
fi

# Download the provider zip file
# Create a temp directory for download to avoid conflicts
DOWNLOAD_DIR=$(mktemp -d)
ORIG_DIR=$(pwd)
cd "$DOWNLOAD_DIR"

if command -v curl >/dev/null 2>&1; then
    curl -sL -f "$URL" -o provider.zip || {
        echo "ERROR: Failed to download from $URL"
        exit 1
    }
elif command -v wget >/dev/null 2>&1; then
    wget -q -O provider.zip "$URL" || {
        echo "ERROR: Failed to download from $URL"
        exit 1
    }
else
    echo "ERROR: Neither wget nor curl is available"
    exit 1
fi

# Verify checksum (required for security)
# SHA256 contains comma-separated list of hex SHA256 hashes (zh format)
if [ -z "$SHA256" ]; then
    echo "ERROR: No SHA256 hashes provided for provider verification"
    echo "Provider downloads require hash verification for security"
    echo "Run 'bazel run //:tf-update' to generate provider locks with hashes"
    exit 1
fi

if [ -n "$SHA256" ]; then
    # Calculate the actual SHA256 of the downloaded file
    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL_HEX=$(sha256sum provider.zip | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        ACTUAL_HEX=$(shasum -a 256 provider.zip | cut -d' ' -f1)
    else
        echo "ERROR: Cannot calculate checksum - no sha256sum or shasum available"
        exit 1
    fi
    
    # Check if our hash matches any of the provided hashes
    HASH_FOUND=false
    
    # SHA256 contains comma-separated hex hashes
    IFS=',' read -ra HASHES <<< "$SHA256"
    for hash in "${HASHES[@]}"; do
        # Trim whitespace
        hash=$(echo "$hash" | tr -d ' ')
        
        # Compare hex hashes
        if [ "$hash" = "$ACTUAL_HEX" ]; then
            HASH_FOUND=true
            break
        fi
    done
    
    if [ "$HASH_FOUND" = false ]; then
        echo "ERROR: Provider checksum verification failed!"
        echo "Expected one of: $SHA256"
        echo "Actual: $ACTUAL_HEX"
        exit 1
    fi
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Extract the provider
unzip -q -o provider.zip -d "$OUTPUT_DIR" || {
    echo "WARNING: unzip reported issues, trying to continue..."
    echo "Unzip exit code: $?"
    # Sometimes the zip has warnings but the files extract OK
}

# Make the provider executable
chmod +x "$OUTPUT_DIR"/terraform-provider-* 2>/dev/null || true

# Clean up
cd /
rm -rf "$DOWNLOAD_DIR"
"""
    
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )
    
    # Run the download script with use_default_shell_env to get system tools
    ctx.actions.run_shell(
        outputs = [provider_dir],
        command = "{script} {output} {url} {sha256}".format(
            script = script.path,
            output = provider_dir.path,
            url = ctx.attr.url,
            sha256 = ctx.attr.sha256 or "",
        ),
        tools = [script],
        mnemonic = "ProviderDownload",
        progress_message = "Downloading provider {}".format(ctx.label.name),
        use_default_shell_env = True,  # This gives us access to system tools
        execution_requirements = {
            "no-sandbox": "1",  # Network access required
            "no-remote-cache": "1",  # Don't cache large binaries remotely
        },
    )
    
    return [DefaultInfo(
        files = depset([provider_dir]),
        runfiles = ctx.runfiles(files = [provider_dir]),
    )]

provider_download_action = rule(
    implementation = _provider_download_action_impl,
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
    doc = """Downloads a single Terraform provider binary using Bazel actions.
    
    This rule downloads a provider archive from the specified URL,
    verifies its checksum, and extracts it to a directory.
    
    Example:
        provider_download_action(
            name = "aws_6_12_0_linux_amd64",
            url = "https://releases.hashicorp.com/terraform-provider-aws/6.12.0/terraform-provider-aws_6.12.0_linux_amd64.zip",
            sha256 = "abc123...",
            provider = "hashicorp/aws",
            version = "6.12.0",
            platform = "linux_amd64",
        )
    """,
)