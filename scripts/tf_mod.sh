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
FORCE_REGENERATE=false
MAX_PARALLEL_JOBS=${TF_MOD_PARALLEL_JOBS:-4}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --force|-f)
            FORCE_REGENERATE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Generate provider locks, update terraform.tf files, and regenerate documentation"
            echo "Options:"
            echo "  --verbose, -v  Show detailed output"
            echo "  --force, -f    Force regeneration of all provider locks (skip delta detection)"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  TF_MOD_PARALLEL_JOBS  Number of parallel provider lock jobs (default: 4)"
            echo "  TF_PLUGIN_CACHE_DIR   Terraform plugin cache directory"
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

# Function to validate lockfile and return status
# Returns: VALID, MISSING, CORRUPT_JSON, or INVALID_SCHEMA
validate_lockfile() {
    local lockfile="$1"

    # Check if file exists
    if [ ! -f "$lockfile" ]; then
        echo "MISSING"
        return 0
    fi

    # Check if file is empty
    if [ ! -s "$lockfile" ]; then
        echo "CORRUPT_JSON"
        return 0
    fi

    # Validate JSON and schema
    python3 << PYTHON_VALIDATE
import json
import sys

try:
    with open('$lockfile', 'r') as f:
        data = json.load(f)

    # Validate schema: each key should be provider:version, each value should have h1 or zh
    for key, value in data.items():
        if ':' not in key:
            print('INVALID_SCHEMA')
            sys.exit(0)
        if not isinstance(value, dict) or ('h1' not in value and 'zh' not in value):
            print('INVALID_SCHEMA')
            sys.exit(0)

    print('VALID')
except json.JSONDecodeError:
    print('CORRUPT_JSON')
except Exception as e:
    print('CORRUPT_JSON')
PYTHON_VALIDATE
}

# Function to detect which providers need lock regeneration
# Outputs to stdout: provider:version pairs that need processing (one per line)
# Outputs to a file: providers that should be removed from lockfile
detect_provider_delta() {
    local versions_file="$1"
    local locks_file="$2"
    local removed_file="$3"

    python3 << PYTHON_DELTA
import json
import sys
import os

versions_file = '$versions_file'
locks_file = '$locks_file'
removed_file = '$removed_file'

# Load versions.json - get all desired provider:version pairs
with open(versions_file, 'r') as f:
    versions_data = json.load(f)

desired_providers = set()
for provider, versions in versions_data.get('providers', {}).items():
    for version in versions:
        desired_providers.add(f"{provider}:{version}")

# Load existing locks (or empty if file doesn't exist or is invalid)
existing_locks = set()
try:
    if os.path.exists(locks_file):
        with open(locks_file, 'r') as f:
            locks_data = json.load(f)
            existing_locks = set(locks_data.keys())
except (json.JSONDecodeError, IOError):
    pass

# Find providers that need processing (in versions.json but not in locks)
new_providers = desired_providers - existing_locks

# Find providers to remove (in locks but not in versions.json)
removed_providers = existing_locks - desired_providers

# Output new providers to stdout
for provider in sorted(new_providers):
    print(provider)

# Output removed providers to file
with open(removed_file, 'w') as f:
    for provider in sorted(removed_providers):
        f.write(provider + '\n')
PYTHON_DELTA
}

# Function to get existing locks that should be preserved
# Returns JSON entries for providers that are NOT being regenerated and are still in versions.json
get_preserved_locks_json() {
    local locks_file="$1"
    local versions_file="$2"
    local providers_to_update="$3"  # newline-separated provider:version list

    python3 << PYTHON_PRESERVE
import json
import sys
import os

locks_file = '$locks_file'
versions_file = '$versions_file'
providers_to_update = '''$providers_to_update'''

# Parse providers being updated
updating = set()
for line in providers_to_update.strip().split('\n'):
    if line:
        updating.add(line)

# Load existing locks
existing_locks = {}
try:
    if os.path.exists(locks_file):
        with open(locks_file, 'r') as f:
            existing_locks = json.load(f)
except (json.JSONDecodeError, IOError):
    pass

# Load versions.json to know which providers should exist
desired_providers = set()
with open(versions_file, 'r') as f:
    versions_data = json.load(f)
    for provider, versions in versions_data.get('providers', {}).items():
        for version in versions:
            desired_providers.add(f"{provider}:{version}")

# Output preserved locks (not being updated AND still in versions.json)
preserved = {}
for key, value in existing_locks.items():
    if key not in updating and key in desired_providers:
        preserved[key] = value

# Output as JSON (without outer braces for easier merging)
first = True
for key in sorted(preserved.keys()):
    if not first:
        print(',')
    print(f'  "{key}": {json.dumps(preserved[key])}', end='')
    first = False

if preserved:
    print()  # Final newline if we printed anything
PYTHON_PRESERVE
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

    # Enable terraform plugin cache for faster provider downloads
    export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
    mkdir -p "$TF_PLUGIN_CACHE_DIR"
    log "Using terraform plugin cache: $TF_PLUGIN_CACHE_DIR"

    # Create base temporary directory
    BASE_TEMP_DIR=$(mktemp -d)
    trap "rm -rf $BASE_TEMP_DIR" EXIT

    # Validate existing lockfile
    local lockfile_status
    lockfile_status=$(validate_lockfile "$LOCKS_FILE")
    log "Lockfile status: $lockfile_status"

    local providers_to_process=""
    local removed_file="$BASE_TEMP_DIR/removed_providers.txt"
    touch "$removed_file"
    local total_provider_count=$(echo "$providers" | wc -l)

    # Determine which providers need processing
    if [ "$FORCE_REGENERATE" = true ]; then
        echo -e "${YELLOW}Force mode: regenerating all $total_provider_count provider locks${NC}"
        providers_to_process="$providers"
    elif [ "$lockfile_status" = "VALID" ]; then
        # Delta detection: only process changed providers
        providers_to_process=$(detect_provider_delta "$VERSIONS_FILE" "$LOCKS_FILE" "$removed_file")
    else
        # Invalid/missing lockfile: regenerate all
        case "$lockfile_status" in
            "MISSING")
                echo "No existing lockfile found - generating all locks"
                ;;
            "CORRUPT_JSON"|"INVALID_SCHEMA")
                echo -e "${YELLOW}Warning: Existing lockfile is corrupt or invalid - regenerating all locks${NC}"
                ;;
        esac
        providers_to_process="$providers"
    fi

    # Check if removed providers exist
    local removed_providers=""
    if [ -s "$removed_file" ]; then
        removed_providers=$(cat "$removed_file")
        local removed_count=$(echo "$removed_providers" | wc -l)
        echo "Removing $removed_count obsolete provider locks"
    fi

    # Check if there's anything to do
    if [ -z "$providers_to_process" ] && [ -z "$removed_providers" ]; then
        echo -e "${GREEN}✓ All provider locks are up to date - nothing to do${NC}"
        return 0
    fi

    local update_count=0
    if [ -n "$providers_to_process" ]; then
        update_count=$(echo "$providers_to_process" | wc -l)
    fi

    if [ "$update_count" -gt 0 ]; then
        if [ "$FORCE_REGENERATE" != true ] && [ "$lockfile_status" = "VALID" ]; then
            echo "Delta detected: $update_count of $total_provider_count providers need lock updates"
        fi
    fi

    # Create results directory for parallel processing
    local results_dir="$BASE_TEMP_DIR/results"
    mkdir -p "$results_dir"

    # Process providers in parallel
    local success_count=0
    local failure_count=0
    local failed_providers=()
    local current_count=0
    local job_pids=()

    if [ "$update_count" -gt 0 ]; then
        echo ""
        echo "Processing $update_count providers (max $MAX_PARALLEL_JOBS parallel jobs):"

        while IFS=':' read -r provider version; do
            [ -z "$provider" ] && continue

            current_count=$((current_count + 1))
            local safe_name=$(echo "${provider}_${version}" | tr '/' '_')
            local provider_temp_dir="$BASE_TEMP_DIR/work_$safe_name"
            local result_file="$results_dir/${safe_name}.json"
            local status_file="$results_dir/${safe_name}.status"
            mkdir -p "$provider_temp_dir"

            echo "  $current_count/$update_count | Starting $provider:$version"

            # Run in background with exported environment variables
            (
                export PROVIDER="$provider"
                export VERSION="$version"
                export TERRAFORM_CMD="$TERRAFORM_CMD"
                export TF_PLUGIN_CACHE_DIR="$TF_PLUGIN_CACHE_DIR"

                if generate_single_provider_lock_json "$provider" "$version" "$provider_temp_dir" "/dev/null" "true"; then
                    # Extract hashes to result file
                    if [ -f "$provider_temp_dir/.terraform.lock.hcl" ]; then
                        cd "$provider_temp_dir"
                        python3 - << 'PYTHON_EXTRACT' > "$result_file"
import re
import json
import sys
import os

provider = os.environ.get('PROVIDER', '')
version = os.environ.get('VERSION', '')

with open('.terraform.lock.hcl', 'r') as f:
    content = f.read()

hashes_match = re.search(r'hashes\s*=\s*\[(.*?)\]', content, re.DOTALL)
if hashes_match:
    hashes_text = hashes_match.group(1)
    hash_lines = re.findall(r'"([^"]+)"', hashes_text)
    h1_hashes = [h[3:] for h in hash_lines if h.startswith('h1:')]
    zh_hashes = [h[3:] for h in hash_lines if h.startswith('zh:')]
    result = {}
    if h1_hashes:
        result['h1'] = h1_hashes
    if zh_hashes:
        result['zh'] = zh_hashes
    provider_key = f"{provider}:{version}"
    print(json.dumps({provider_key: result}))
else:
    print('{}')
PYTHON_EXTRACT
                        echo "SUCCESS" > "$status_file"
                    else
                        echo "NO_LOCKFILE" > "$status_file"
                    fi
                else
                    echo "FAILED" > "$status_file"
                fi
            ) &

            job_pids+=($!)

            # Limit concurrent jobs
            if [ ${#job_pids[@]} -ge $MAX_PARALLEL_JOBS ]; then
                # Wait for oldest job to complete
                wait "${job_pids[0]}" 2>/dev/null || true
                job_pids=("${job_pids[@]:1}")
            fi
        done <<< "$providers_to_process"

        # Wait for all remaining jobs
        for pid in "${job_pids[@]}"; do
            wait "$pid" 2>/dev/null || true
        done

        echo ""
    fi

    # Collect results and build final JSON
    echo "Merging provider locks..."

    # Start building the new lockfile
    echo "{" > "$BASE_TEMP_DIR/provider_locks.json.tmp"
    local first_entry=true

    # First, add preserved locks (existing locks not being regenerated)
    if [ "$FORCE_REGENERATE" != true ] && [ "$lockfile_status" = "VALID" ]; then
        local preserved_json
        preserved_json=$(get_preserved_locks_json "$LOCKS_FILE" "$VERSIONS_FILE" "$providers_to_process")
        if [ -n "$preserved_json" ]; then
            echo "$preserved_json" >> "$BASE_TEMP_DIR/provider_locks.json.tmp"
            first_entry=false
        fi
    fi

    # Add newly generated locks
    shopt -s nullglob
    for status_file in "$results_dir"/*.status; do
        [ -f "$status_file" ] || continue

        local base_name=$(basename "$status_file" .status)
        local json_file="$results_dir/${base_name}.json"
        local status=$(cat "$status_file")

        if [ "$status" = "SUCCESS" ] && [ -f "$json_file" ]; then
            local content=$(cat "$json_file")

            # Skip empty results
            if [ "$content" = "{}" ]; then
                failure_count=$((failure_count + 1))
                failed_providers+=("$base_name (empty result)")
                continue
            fi

            # Extract inner content and add to output
            local inner_content=$(echo "$content" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
for key, value in data.items():
    print(f'  \"{key}\": {json.dumps(value)}')
")

            if [ -n "$inner_content" ]; then
                if [ "$first_entry" = false ]; then
                    echo "," >> "$BASE_TEMP_DIR/provider_locks.json.tmp"
                fi
                echo "$inner_content" >> "$BASE_TEMP_DIR/provider_locks.json.tmp"
                first_entry=false
                success_count=$((success_count + 1))
            fi
        else
            failure_count=$((failure_count + 1))
            failed_providers+=("$base_name ($status)")
        fi
    done

    # Close JSON structure
    echo "" >> "$BASE_TEMP_DIR/provider_locks.json.tmp"
    echo "}" >> "$BASE_TEMP_DIR/provider_locks.json.tmp"

    # Validate the generated JSON before writing
    if ! python3 -c "import json; json.load(open('$BASE_TEMP_DIR/provider_locks.json.tmp'))" 2>/dev/null; then
        log_error "${RED}Error: Generated lockfile is invalid JSON${NC}"
        return 1
    fi

    echo ""
    echo "Lock generation summary:"
    if [ "$update_count" -gt 0 ]; then
        echo "  ✓ Newly generated: $success_count providers"
        echo "  ⚠ Failed: $failure_count providers"
    fi
    if [ -n "$removed_providers" ]; then
        echo "  ✓ Removed: $(echo "$removed_providers" | wc -l) obsolete providers"
    fi
    if [ "$FORCE_REGENERATE" != true ] && [ "$lockfile_status" = "VALID" ]; then
        local preserved_count=$((total_provider_count - update_count))
        if [ "$preserved_count" -gt 0 ]; then
            echo "  ✓ Preserved: $preserved_count existing providers"
        fi
    fi

    if [ $failure_count -gt 0 ]; then
        echo ""
        echo "Failed providers:"
        for failed in "${failed_providers[@]}"; do
            echo "  - $failed"
        done
    fi

    # Atomic write: move temp file to final location
    mv "$BASE_TEMP_DIR/provider_locks.json.tmp" "$LOCKS_FILE"
    echo -e "${GREEN}✓ Provider locks JSON updated successfully${NC}"
    echo "Locks file location: $LOCKS_FILE"
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