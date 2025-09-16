#!/usr/bin/env bash
# Terraform init script with plugin directory support

set -euo pipefail

# Parse arguments
BACKEND_FLAG=""
UPGRADE_FLAG=""
PLUGIN_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-backend)
            BACKEND_FLAG="-backend=false"
            shift
            ;;
        --no-upgrade)
            UPGRADE_FLAG="-upgrade=false"
            shift
            ;;
        --plugin-dir)
            PLUGIN_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Build init command
INIT_CMD="terraform init"
[ -n "$BACKEND_FLAG" ] && INIT_CMD="$INIT_CMD $BACKEND_FLAG"
[ -n "$UPGRADE_FLAG" ] && INIT_CMD="$INIT_CMD $UPGRADE_FLAG"

# Use provider library if available
if [ -n "$PLUGIN_DIR" ]; then
    if [ -d "$PLUGIN_DIR" ]; then
        # Disable provider installation - we're using pre-downloaded providers
        export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=1
        
        # Run init with plugin directory, suppress verbose output
        $INIT_CMD -plugin-dir "$PLUGIN_DIR" -no-color 2>&1 | \
            grep -v "^Initializing" | \
            grep -v "^- Finding" | \
            grep -v "^- Installing" | \
            grep -v "^Terraform has been successfully initialized" | \
            grep -v "^You may now begin working" | \
            grep -v "^If you ever set or change" | \
            grep -v "^rerun this command" | \
            grep -v "^Terraform has created a lock file" | \
            grep -v "^selections it made above" | \
            grep -v "^so that Terraform can guarantee" | \
            grep -v "^you run \"terraform init\"" | \
            grep -v "Warning: Incomplete lock file" | \
            grep -v "Due to your customized provider" | \
            grep -v "to calculate lock file" | \
            grep -v "The current .terraform.lock.hcl" | \
            grep -v "so Terraform running on another" | \
            grep -v "To calculate additional checksums" | \
            grep -v "terraform providers lock" | \
            grep -v "(where .* is the platform" || true
        
        # Check if init actually succeeded
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "ERROR: terraform init failed"
            # Re-run to show full error output
            $INIT_CMD -plugin-dir "$PLUGIN_DIR" -no-color
            exit 1
        fi
    else
        echo "ERROR: Plugin directory not found at $PLUGIN_DIR"
        exit 1
    fi
else
    # Run init without plugin directory
    $INIT_CMD -no-color 2>&1 | \
        grep -v "^Initializing" | \
        grep -v "^- Finding" | \
        grep -v "^- Installing" | \
        grep -v "^Terraform has been successfully initialized" | \
        grep -v "^You may now begin working" | \
        grep -v "^If you ever set or change" | \
        grep -v "^rerun this command" | \
        grep -v "^Terraform has created a lock file" | \
        grep -v "^selections it made above" | \
        grep -v "^so that Terraform can guarantee" | \
        grep -v "^you run \"terraform init\"" | \
        grep -v "Warning: Incomplete lock file" | \
        grep -v "Due to your customized provider" | \
        grep -v "to calculate lock file" | \
        grep -v "The current .terraform.lock.hcl" | \
        grep -v "so Terraform running on another" | \
        grep -v "To calculate additional checksums" | \
        grep -v "terraform providers lock" | \
        grep -v "(where .* is the platform" || true
    
    # Check if init actually succeeded
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "ERROR: terraform init failed"
        # Re-run to show full error output
        $INIT_CMD -no-color
        exit 1
    fi
fi