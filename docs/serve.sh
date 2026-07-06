#!/usr/bin/env bash
set -euo pipefail

# Serve the docs locally with live reload. Extracts the assembled book source
# (//docs:book_src -- static src/ plus the Stardoc-generated reference pages) and
# runs `mdbook serve` on it, so this shows exactly what //docs:book publishes.

RUNFILES="${RUNFILES_DIR:-$0.runfiles}"
if [[ ! -d "$RUNFILES" ]]; then
    RUNFILES="$(dirname "$0")/serve.runfiles"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Locate the assembled source tarball (main repo runfiles, name may vary).
BOOK_SRC=""
for p in "$RUNFILES"/*/docs/book_src.tar.gz; do
    [[ -e "$p" ]] && { BOOK_SRC="$p"; break; }
done
if [[ -z "$BOOK_SRC" ]]; then
    echo "Error: book_src.tar.gz not found in runfiles" >&2
    ls -la "$RUNFILES" >&2
    exit 1
fi
tar -xzf "$BOOK_SRC" -C "$WORK_DIR"
chmod -R u+w "$WORK_DIR"

# Locate the downloaded mdbook binary (external-repo dir name is mangled).
MDBOOK=""
for p in "$RUNFILES"/*mdbook/mdbook; do
    [[ -x "$p" ]] && { MDBOOK="$p"; break; }
done
if [[ -z "$MDBOOK" ]]; then
    echo "Error: could not find mdbook binary" >&2
    ls -la "$RUNFILES" >&2
    exit 1
fi

echo "Documentation will be available at: http://$(hostname):3000"
echo "Press Ctrl+C to stop"
echo ""
cd "$WORK_DIR"
exec "$MDBOOK" serve --hostname 0.0.0.0 --port 3000
