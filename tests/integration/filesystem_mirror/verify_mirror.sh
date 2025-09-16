#!/usr/bin/env bash
set -euo pipefail

MIRROR_DIR="$1"

echo "Verifying filesystem mirror structure at: $MIRROR_DIR"

# Check if the directory exists
if [ ! -d "$MIRROR_DIR" ]; then
    echo "ERROR: Mirror directory does not exist: $MIRROR_DIR"
    exit 1
fi

# Check for the expected structure
echo "Contents of mirror:"
find "$MIRROR_DIR" -type f -name "terraform-provider-*" || true

# Verify the directory structure
if [ -d "$MIRROR_DIR/registry.terraform.io" ]; then
    echo "✓ Found registry.terraform.io directory"
else
    echo "✗ Missing registry.terraform.io directory"
    exit 1
fi

# Check for at least one provider
PROVIDER_COUNT=$(find "$MIRROR_DIR" -type f -name "terraform-provider-*" | wc -l)
if [ "$PROVIDER_COUNT" -gt 0 ]; then
    echo "✓ Found $PROVIDER_COUNT provider binary/binaries"
else
    echo "✗ No provider binaries found"
    exit 1
fi

echo "Mirror structure verification passed!"