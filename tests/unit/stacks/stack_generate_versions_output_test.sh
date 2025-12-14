#!/usr/bin/env bash
# Test that tf_stack_generate_versions outputs expected provider information

set -euo pipefail

echo "Testing stack _generate_versions output..."

# Set up runfiles
if [ -n "${RUNFILES_DIR:-}" ]; then
    RUNFILES="$RUNFILES_DIR"
elif [ -d "$0.runfiles" ]; then
    RUNFILES="$0.runfiles"
else
    RUNFILES="$(dirname "$0")"
fi

# Find the generate_versions script in runfiles
SCRIPT_PATHS=(
    "$RUNFILES/_main/tests/integration/sample_tf_stack/tf_stack_generate_versions_generate.sh"
    "$RUNFILES/rules_tf2/tests/integration/sample_tf_stack/tf_stack_generate_versions_generate.sh"
)

SCRIPT=""
for path in "${SCRIPT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCRIPT="$path"
        break
    fi
done

if [ -z "$SCRIPT" ]; then
    echo "✗ Could not find _generate_versions script"
    exit 1
fi

# Run the script and capture output
OUTPUT=$("$SCRIPT" 2>&1)

# Verify output contains expected elements
ERRORS=0

# Check for stack name
if echo "$OUTPUT" | grep -q "Stack: tf_stack"; then
    echo "✓ Output contains stack name"
else
    echo "✗ Missing stack name in output"
    ERRORS=$((ERRORS + 1))
fi

# Check for provider configuration section
if echo "$OUTPUT" | grep -q "Provider Configuration"; then
    echo "✓ Output contains provider configuration section"
else
    echo "✗ Missing provider configuration section"
    ERRORS=$((ERRORS + 1))
fi

# Check for providers section
if echo "$OUTPUT" | grep -q "Providers:"; then
    echo "✓ Output contains providers section"
else
    echo "✗ Missing providers section"
    ERRORS=$((ERRORS + 1))
fi

# Check for terraform version
if echo "$OUTPUT" | grep -q "Terraform Version:"; then
    echo "✓ Output contains terraform version"
else
    echo "✗ Missing terraform version"
    ERRORS=$((ERRORS + 1))
fi

# Check for validation message
if echo "$OUTPUT" | grep -q "Stack provider configuration validated"; then
    echo "✓ Output shows validation success"
else
    echo "✗ Missing validation success message"
    ERRORS=$((ERRORS + 1))
fi

# Check for tf-mod guidance
if echo "$OUTPUT" | grep -q "tf-mod"; then
    echo "✓ Output includes tf-mod guidance"
else
    echo "✗ Missing tf-mod guidance"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "✗ Test failed with $ERRORS error(s)"
    echo ""
    echo "Full output:"
    echo "$OUTPUT"
    exit 1
fi

echo "✓ All output checks passed"
