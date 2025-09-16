#!/usr/bin/env bash
# Fix import paths in generated CDKTF Go files
# Usage: fix_imports.sh <provider_name> <major_version>

set -euo pipefail

PROVIDER_NAME="${1:?Provider name required}"
MAJOR_VERSION="${2:?Major version required}"

echo "Fixing imports in Go files for ${PROVIDER_NAME} v${MAJOR_VERSION}..."

# Count files for progress reporting
file_count=$(find . -name "*.go" -type f | wc -l)
echo "Found $file_count Go files to process"

# Process files in batches using find -exec for better performance
# This is much faster than a shell loop for large numbers of files
# The CDKTF generator creates imports like "cdktf_aws_6/.gen/aws/..." 
# but we need "cdktf_aws_6/..."
find . -name "*.go" -type f -exec sed -i.bak \
    "s|cdktf_${PROVIDER_NAME}_${MAJOR_VERSION}/\.gen/[^/]*/|cdktf_${PROVIDER_NAME}_${MAJOR_VERSION}/|g" {} +

# Clean up backup files
find . -name "*.bak" -type f -delete

echo "Import fix complete for $file_count files"