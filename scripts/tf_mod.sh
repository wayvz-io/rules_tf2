#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect if we're running in rules_tf2 workspace or external workspace
detect_target_prefix() {
    local workspace_root="${BUILD_WORKSPACE_DIRECTORY:-$(pwd)}"

    # Find the workspace root if not set
    if [ ! -f "$workspace_root/MODULE.bazel" ]; then
        while [ "$workspace_root" != "/" ]; do
            if [ -f "$workspace_root/MODULE.bazel" ]; then
                break
            fi
            workspace_root="$(dirname "$workspace_root")"
        done
    fi

    # Check if we're in the rules_tf2 workspace by looking for marker
    if [ -f "$workspace_root/MODULE.bazel" ] && grep -q 'module(name = "rules_tf2"' "$workspace_root/MODULE.bazel" 2>/dev/null; then
        echo "//"
    else
        echo "@rules_tf2//"
    fi
}

TARGET_PREFIX=$(detect_target_prefix)

# Default values
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Generate provider locks, update terraform.tf files, and regenerate documentation"
            echo "Options:"
            echo "  --verbose    Show detailed output"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to log messages to stderr to avoid corrupting data output
log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "$1" >&2
    fi
}

# Function to log error messages (always shown)
log_error() {
    echo -e "$1" >&2
}


# Function to generate lock for a single provider and return JSON
generate_single_provider_lock_json() {
    local provider=$1
    local version=$2
    local temp_dir=$3
    local json_file=$4
    local is_first_entry=$5

    log "  Generating lock for $provider:$version"

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
    local init_output
    local lock_output

    # Capture output for error reporting
    if init_output=$(timeout 1800 "$TERRAFORM_CMD" init -backend=false 2>&1); then
        if lock_output=$(timeout 1800 "$TERRAFORM_CMD" providers lock \
            -platform=linux_amd64 \
            -platform=linux_arm64 \
            -platform=darwin_amd64 \
            -platform=darwin_arm64 \
            -platform=windows_amd64 \
            2>&1); then

            # Extract hashes from the generated lock file
            if [ -f ".terraform.lock.hcl" ]; then
                # Parse the lock file to extract hashes
                local hashes_json
                hashes_json=$(python3 - << 'PYTHON_EOF'
import re
import json
import sys

# Read the terraform lock file
with open('.terraform.lock.hcl', 'r') as f:
    content = f.read()

# Extract hashes using regex
hashes_match = re.search(r'hashes\s*=\s*\[(.*?)\]', content, re.DOTALL)
if hashes_match:
    hashes_text = hashes_match.group(1)
    # Extract individual hash strings
    hash_lines = re.findall(r'"([^"]+)"', hashes_text)

    # Separate h1 and zh hashes
    h1_hashes = [h[3:] for h in hash_lines if h.startswith('h1:')]
    zh_hashes = [h[3:] for h in hash_lines if h.startswith('zh:')]

    # Create JSON structure
    result = {}
    if h1_hashes:
        result['h1'] = h1_hashes
    if zh_hashes:
        result['zh'] = zh_hashes

    print(json.dumps(result))
else:
    print('{}')
PYTHON_EOF
)

                # Add JSON entry to the locks file
                if [ "$is_first_entry" = "false" ]; then
                    echo "," >> "$json_file"
                fi

                local provider_key="${provider}:${version}"
                echo "  \"$provider_key\": $hashes_json" >> "$json_file"

                log "    ✓ Successfully extracted hashes for $provider:$version"
                return 0
            else
                log_error "    ⚠ No lock file generated for $provider:$version"
                return 1
            fi
        else
            log_error "    ⚠ Providers lock failed for $provider:$version"
            log_error "    Error: $lock_output"
            return 1
        fi
    else
        log_error "    ⚠ Init failed for $provider:$version"
        log_error "    Error: $init_output"
        return 1
    fi
}

# Function to generate provider locks JSON file
generate_provider_lock_file() {
    log "${BLUE}Generating provider locks JSON file...${NC}"

    # Parse paths from MODULE.bazel tf_providers.download() call
    local module_bazel="$WORKSPACE_ROOT/MODULE.bazel"
    if [ ! -f "$module_bazel" ]; then
        log_error "${RED}Error: MODULE.bazel not found at $module_bazel${NC}"
        return 1
    fi

    # Extract versions_file and lock_file from tf_providers.download()
    VERSIONS_FILE=$(grep -A 10 "tf_providers\.download(" "$module_bazel" | grep "versions_file" | sed 's/.*versions_file = "\([^"]*\)".*/\1/')
    LOCKS_FILE=$(grep -A 10 "tf_providers\.download(" "$module_bazel" | grep "lock_file" | sed 's/.*lock_file = "\([^"]*\)".*/\1/')

    if [ -z "$VERSIONS_FILE" ]; then
        log_error "${RED}Error: Could not find versions_file in MODULE.bazel tf_providers.download()${NC}"
        return 1
    fi

    if [ -z "$LOCKS_FILE" ]; then
        log_error "${RED}Error: Could not find lock_file in MODULE.bazel tf_providers.download()${NC}"
        return 1
    fi

    # Convert to absolute paths
    VERSIONS_FILE="$WORKSPACE_ROOT/$VERSIONS_FILE"
    LOCKS_FILE="$WORKSPACE_ROOT/$LOCKS_FILE"

    if [ ! -f "$VERSIONS_FILE" ]; then
        log_error "${RED}Error: versions.json not found at $VERSIONS_FILE${NC}"
        return 1
    fi


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
        log_error "${YELLOW}No providers found in versions.json${NC}"
        return 0
    fi

    log "Found $(echo "$providers" | wc -l) provider versions to process"

    # Find terraform binary - try Bazel runfiles first, then system paths
    TERRAFORM_CMD=""

    # Try to locate runfiles directory
    RUNFILES_BASE=""

    # Debug info
    if [ "$VERBOSE" = "true" ]; then
        log "Debug: Script path: $0"
        log "Debug: Script directory: $(dirname "$0")"
        log "Debug: Working directory: $(pwd)"
        log "Debug: RUNFILES_DIR: ${RUNFILES_DIR:-<not set>}"
    fi

    # Method 1: Use RUNFILES_DIR if set
    if [ -n "${RUNFILES_DIR:-}" ] && [ -d "${RUNFILES_DIR:-}" ]; then
        RUNFILES_BASE="$RUNFILES_DIR"
        [ "$VERBOSE" = "true" ] && log "Debug: Using RUNFILES_DIR: $RUNFILES_BASE"
    else
        # Method 2: Look for .runfiles directory relative to script or current working directory
        SCRIPT_DIR="$(dirname "$0")"
        PWD_DIR="$(pwd)"

        # Check if we're already in a runfiles directory
        if [[ "$PWD_DIR" == *".runfiles"* ]]; then
            # Extract the runfiles base from the current working directory
            RUNFILES_BASE="${PWD_DIR%/.runfiles/*}.runfiles"
            # If that didn't work, try a more direct approach
            if [[ ! -d "$RUNFILES_BASE" ]]; then
                # Find the .runfiles directory by going up from current directory
                current="$PWD_DIR"
                while [[ "$current" == *".runfiles"* ]] && [[ "$current" != "/" ]]; do
                    if [[ "$current" == *".runfiles" ]]; then
                        RUNFILES_BASE="$current"
                        break
                    fi
                    current="$(dirname "$current")"
                done
            fi
            [ "$VERBOSE" = "true" ] && log "Debug: Detected runfiles from PWD: $RUNFILES_BASE"
        else
            # Look for .runfiles directory relative to script
            for candidate in "$SCRIPT_DIR.runfiles" "$(dirname "$SCRIPT_DIR")/.runfiles" ".runfiles"; do
                [ "$VERBOSE" = "true" ] && log "Debug: Checking candidate: $candidate"
                if [ -d "$candidate" ]; then
                    RUNFILES_BASE="$candidate"
                    [ "$VERBOSE" = "true" ] && log "Debug: Found runfiles at: $RUNFILES_BASE"
                    break
                fi
            done
        fi
    fi

    # If we found runfiles, try to locate terraform
    if [ -n "$RUNFILES_BASE" ]; then
        # Try different possible runfiles paths for terraform
        POSSIBLE_PATHS=(
            "$RUNFILES_BASE/_main~tf_tools~terraform_tool/terraform"
            "$RUNFILES_BASE/rules_tf2~~tf_tools~terraform_tool/terraform"
            "$RUNFILES_BASE/tf_tools~terraform_tool/terraform"
        )

        for path in "${POSSIBLE_PATHS[@]}"; do
            if [ -f "$path" ]; then
                TERRAFORM_CMD="$path"
                break
            fi
        done
    fi

    # Fall back to system terraform if not found in runfiles
    if [ -z "$TERRAFORM_CMD" ]; then
        if command -v terraform >/dev/null 2>&1; then
            TERRAFORM_CMD="terraform"
        else
            # Try common system locations
            for path in /usr/local/bin/terraform /opt/homebrew/bin/terraform ~/.local/bin/terraform; do
                if [ -f "$path" ]; then
                    TERRAFORM_CMD="$path"
                    break
                fi
            done
        fi
    fi

    if [ -z "$TERRAFORM_CMD" ] || ! command -v "$TERRAFORM_CMD" >/dev/null 2>&1; then
        log_error "${RED}Error: Terraform binary not found${NC}"
        log_error "Tried:"
        log_error "  - Bazel runfiles: ${RUNFILES_BASE:-<not found>}"
        log_error "  - System PATH"
        log_error "  - Common system locations"
        log_error ""
        log_error "Provider locks will not be generated - builds will fall back to network downloads"
        return 1
    fi


    # Create base temporary directory
    BASE_TEMP_DIR=$(mktemp -d)
    trap "rm -rf $BASE_TEMP_DIR" EXIT

    # Initialize JSON structure
    echo "{" > "$BASE_TEMP_DIR/provider_locks.json"
    local first_entry=true

    # Process each provider version sequentially for reliability
    local success_count=0
    local failure_count=0
    local failed_providers=()
    local current_count=0
    local total_count=$(echo "$providers" | wc -l)

    echo "Processing:"

    while IFS=':' read -r provider version; do
        [ -z "$provider" ] && continue

        current_count=$((current_count + 1))

        # Create temporary directory for this provider
        local provider_temp_dir="$BASE_TEMP_DIR/provider_$(echo "$provider" | tr '/' '_')_$version"
        mkdir -p "$provider_temp_dir"

        echo "  $current_count/$total_count | $provider:$version"

        # Generate lock for this individual provider
        if generate_single_provider_lock_json "$provider" "$version" "$provider_temp_dir" "$BASE_TEMP_DIR/provider_locks.json" "$first_entry"; then
            success_count=$((success_count + 1))
            first_entry=false
        else
            failure_count=$((failure_count + 1))
            failed_providers+=("$provider:$version")
        fi
    done <<< "$providers"

    # Close JSON structure
    echo "}" >> "$BASE_TEMP_DIR/provider_locks.json"

    echo ""
    echo "Lock generation summary:"
    echo "  ✓ Successful: $success_count providers"
    echo "  ⚠ Failed: $failure_count providers"

    if [ $failure_count -gt 0 ]; then
        echo ""
        echo "Failed providers:"
        for failed in "${failed_providers[@]}"; do
            echo "  - $failed"
        done
    fi

    if [ $success_count -gt 0 ]; then
        # Copy provider locks to final location
        cp "$BASE_TEMP_DIR/provider_locks.json" "$LOCKS_FILE"
        echo -e "${GREEN}✓ Provider locks JSON generated successfully${NC}"
        echo "Locks file location: $LOCKS_FILE"
    else
        log_error "${RED}Error: No providers were successfully processed${NC}"
        return 1
    fi
}

# Find workspace root
WORKSPACE_ROOT="${BUILD_WORKSPACE_DIRECTORY:-}"
if [ -z "$WORKSPACE_ROOT" ]; then
    WORKSPACE_ROOT="$(pwd)"
    while [ "$WORKSPACE_ROOT" != "/" ]; do
        if [ -f "$WORKSPACE_ROOT/MODULE.bazel" ]; then
            break
        fi
        WORKSPACE_ROOT="$(dirname "$WORKSPACE_ROOT")"
    done
fi

echo -e "${BLUE}Updating provider locks and terraform.tf files...${NC}"

# Generate provider lock file
if generate_provider_lock_file; then
    echo ""
    echo "Running bazel mod tidy to update MODULE.bazel.lock..."
    cd "$WORKSPACE_ROOT"

    TIDY_OUTPUT=$(bazel mod tidy 2>&1)
    TIDY_EXIT_CODE=$?
    if [ $TIDY_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓ MODULE.bazel.lock updated successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: bazel mod tidy encountered issues${NC}"
        echo "Error output:"
        echo "$TIDY_OUTPUT" | grep -v "Loading:" | sed 's/^/  /'
    fi

    # Regenerate terraform.tf files and documentation using Starlark rule
    echo ""
    echo "Regenerating terraform.tf files and documentation..."

    REGEN_OUTPUT=$(bazel run ${TARGET_PREFIX}:tf-regenerate-all-starlark 2>&1)
    REGEN_EXIT_CODE=$?
    if [ $REGEN_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓ Version and documentation regeneration complete${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Some regeneration targets failed${NC}"
        echo "Error details:"
        echo "$REGEN_OUTPUT" | tail -20 | sed 's/^/  /'
        echo "  This is often due to missing tools but doesn't affect provider locks"
    fi

    echo ""
    echo -e "${GREEN}✓ Provider locks and terraform.tf files updated successfully${NC}"
else
    echo -e "${RED}✗ Failed to generate provider locks${NC}"
    exit 1
fi