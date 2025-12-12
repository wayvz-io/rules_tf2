#!/usr/bin/env bash
set -euo pipefail

# Find runfiles directory
RUNFILES="${RUNFILES_DIR:-$0.runfiles}"
if [[ ! -d "$RUNFILES" ]]; then
    RUNFILES="$(dirname "$0")/serve.runfiles"
fi

# Create working directory with write permissions
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Copy docs structure
cp -rL "$RUNFILES/rules_tf2_docs/docs"/* "$WORK_DIR/" 2>/dev/null || cp -rL "$RUNFILES/_main/docs"/* "$WORK_DIR/"
chmod -R u+w "$WORK_DIR"

# Copy stardoc outputs over placeholder files
STARDOC_DIR=""
for prefix in "_main" "rules_tf2_docs"; do
    if [[ -d "$RUNFILES/$prefix/tf2/docs" ]]; then
        STARDOC_DIR="$RUNFILES/$prefix/tf2/docs"
        break
    fi
done

if [[ -z "$STARDOC_DIR" ]]; then
    echo "Warning: Could not find stardoc outputs directory"
    echo "Looked in: $RUNFILES/*/tf2/docs"
    ls -la "$RUNFILES"
else
    echo "Found stardoc outputs in: $STARDOC_DIR"

    # Function to copy stardoc file with auto-generated banner
    copy_stardoc() {
        local src="$1"
        local dst="$2"
        {
            echo '> **Note**: This page is auto-generated from source code docstrings using [Stardoc](https://github.com/bazelbuild/stardoc). Do not edit directly.'
            echo ''
            cat "$src"
        } > "$dst"
        echo "Copied: $src -> $dst"
    }

    copy_stardoc "$STARDOC_DIR/tf_module.md" "$WORK_DIR/src/reference/rules/tf-module.md"
    copy_stardoc "$STARDOC_DIR/tf_runner.md" "$WORK_DIR/src/reference/rules/tf-runner.md"
    copy_stardoc "$STARDOC_DIR/tf_test.md" "$WORK_DIR/src/reference/rules/tf-test.md"
    copy_stardoc "$STARDOC_DIR/tf_variables.md" "$WORK_DIR/src/reference/rules/tf-variables.md"
    copy_stardoc "$STARDOC_DIR/tf_file_export.md" "$WORK_DIR/src/reference/rules/tf-file-export.md"
    copy_stardoc "$STARDOC_DIR/tf_cloud.md" "$WORK_DIR/src/reference/cloud/tf-cloud-configuration.md"
    copy_stardoc "$STARDOC_DIR/provider_mirror.md" "$WORK_DIR/src/reference/providers/provider-mirror.md"
    copy_stardoc "$STARDOC_DIR/tf_publish.md" "$WORK_DIR/src/reference/publishing/tf-module-publish.md"
    copy_stardoc "$STARDOC_DIR/tf_oci.md" "$WORK_DIR/src/reference/publishing/tf-module-push-oci.md"
    copy_stardoc "$STARDOC_DIR/extensions.md" "$WORK_DIR/src/reference/extensions/README.md"
fi

# Find mdbook (handle various runfiles layouts)
MDBOOK=""
for path in \
    "$RUNFILES/nixpkgs_mdbook/bin/mdbook" \
    "$RUNFILES/_main~non_module_deps~nixpkgs_mdbook/bin/mdbook" \
    "$RUNFILES/rules_tf2_docs~non_module_deps~nixpkgs_mdbook/bin/mdbook"; do
    if [[ -x "$path" ]]; then
        MDBOOK="$path"
        break
    fi
done

if [[ -z "$MDBOOK" ]]; then
    echo "Error: Could not find mdbook binary"
    echo "Searched in: $RUNFILES"
    ls -la "$RUNFILES"
    exit 1
fi

echo "Starting mdbook server..."
echo "Documentation will be available at: http://$(hostname):3000"
echo "Press Ctrl+C to stop"
echo ""

cd "$WORK_DIR"
exec "$MDBOOK" serve --hostname 0.0.0.0 --port 3000
