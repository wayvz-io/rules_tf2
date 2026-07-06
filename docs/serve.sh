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

# Drop the Stardoc-generated reference pages (//docs:reference_pages) into the
# book source tree. Each page ships under docs/gen/<in-book-path>; its
# destination is the part of the path after "gen/". This mirrors what the
# //docs:book genrule does, so `serve` shows exactly what gets published.
found_pages=0
while IFS= read -r f; do
    rel="${f##*/gen/}"
    mkdir -p "$WORK_DIR/src/$(dirname "$rel")"
    cp "$f" "$WORK_DIR/src/$rel"
    found_pages=1
done < <(find "$RUNFILES" -path "*/docs/gen/*.md" 2>/dev/null)

if [[ "$found_pages" -eq 0 ]]; then
    echo "Warning: no Stardoc-generated reference pages found under $RUNFILES/*/docs/gen"
fi

# Find the downloaded @mdbook binary (handle various runfiles layouts)
MDBOOK=""
for path in \
    "$RUNFILES/_main+non_module_deps+mdbook/mdbook" \
    "$RUNFILES/rules_tf2_docs+non_module_deps+mdbook/mdbook" \
    "$RUNFILES/mdbook/mdbook"; do
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
