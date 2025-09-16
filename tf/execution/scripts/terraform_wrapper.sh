#!/usr/bin/env bash
# Main terraform wrapper script

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up runfiles directory
if [ -z "${RUNFILES_DIR:-}" ]; then
    if [ -n "${RUNFILES_MANIFEST_FILE:-}" ]; then
        RUNFILES="$RUNFILES_MANIFEST_FILE"
    elif [ -n "${BASH_SOURCE[0]:-}" ]; then
        # First check if we're in a runfiles directory already
        if [[ "$SCRIPT_DIR" == *".runfiles"* ]]; then
            RUNFILES="$SCRIPT_DIR"
            while [[ "$RUNFILES" != *.runfiles ]] && [ "$RUNFILES" != "/" ]; do
                RUNFILES="$(dirname "$RUNFILES")"
            done
        else
            # Try script location with .runfiles suffix
            RUNFILES="${BASH_SOURCE[0]}.runfiles"
        fi
    else
        echo >&2 "ERROR: Cannot find runfiles directory"
        exit 1
    fi
else
    RUNFILES="$RUNFILES_DIR"
fi

# Create a temporary working directory
WORK_DIR=$(mktemp -d -t terraform-XXXXXX)

# Ensure cleanup happens even on script exit
cleanup() {
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        chmod -R u+w "$WORK_DIR" 2>/dev/null || true
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT INT TERM

# Disable Terraform from accessing the network
export TF_DISABLE_CHECKPOINT=true
export CHECKPOINT_DISABLE=true

# Parse wrapper arguments (these come before the -- separator)
COPY_MODULE_ARGS=""
COPY_SOURCE_ARGS=""
TERRAFORM_COMMANDS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --copy-module)
            # Format: --copy-module REPO_NAME MODULE_DIR
            # or: --copy-module MODULE_DIR (for main workspace)
            if [[ "$2" == "" ]] || [[ "$2" == --* ]]; then
                # Main workspace
                COPY_MODULE_ARGS="$RUNFILES $WORK_DIR '' $2"
            else
                # Check if $3 exists and doesn't start with --
                if [[ -n "${3:-}" ]] && [[ "$3" != --* ]]; then
                    # External repo
                    COPY_MODULE_ARGS="$RUNFILES $WORK_DIR $2 $3"
                    shift
                else
                    # Main workspace
                    COPY_MODULE_ARGS="$RUNFILES $WORK_DIR '' $2"
                fi
            fi
            shift 2
            ;;
        --copy-source)
            # Format: --copy-source SRC_PATH BASENAME
            COPY_SOURCE_ARGS="$COPY_SOURCE_ARGS $2 $3"
            shift 3
            ;;
        --)
            shift
            TERRAFORM_COMMANDS="$*"
            break
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Copy module files if requested
if [ -n "$COPY_MODULE_ARGS" ]; then
    "$SCRIPT_DIR/copy_module_files.sh" $COPY_MODULE_ARGS
fi

# Copy source files if requested
if [ -n "$COPY_SOURCE_ARGS" ]; then
    "$SCRIPT_DIR/copy_source_files.sh" "$RUNFILES" "$WORK_DIR" $COPY_SOURCE_ARGS
fi

# Change to work directory
cd "$WORK_DIR"

# Execute terraform commands
eval "$TERRAFORM_COMMANDS"