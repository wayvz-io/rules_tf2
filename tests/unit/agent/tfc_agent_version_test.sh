#!/usr/bin/env bash
# Test that tf_agent_base extension is configured to read from versions.json
# and that versions.json has a valid tfc-agent version

set -euo pipefail

VERSIONS_JSON="$1"
MODULE_BAZEL="$2"

# Extract version from versions.json
JSON_VERSION=$(grep -o '"tfc-agent"[[:space:]]*:[[:space:]]*"[^"]*"' "$VERSIONS_JSON" | \
    sed 's/.*"tfc-agent"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [[ -z "$JSON_VERSION" ]]; then
    echo "ERROR: Could not find tfc-agent version in $VERSIONS_JSON"
    exit 1
fi

echo "versions.json tfc-agent version: $JSON_VERSION"

# Verify tf_agent_base extension is configured in MODULE.bazel
if ! grep -q 'tf_agent_base = use_extension' "$MODULE_BAZEL"; then
    echo "ERROR: tf_agent_base extension not found in MODULE.bazel"
    exit 1
fi

# Verify it reads from a versions.json file
if ! grep -q 'tf_agent_base.from_versions_json' "$MODULE_BAZEL"; then
    echo "ERROR: tf_agent_base.from_versions_json not found in MODULE.bazel"
    exit 1
fi

echo "MODULE.bazel uses tf_agent_base extension: OK"

# Verify the version looks valid (semver-like)
if ! [[ "$JSON_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: tfc-agent version '$JSON_VERSION' doesn't look like a valid semver"
    exit 1
fi

echo ""
echo "SUCCESS: tf_agent_base extension configured correctly"
echo "  Version from versions.json: $JSON_VERSION"
