#!/usr/bin/env bash
# Generate CDKTF bindings for a Terraform provider
# Usage: generate_cdktf.sh <provider_name> <provider_source> <provider_version>

set -euo pipefail

# Parse arguments
PROVIDER_NAME="${1:?Provider name required}"
PROVIDER_SOURCE="${2:?Provider source required}"  
PROVIDER_VERSION="${3:?Provider version required}"

# Setup environment
export CDKTF_HOME="$PWD/.cdktf"
export HOME="${HOME:-/tmp}"
export CHECKPOINT_DISABLE=1
export JSII_SILENCE_WARNING_UNTESTED_NODE_VERSION=1

# Create a writable temp directory for cdktf
export TMPDIR="$PWD/.tmp"
mkdir -p "$TMPDIR"
mkdir -p "$CDKTF_HOME"

echo "=== Generating CDKTF Go bindings for ${PROVIDER_NAME} v${PROVIDER_VERSION} ==="

# Check if cdktf is available
if ! command -v cdktf &> /dev/null; then
    echo "ERROR: cdktf command not found in PATH"
    echo "PATH is: $PATH"
    exit 1
fi

echo "Using cdktf from: $(which cdktf)"
echo "cdktf version: $(cdktf --version || echo 'version check failed')"

# Create a minimal terraform config to download the provider
cat > terraform.tf <<EOF
terraform {
  required_providers {
    ${PROVIDER_NAME} = {
      source  = "${PROVIDER_SOURCE}"
      version = "${PROVIDER_VERSION}"
    }
  }
}
EOF

# First run terraform init to download providers
echo "Running terraform init to download providers..."
terraform init 2>&1 | tee terraform-init.log || true

# Debug provider binary (optional - can be commented out for production)
echo "=== Checking provider binaries ==="
find .terraform/providers -name "terraform-provider-*" -type f -executable 2>/dev/null | while read provider; do
    echo "Found provider: $provider"
    # Quick test to see if it can execute with Debian libraries
    echo "Testing execution with Debian libraries..."
    LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu:/usr/lib:/lib/aarch64-linux-gnu:/lib" \
    "$provider" --version 2>&1 | head -2 || echo "Provider test failed with exit code: $?"
done
echo "=== Provider check complete ===="

# Create a wrapper script for providers that cdktf will use
cat > terraform-provider-wrapper <<'EOF'
#!/bin/sh
# Run provider with Debian libraries
LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu:/usr/lib:/lib/aarch64-linux-gnu:/lib" exec "$@"
EOF
chmod +x terraform-provider-wrapper

# Use cdktf get to generate bindings
echo "Running: cdktf get -l go"
# Run cdktf WITHOUT setting LD_LIBRARY_PATH (let it use Nix libraries)
# But use TF_PLUGIN_CACHE_DIR to control where providers are cached
CDKTF_EXPERIMENTAL_PROVIDER_SCHEMA_CACHE_PATH=".cdktf-schema-cache" \
CDKTF_DISABLE_PLUGIN_CACHE_ENV=true \
cdktf get -l go 2>&1 | tee cdktf.log

# Check the exit code but don't exit - try to continue
CDKTF_EXIT=$?
if [ $CDKTF_EXIT -ne 0 ]; then
    echo "WARNING: cdktf get failed with exit code $CDKTF_EXIT"
    echo "Log contents:"
    cat cdktf.log || true
    echo "Continuing anyway to see if files were generated..."
fi

# Debug: List what was generated
echo "=== Checking generated files ==="
echo "Contents of current directory:"
ls -la
if [ -d ".gen" ]; then
    echo "Contents of .gen directory:"
    find .gen -type d -maxdepth 3 | head -20
fi

# Check if generation succeeded and move files
if [ -d ".gen" ]; then
    echo "Moving generated files from .gen..."
    # More flexible approach to find and move generated files
    if [ -d ".gen/${PROVIDER_NAME}" ]; then
        echo "Found .gen/${PROVIDER_NAME}, copying..."
        cp -r .gen/${PROVIDER_NAME}/* . 2>/dev/null || true
    elif [ -d ".gen" ]; then
        # Try multiple patterns to find the generated provider
        for pattern in "*${PROVIDER_NAME}*" "hashicorp-${PROVIDER_NAME}" "${PROVIDER_NAME}-provider"; do
            echo "Searching for pattern: $pattern"
            found_dirs=$(find .gen -type d -maxdepth 2 -name "$pattern" 2>/dev/null)
            if [ -n "$found_dirs" ]; then
                echo "Found directories: $found_dirs"
                for dir in $found_dirs; do
                    echo "Copying from $dir"
                    cp -r "$dir"/* . 2>/dev/null || true
                done
                break
            fi
        done
        
        # Last resort: copy everything from .gen
        if [ -z "$(ls -A . | grep -v '^\.')" ]; then
            echo "No provider files found with patterns, copying all from .gen"
            cp -r .gen/* . 2>/dev/null || true
        fi
    fi
    rm -rf .gen
else
    echo "ERROR: .gen directory not created by cdktf"
    echo "Checking for any generated files..."
    find . -name "*.go" -type f | head -10
fi

# Clean up but keep the log for debugging
rm -rf .cdktf cdktf.json .tmp 2>/dev/null || true

echo "=== Generation complete ==="