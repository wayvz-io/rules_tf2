#!/usr/bin/env bash
# Verify TFC agent image structure
# This script loads an OCI image and verifies expected contents

set -euo pipefail

IMAGE_PATH="$1"

echo "Verifying image at: $IMAGE_PATH"

# Check that the image directory exists
if [[ ! -d "$IMAGE_PATH" ]]; then
    echo "ERROR: Image path does not exist or is not a directory: $IMAGE_PATH"
    exit 1
fi

# Check for expected OCI layout files
if [[ -f "$IMAGE_PATH/oci-layout" ]]; then
    echo "OK: Found oci-layout file"
else
    echo "ERROR: Missing oci-layout file"
    exit 1
fi

if [[ -f "$IMAGE_PATH/index.json" ]]; then
    echo "OK: Found index.json"
else
    echo "ERROR: Missing index.json"
    exit 1
fi

if [[ -d "$IMAGE_PATH/blobs" ]]; then
    echo "OK: Found blobs directory"
else
    echo "ERROR: Missing blobs directory"
    exit 1
fi

# Verify the image layers exist
LAYER_COUNT=$(find "$IMAGE_PATH/blobs" -type f | wc -l)
if [[ $LAYER_COUNT -gt 0 ]]; then
    echo "OK: Found $LAYER_COUNT blob files"
else
    echo "ERROR: No blob files found"
    exit 1
fi

echo ""
echo "Image verification passed!"
echo "Note: Full container testing requires Docker/Podman to load and inspect the image"
