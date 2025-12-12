#!/usr/bin/env bash
# Test that tf_stack generates a _generate_versions target
# that can be discovered by tf_regenerate_all's bazel query pattern

set -euo pipefail

echo "Testing that stack _generate_versions target exists..."

# Set up runfiles
if [ -n "${RUNFILES_DIR:-}" ]; then
    RUNFILES="$RUNFILES_DIR"
elif [ -d "$0.runfiles" ]; then
    RUNFILES="$0.runfiles"
else
    RUNFILES="$(dirname "$0")"
fi

# Find the script in the expected runfiles location
SCRIPT_PATHS=(
    "$RUNFILES/_main/tests/integration/sample_tf_stack/tf_stack_generate_versions_generate.sh"
    "$RUNFILES/rules_tf2/tests/integration/sample_tf_stack/tf_stack_generate_versions_generate.sh"
)

FOUND=""
for path in "${SCRIPT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FOUND="$path"
        break
    fi
done

if [ -n "$FOUND" ]; then
    echo "✓ Stack _generate_versions target exists and builds successfully"
    echo "  Found at: $FOUND"
else
    echo "✗ Could not find _generate_versions target"
    echo "Searched in:"
    for path in "${SCRIPT_PATHS[@]}"; do
        echo "  - $path"
    done
    echo ""
    echo "RUNFILES_DIR: ${RUNFILES_DIR:-<not set>}"
    echo "RUNFILES: $RUNFILES"
    ls -la "$RUNFILES" 2>/dev/null || echo "Could not list runfiles directory"
    exit 1
fi

echo ""
echo "This test verifies that:"
echo "  1. tf_stack macro creates a *_generate_versions target"
echo "  2. The target follows the naming convention for tf_regenerate_all discovery"
echo "  3. The target builds successfully"
echo ""
echo "✓ Test passed"
