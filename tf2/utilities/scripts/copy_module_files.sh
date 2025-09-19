#!/usr/bin/env bash
# Script to copy module files to work directory

set -euo pipefail

# Arguments
RUNFILES_DIR="$1"
WORK_DIR="$2"
REPO_NAME="${3:-}"
MODULE_DIR="$4"

# Copy all files from the module directory
if [ -n "$REPO_NAME" ]; then
    # External repository
    MODULE_PATH="$RUNFILES_DIR/$REPO_NAME/$MODULE_DIR"
    if [ ! -d "$MODULE_PATH" ]; then
        # Try with ~~ separator (newer bazel versions)
        MODULE_PATH="$RUNFILES_DIR/${REPO_NAME}~/$MODULE_DIR"
    fi
    
    if [ -d "$MODULE_PATH" ]; then
        cp -r "$MODULE_PATH"/* "$WORK_DIR/" 2>/dev/null || true
    else
        echo "ERROR: Module directory not found at $MODULE_PATH"
        ls -la "$RUNFILES_DIR/$REPO_NAME/" | head -20 || true
        ls -la "$RUNFILES_DIR/${REPO_NAME}~/" | head -20 || true
        exit 1
    fi
else
    # Main workspace
    MODULE_PATH="$RUNFILES_DIR/_main/$MODULE_DIR"
    if [ -d "$MODULE_PATH" ]; then
        cp -r "$MODULE_PATH"/* "$WORK_DIR/" 2>/dev/null || true
    else
        echo "WARNING: Module directory not found at $MODULE_PATH"
    fi
fi