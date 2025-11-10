#!/usr/bin/env bash
set -euo pipefail

# Buildifier strict lint check script for rules_tf2
# This script enforces both formatting and linting rules

echo "Running strict buildifier checks (formatting + linting)..."

# Find the source directory (when running from Bazel runfiles)
if [[ $(pwd) == *"runfiles"* ]]; then
    # We're in Bazel runfiles, need to find the actual source
    echo "Running from Bazel runfiles, looking for source directory..."

    # Try to find the workspace directory
    if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
        cd "$BUILD_WORKSPACE_DIRECTORY"
        echo "Using BUILD_WORKSPACE_DIRECTORY: $(pwd)"
    elif [ -f "../../../../../../../MODULE.bazel" ]; then
        cd "../../../../../../../"
        echo "Found MODULE.bazel, using: $(pwd)"
    else
        # In test environment, run buildifier on the current runfiles directory
        # which contains all the BUILD and .bzl files as test data
        echo "Running buildifier on test data files in current directory..."
    fi
fi

# Check if buildifier is available
if ! command -v buildifier &> /dev/null; then
    echo "ERROR: buildifier not found in PATH"
    echo "Please install buildifier or run from a nix environment with 'nix develop'"
    exit 1
fi

# Run buildifier and capture output to temporary file to handle large output
TEMP_OUTPUT=$(mktemp)
trap "rm -f $TEMP_OUTPUT" EXIT

set +e  # Don't exit on buildifier warnings
buildifier -lint=warn -mode=check -r . > "$TEMP_OUTPUT" 2>&1
BUILDIFIER_EXIT_CODE=$?
set -e

# Check for formatting issues (files that need reformatting)
if grep -q "# reformat" "$TEMP_OUTPUT"; then
    echo "❌ Files need reformatting:"
    grep "# reformat" "$TEMP_OUTPUT"
    echo ""
    echo "Run: buildifier -mode=fix -r ."
    exit 1
fi

# Check for critical linting warnings
if grep -q -E ": (unused-variable|print)" "$TEMP_OUTPUT"; then
    echo "❌ Critical linting issues found:"
    grep -E ": (unused-variable|print)" "$TEMP_OUTPUT" | head -20
    echo ""
    echo "Fix these critical issues. Full output in temp file if needed."
    exit 1
fi

# Check for documentation warnings (less critical, but still fail in strict mode)
if grep -q -E ": (function-docstring|module-docstring)" "$TEMP_OUTPUT"; then
    echo "❌ Documentation issues found:"
    grep -E ": (function-docstring|module-docstring)" "$TEMP_OUTPUT" | head -10
    echo ""
    echo "Fix documentation issues above. Run with --ignore-docs to skip."
    exit 1
fi

# If buildifier itself failed
if [ $BUILDIFIER_EXIT_CODE -ne 0 ]; then
    echo "❌ Buildifier failed with exit code $BUILDIFIER_EXIT_CODE"
    exit $BUILDIFIER_EXIT_CODE
fi

echo "✅ All BUILD files pass strict formatting and linting checks"