#!/usr/bin/env bash

# Generate Terraform provider lock file with actual hashes
# This script reads providers from versions.json and generates terraform.lock.hcl

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSIONS_FILE="$WORKSPACE_ROOT/tests/providers/versions.json"
LOCK_FILE="$WORKSPACE_ROOT/tests/providers/terraform.lock.hcl"

# Terraform binary location
TERRAFORM_BIN=""

# Function to log messages
log() {
    echo -e "$1" >&2
}

# Function to find terraform binary
find_terraform_binary() {
    # Try to find terraform binary from Bazel
    if [[ "$0" == *"bazel-out"* ]]; then
        # Running from bazel, look for terraform in runfiles
        RUNFILES_DIR="$(dirname "$0")/generate_provider_locks.runfiles"
        if [ -d "$RUNFILES_DIR" ]; then
            # Try different possible paths for terraform binary
            POSSIBLE_PATHS=(
                "$RUNFILES_DIR/rules_tf2~~tf_tools~terraform_tool/terraform"
                "$RUNFILES_DIR/_main~tf_tools~terraform_tool/terraform"
                "$RUNFILES_DIR/tf_tools~terraform_tool/terraform"
            )
            for path in "${POSSIBLE_PATHS[@]}"; do
                if [ -f "$path" ]; then
                    TERRAFORM_BIN="$path"
                    break
                fi
            done
        fi
    fi

    # Fall back to system terraform
    if [ ! -f "$TERRAFORM_BIN" ]; then
        TERRAFORM_BIN=$(which terraform 2>/dev/null || echo "")
    fi

    if [ ! -f "$TERRAFORM_BIN" ]; then
        log "${RED}Error: Terraform binary not found${NC}"
        log "Please ensure terraform is installed or run from bazel context"
        exit 1
    fi

    log "${BLUE}Using terraform binary: $TERRAFORM_BIN${NC}"
}

# Function to generate lock for a single provider
generate_provider_lock() {
    local provider=$1
    local version=$2
    local temp_dir=$3

    log "${BLUE}Generating lock for $provider:$version${NC}"

    # Create terraform configuration for this specific provider
    cat > "$temp_dir/main.tf" << 'EOF'
terraform {
  required_version = ">= 1.0"
}
EOF

    # Create versions.tf with just this provider
    cat > "$temp_dir/versions.tf" << EOF
terraform {
  required_providers {
    $(echo "$provider" | cut -d'/' -f2) = {
      source  = "$provider"
      version = "= $version"
    }
  }
}
EOF

    # Run terraform init and providers lock
    cd "$temp_dir"
    if timeout 300 "$TERRAFORM_BIN" init -backend=false >/dev/null 2>&1; then
        if timeout 300 "$TERRAFORM_BIN" providers lock \
            -platform=linux_amd64 \
            -platform=linux_arm64 \
            -platform=darwin_amd64 \
            -platform=darwin_arm64 \
            -platform=windows_amd64 \
            >/dev/null 2>&1; then
            # Return the provider block from the generated lock file
            if [ -f ".terraform.lock.hcl" ]; then
                echo "SUCCESS:$provider:$version"
                cat ".terraform.lock.hcl"
                return 0
            else
                echo "FAILED:$provider:$version:No lock file generated"
                return 1
            fi
        else
            echo "FAILED:$provider:$version:Providers lock failed"
            return 1
        fi
    else
        echo "FAILED:$provider:$version:Init failed"
        return 1
    fi
}

# Main function to generate consolidated lock file
generate_consolidated_lock_file() {
    log "${BLUE}Generating consolidated lock file...${NC}"

    # Check if versions file exists
    if [ ! -f "$VERSIONS_FILE" ]; then
        log "${RED}Error: versions.json not found at $VERSIONS_FILE${NC}"
        exit 1
    fi

    # Parse providers from versions.json
    local providers
    providers=$(python3 -c "
import json
import sys
with open('$VERSIONS_FILE', 'r') as f:
    data = json.load(f)
    providers = data.get('providers', {})
    for provider, versions in providers.items():
        for version in versions:
            print(f'{provider}:{version}')
")

    if [ -z "$providers" ]; then
        log "${YELLOW}No providers found in versions.json${NC}"
        exit 0
    fi

    log "Found $(echo "$providers" | wc -l) provider versions to process"

    # Create base temporary directory
    BASE_TEMP_DIR=$(mktemp -d)
    trap "rm -rf $BASE_TEMP_DIR" EXIT

    # Create consolidated lock file
    CONSOLIDATED_LOCK="$BASE_TEMP_DIR/terraform.lock.hcl"

    # Write lock file header
    cat > "$CONSOLIDATED_LOCK" << 'EOF'
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

EOF

    # Process each provider version
    local job_count=0
    local max_jobs=10  # Limit parallel jobs

    echo "$providers" | while IFS=':' read -r provider version; do
        [ -z "$provider" ] && continue

        # Create temporary directory for this provider
        local provider_temp_dir="$BASE_TEMP_DIR/provider_$(echo "$provider" | tr '/' '_')_$version"
        mkdir -p "$provider_temp_dir"

        # Generate lock for this provider (run in background for parallel processing)
        (
            result=$(generate_provider_lock "$provider" "$version" "$provider_temp_dir")
            echo "$result" > "$BASE_TEMP_DIR/result_${job_count}_$(echo "$provider" | tr '/' '_')_$version"
        ) &

        job_count=$((job_count + 1))

        # Limit parallel jobs
        if [ $job_count -ge $max_jobs ]; then
            wait  # Wait for current batch to complete
            job_count=0
        fi

        log "Started job for $provider:$version"
    done

    # Wait for all remaining jobs to complete
    wait

    log "All provider lock generation jobs completed. Consolidating results..."

    # Collect and process all results
    local success_count=0
    local failure_count=0

    for result_file in "$BASE_TEMP_DIR"/result_*; do
        if [ -f "$result_file" ]; then
            first_line=$(head -n1 "$result_file")
            if [[ "$first_line" == SUCCESS:* ]]; then
                # Extract provider info and append lock content (skip the first line)
                provider_version=$(echo "$first_line" | cut -d':' -f2-3)
                log "✓ Successfully generated lock for $provider_version"

                # Append the lock file content (skip header and first line)
                tail -n +2 "$result_file" | sed '/^# This file is maintained automatically/d' | sed '/^# Manual edits may be lost/d' | sed '/^$/d' >> "$CONSOLIDATED_LOCK"
                echo "" >> "$CONSOLIDATED_LOCK"

                success_count=$((success_count + 1))
            else
                # This is a failure case
                failure_info=$(echo "$first_line" | cut -d':' -f2-)
                log "⚠ Failed to generate lock for $failure_info"
                failure_count=$((failure_count + 1))
            fi
        fi
    done

    echo ""
    log "Lock generation summary:"
    log "  ✓ Successful: $success_count providers"
    log "  ⚠ Failed: $failure_count providers"

    if [ $success_count -gt 0 ]; then
        # Copy consolidated lock file to final location
        cp "$CONSOLIDATED_LOCK" "$LOCK_FILE"
        log "${GREEN}✓ Consolidated terraform.lock.hcl generated successfully${NC}"
        log "Lock file location: $LOCK_FILE"
    else
        log "${RED}Error: No providers were successfully processed${NC}"
        exit 1
    fi
}

# Main execution
main() {
    log "${BLUE}Terraform Provider Lock File Generator${NC}"
    log "Workspace: $WORKSPACE_ROOT"

    find_terraform_binary
    generate_consolidated_lock_file

    log "${GREEN}✓ Lock file generation complete${NC}"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi