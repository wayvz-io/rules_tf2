#!/usr/bin/env bash
# Script to copy individual source files to work directory

set -euo pipefail

# Arguments
RUNFILES_DIR="$1"
WORK_DIR="$2"
shift 2

# Copy each file provided as argument
while [[ $# -gt 0 ]]; do
    SRC_PATH="$1"
    BASENAME="$2"
    shift 2
    
    SRC_FILE="$RUNFILES_DIR/$SRC_PATH"
    if [ -f "$SRC_FILE" ]; then
        cp "$SRC_FILE" "$WORK_DIR/$BASENAME"
    else
        echo "WARNING: Source file not found: $SRC_FILE"
    fi
done