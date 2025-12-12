#!/usr/bin/env bash
set -euo pipefail

# Find runfiles directory
if [[ -n "${TEST_SRCDIR:-}" ]]; then
    RUNFILES="$TEST_SRCDIR"
elif [[ -f "$0.runfiles/MANIFEST" ]]; then
    RUNFILES="$0.runfiles"
elif [[ -f "$0.runfiles/_main/WORKSPACE" ]] || [[ -f "$0.runfiles/_main/WORKSPACE.bazel" ]] || [[ -f "$0.runfiles/_main/MODULE.bazel" ]]; then
    RUNFILES="$0.runfiles"
else
    echo "Cannot find runfiles directory" >&2
    exit 1
fi

# Get paths to test files and tools
TFLINT="$RUNFILES/+tf_tools+tflint_tool/tflint"
TF2_PLUGIN="$RUNFILES/_main/go/tflint_ruleset/tflint-ruleset-tf2_/tflint-ruleset-tf2"
WRONG_VERSION="$RUNFILES/_main/tests/unit/tflint_plugins/tf2/versions/wrong_version.tf"
TFLINT_CONFIG="$RUNFILES/_main/tests/unit/tflint_plugins/tf2/versions/.tflint.hcl"

# Create temp directory for test
TMPDIR="${TMPDIR:-/tmp}"
TEST_DIR="$TMPDIR/tflint_fix_test_$$"
mkdir -p "$TEST_DIR"
trap "rm -rf $TEST_DIR" EXIT

# Copy test file to temp directory (tflint --fix modifies in place)
cp "$WRONG_VERSION" "$TEST_DIR/terraform.tf"
cp "$TFLINT_CONFIG" "$TEST_DIR/.tflint.hcl"

# Set up tf2 plugin
TFLINT_HOME="$TEST_DIR/tflint_home"
mkdir -p "$TFLINT_HOME/.tflint.d/plugins"
cp "$TF2_PLUGIN" "$TFLINT_HOME/.tflint.d/plugins/tflint-ruleset-tf2"
chmod +x "$TFLINT_HOME/.tflint.d/plugins/tflint-ruleset-tf2"
export TFLINT_PLUGIN_DIR="$TFLINT_HOME/.tflint.d/plugins"

# Test 1: Verify tflint detects version mismatch (should fail)
echo "Test 1: Checking that tflint detects version mismatch..."
OUTPUT=$("$TFLINT" --config="$TEST_DIR/.tflint.hcl" --chdir="$TEST_DIR" --only=tf2_terraform_required_providers 2>&1) || true
if echo "$OUTPUT" | grep -q "version constraint does not match"; then
    echo "PASS: TFLint detected version mismatch"
else
    echo "FAIL: TFLint should have detected version mismatch"
    echo "TFLint output was: $OUTPUT"
    exit 1
fi

# Test 2: Run tflint --fix to correct the version
echo ""
echo "Test 2: Running tflint --fix to update version..."
"$TFLINT" --config="$TEST_DIR/.tflint.hcl" --chdir="$TEST_DIR" --only=tf2_terraform_required_providers --fix || true

# Test 3: Verify the file was updated correctly
echo ""
echo "Test 3: Verifying version was updated..."
if grep -q 'version = "3.6.0"' "$TEST_DIR/terraform.tf"; then
    echo "PASS: Version was updated to 3.6.0"
else
    echo "FAIL: Version was not updated correctly"
    echo "File contents:"
    cat "$TEST_DIR/terraform.tf"
    exit 1
fi

# Test 4: Verify tflint now passes
echo ""
echo "Test 4: Verifying tflint now passes..."
if "$TFLINT" --config="$TEST_DIR/.tflint.hcl" --chdir="$TEST_DIR" --only=tf2_terraform_required_providers; then
    echo "PASS: TFLint now passes after fix"
else
    echo "FAIL: TFLint still fails after fix"
    exit 1
fi

echo ""
echo "All tests passed!"
