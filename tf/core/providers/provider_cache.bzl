"""Provider cache rule for managing multiple provider versions"""

load("//tf/core/rules:info.bzl", "TfProviderCacheInfo")

def _provider_cache_impl(ctx):
    """Implementation of provider_cache rule - downloads all provider versions"""
    
    # Create output directories and files
    cache_dir = ctx.actions.declare_directory(ctx.label.name + "_cache")
    lock_file = ctx.actions.declare_file(ctx.label.name + "/.terraform.lock.hcl")
    manifest_file = ctx.actions.declare_file(ctx.label.name + "/.cache_manifest.json")
    
    # Create download script
    download_script = ctx.actions.declare_file(ctx.label.name + "_download.sh")
    
    # Build provider specifications and validate
    provider_specs = []
    for provider, versions in ctx.attr.providers.items():
        # Validate provider format
        provider_parts = provider.split("/")
        if len(provider_parts) != 2:
            fail("Provider must be in format 'namespace/name', got: " + provider)
        
        namespace, provider_name = provider_parts
        
        for version in versions:
            # Validate version is semver
            version_parts = version.split(".")
            if len(version_parts) != 3:
                fail("Version must be in semver format (X.Y.Z), got: " + version)
            
            for part in version_parts:
                if not part.isdigit():
                    fail("Version components must be numeric, got: " + version)
            
            provider_specs.append(struct(
                provider = provider,
                provider_name = provider_name,
                namespace = namespace,
                version = version,
            ))
    
    # Build terraform.tf content in Starlark
    versions_content = {
        "terraform": {
            "required_providers": {}
        }
    }
    
    for spec in provider_specs:
        versions_content["terraform"]["required_providers"][spec.provider_name] = {
            "source": spec.provider,
            "version": spec.version,
        }
    
    # Build cache manifest in Starlark
    manifest_content = {
        "providers": ctx.attr.providers,
        "generated_by": "provider_cache",
    }
    
    # Generate the shell script (minimal shell, just terraform commands)
    download_script_content = """#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="$1"
LOCK_FILE="$2"
MANIFEST_FILE="$3"

# Save the execroot directory
EXECROOT="$(pwd)"

# Convert paths to absolute
CACHE_DIR="$EXECROOT/$CACHE_DIR"
LOCK_FILE="$EXECROOT/$LOCK_FILE"
MANIFEST_FILE="$EXECROOT/$MANIFEST_FILE"

# Create cache directory
mkdir -p "$CACHE_DIR"

# Create a temporary working directory
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"

# Detect current platform
CURRENT_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
CURRENT_ARCH=$(uname -m)

# Map architecture names
case "$CURRENT_ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $CURRENT_ARCH"; exit 1 ;;
esac

# Map OS names  
case "$CURRENT_OS" in
    linux) OS="linux" ;;
    darwin) OS="darwin" ;;
    *) echo "Unsupported OS: $CURRENT_OS"; exit 1 ;;
esac

PLATFORM="${OS}_${ARCH}"

echo "Creating provider cache with lock file generation..."

# Write the terraform.tf file (as JSON for simplicity)
cat > terraform.tf.json <<'VERSIONS_EOF'
"""
    # Add the JSON content
    download_script_content += json.encode_indent(versions_content, indent = "  ")
    download_script_content += """
VERSIONS_EOF

# Step 1: Initialize and download all providers with --upgrade
echo "Initializing Terraform and downloading providers..."
terraform init -backend=false --upgrade

# Step 2: Mirror providers to cache directory for current platform
echo "Mirroring providers to cache for platform $PLATFORM..."
terraform providers mirror -platform="$PLATFORM" "$CACHE_DIR"

# Step 3: Generate lock file with hashes for all target platforms
echo "Generating lock file with hashes for all platforms..."
terraform providers lock \
    -platform=linux_amd64 \
    -platform=linux_arm64 \
    -platform=darwin_amd64 \
    -platform=darwin_arm64 \
    -platform=windows_amd64

# Step 4: Copy the generated lock file
if [ -f ".terraform.lock.hcl" ]; then
    cp ".terraform.lock.hcl" "$LOCK_FILE"
    echo "Lock file saved to $LOCK_FILE"
else
    echo "ERROR: Failed to generate lock file"
    exit 1
fi

# Step 5: Write the cache manifest
cat > "$MANIFEST_FILE" <<'MANIFEST_EOF'
"""
    # Add manifest JSON
    manifest_content["platform"] = "${PLATFORM}"
    manifest_content["created"] = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    download_script_content += json.encode_indent(manifest_content, indent = "  ")
    download_script_content += """
MANIFEST_EOF

echo "Cache manifest saved to $MANIFEST_FILE"

# Clean up
cd "$EXECROOT"
rm -rf "$WORK_DIR"

echo "Provider cache created successfully with lock file"
"""
    
    ctx.actions.write(
        output = download_script,
        content = download_script_content,
        is_executable = True,
    )
    
    # Run the download script with all outputs
    ctx.actions.run(
        outputs = [cache_dir, lock_file, manifest_file],
        inputs = [],
        executable = download_script,
        arguments = [
            cache_dir.path,
            lock_file.path,
            manifest_file.path,
        ],
        mnemonic = "ProviderCache",
        progress_message = "Creating provider cache with {} providers and lock file".format(len(provider_specs)),
        use_default_shell_env = True,
        execution_requirements = {
            "no-sandbox": "1",  # Network access
            "no-remote-cache": "1",  # Don't upload to remote cache (providers are large)
        },
    )
    
    return [
        TfProviderCacheInfo(
            cache_dir = cache_dir,
            providers = ctx.attr.providers,
            lock_file = lock_file,
        ),
        DefaultInfo(
            files = depset([cache_dir, lock_file, manifest_file]),
            runfiles = ctx.runfiles(files = [cache_dir, lock_file, manifest_file]),
        ),
    ]

provider_cache = rule(
    implementation = _provider_cache_impl,
    attrs = {
        "providers": attr.string_list_dict(
            doc = "Dictionary of providers to versions (e.g., {'hashicorp/aws': ['6.2.0', '5.0.0']})",
            mandatory = True,
        ),
    },
    doc = """Creates a shared provider cache with multiple provider versions.
    
    This rule downloads all specified provider versions once and stores them
    in a shared cache directory. Provider aliases can then reference specific
    versions from this cache without re-downloading.
    
    Example:
        provider_cache(
            name = "shared_cache",
            providers = {
                "hashicorp/aws": ["6.2.0", "5.0.0"],
                "hashicorp/kubernetes": ["2.38.0"],
                "1Password/onepassword": ["2.1.2"],
            },
        )
    """,
)