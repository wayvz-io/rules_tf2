#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --dry-run    Show what would be updated without making changes"
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

<<<<<<< HEAD
# Function to log messages
=======
# Get script directory for later use
if [ -n "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi

# Cache directory for provider locks
CACHE_DIR="${HOME}/.cache/bazel/tf_provider_locks"

# Function to generate lock for a single provider and append to JSON
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
    if timeout 1800 "$TERRAFORM_CMD" init -backend=false >/dev/null 2>&1; then
        if timeout 1800 "$TERRAFORM_CMD" providers lock \
            -platform=linux_amd64 \
            -platform=linux_arm64 \
            -platform=darwin_amd64 \
            -platform=darwin_arm64 \
            -platform=windows_amd64 \
            >/dev/null 2>&1; then

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
                log "    ⚠ No lock file generated for $provider:$version"
                return 1
            fi
        else
            log "    ⚠ Providers lock failed for $provider:$version"
            return 1
        fi
    else
        log "    ⚠ Init failed for $provider:$version"
        return 1
    fi

}

# Legacy function for backward compatibility
generate_single_provider_lock() {
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
    if timeout 300 terraform init -backend=false >/dev/null 2>&1; then
        if timeout 300 terraform providers lock \
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

# Function to generate provider locks JSON file
generate_provider_lock_file() {
    log "${BLUE}Generating provider locks JSON file...${NC}"

    # Parse paths from MODULE.bazel tf_providers.download() call
    local module_bazel="$WORKSPACE_ROOT/MODULE.bazel"
    if [ ! -f "$module_bazel" ]; then
        log "${RED}Error: MODULE.bazel not found at $module_bazel${NC}"
        return 1
    fi

    # Extract versions_file and lock_file from tf_providers.download()
    VERSIONS_FILE=$(grep -A 10 "tf_providers\.download(" "$module_bazel" | grep "versions_file" | sed 's/.*versions_file = "\([^"]*\)".*/\1/')
    LOCKS_FILE=$(grep -A 10 "tf_providers\.download(" "$module_bazel" | grep "lock_file" | sed 's/.*lock_file = "\([^"]*\)".*/\1/')

    if [ -z "$VERSIONS_FILE" ]; then
        log "${RED}Error: Could not find versions_file in MODULE.bazel tf_providers.download()${NC}"
        return 1
    fi

    if [ -z "$LOCKS_FILE" ]; then
        log "${RED}Error: Could not find lock_file in MODULE.bazel tf_providers.download()${NC}"
        return 1
    fi

    # Convert to absolute paths
    VERSIONS_FILE="$WORKSPACE_ROOT/$VERSIONS_FILE"
    LOCKS_FILE="$WORKSPACE_ROOT/$LOCKS_FILE"

    if [ ! -f "$VERSIONS_FILE" ]; then
        log "${RED}Error: versions.json not found at $VERSIONS_FILE${NC}"
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
        log "${YELLOW}No providers found in versions.json${NC}"
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
            # The working directory is something like: /path/to/tf_update.runfiles/_main
            # We want: /path/to/tf_update.runfiles
            # Use a different approach: find the .runfiles part and cut there
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
        log "${RED}Error: Terraform binary not found${NC}"
        log "Tried:"
        log "  - Bazel runfiles: ${RUNFILES_BASE:-<not found>}"
        log "  - System PATH"
        log "  - Common system locations"
        log ""
        log "Provider locks will not be generated - builds will fall back to network downloads"
        return 1
    fi

    log "${BLUE}Using terraform binary: $TERRAFORM_CMD${NC}"

    # Create base temporary directory
    BASE_TEMP_DIR=$(mktemp -d)
    trap "rm -rf $BASE_TEMP_DIR" EXIT

    # Initialize JSON structure
    echo "{" > "$BASE_TEMP_DIR/provider_locks.json"
    local first_entry=true

    # Process each provider version sequentially for reliability
    local success_count=0
    local failure_count=0

    while IFS=':' read -r provider version; do
        [ -z "$provider" ] && continue

        # Create temporary directory for this provider
        local provider_temp_dir="$BASE_TEMP_DIR/provider_$(echo "$provider" | tr '/' '_')_$version"
        mkdir -p "$provider_temp_dir"

        log "Processing $provider:$version"

        # Generate lock for this individual provider
        if generate_single_provider_lock_json "$provider" "$version" "$provider_temp_dir" "$BASE_TEMP_DIR/provider_locks.json" "$first_entry"; then
            success_count=$((success_count + 1))
            first_entry=false
        else
            failure_count=$((failure_count + 1))
        fi
    done <<< "$providers"

    # Close JSON structure
    echo "}" >> "$BASE_TEMP_DIR/provider_locks.json"

    echo ""
    log "Lock generation summary:"
    log "  ✓ Successful: $success_count providers"
    log "  ⚠ Failed: $failure_count providers"

    if [ $success_count -gt 0 ]; then
        # Copy provider locks to final location
        cp "$BASE_TEMP_DIR/provider_locks.json" "$LOCKS_FILE"
        log "${GREEN}✓ Provider locks JSON generated successfully${NC}"
        log "Locks file location: $LOCKS_FILE"
    else
        log "${RED}Error: No providers were successfully processed${NC}"
        return 1
    fi
}

# Function to log messages to stderr to avoid corrupting data output
>>>>>>> d88d2c3 (Updates to warnings, and tflint, so that all tests now pass)
log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "$1"
    fi
}

# Function to get the latest version for a provider matching the major version constraint
get_latest_version() {
    local provider=$1
    local current_version=$2
    local namespace=$(echo "$provider" | cut -d'/' -f1)
    local name=$(echo "$provider" | cut -d'/' -f2)
    local major_version=$(echo "$current_version" | cut -d'.' -f1)

    log "${BLUE}Checking $provider (current: $current_version)...${NC}"

    # Query the Terraform Registry API
    local api_url="https://registry.terraform.io/v1/providers/${namespace}/${name}"
    local response=$(curl -s "$api_url")

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        echo -e "${RED}Failed to fetch data for $provider${NC}" >&2
        echo "$current_version"
        return
    fi

    # Extract all versions from the response
    local versions=$(echo "$response" | sed -n 's/.*"versions":\[\([^]]*\)\].*/\1/p' | tr ',' '\n' | tr -d '"' | tr -d ' ')

    if [ -z "$versions" ]; then
        log "${YELLOW}No versions found for $provider${NC}"
        echo "$current_version"
        return
    fi

    # Filter versions by major version and find the latest
    local latest_version=""
    local latest_minor=-1
    local latest_patch=-1
    local highest_major=-1

    while IFS= read -r version; do
        # Skip empty lines or pre-release versions with non-numeric major versions
        [ -z "$version" ] && continue
        echo "$version" | grep -qE '^[0-9]+\.' || continue

        # Skip pre-release versions (anything with a dash after the version)
        echo "$version" | grep -q '-' && continue

        # Parse version components
        local v_major=$(echo "$version" | cut -d'.' -f1)
        local v_minor=$(echo "$version" | cut -d'.' -f2)
        local v_patch=$(echo "$version" | cut -d'.' -f3)

        # Track the highest major version
        if [ "$v_major" -gt "$highest_major" ] 2>/dev/null; then
            highest_major=$v_major
        fi

        # Skip if not matching major version
        if [ "$v_major" != "$major_version" ]; then
            continue
        fi

        # Compare versions
        if [ "$v_minor" -gt "$latest_minor" ] 2>/dev/null; then
            latest_version="$version"
            latest_minor=$v_minor
            latest_patch=$v_patch
        elif [ "$v_minor" -eq "$latest_minor" ] 2>/dev/null && [ "$v_patch" -gt "$latest_patch" ] 2>/dev/null; then
            latest_version="$version"
            latest_patch=$v_patch
        fi
    done <<< "$versions"

    # Fallback to current version if no suitable version found
    if [ -z "$latest_version" ]; then
        latest_version="$current_version"
    fi

    # Return both the latest version and highest major version
    echo "${latest_version}|${highest_major}"
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

# Determine the correct versions.json path based on context
# Check if we're in the tf2 module context
if [ -f "$WORKSPACE_ROOT/tests/providers/versions.json" ]; then
    # tf2 module context - process tests/providers
    VERSIONS_FILE="$WORKSPACE_ROOT/tests/providers/versions.json"
    LOCK_FILE="$WORKSPACE_ROOT/tests/providers/terraform.lock.hcl"
elif [ -f "$WORKSPACE_ROOT/test_providers/versions.json" ]; then
    # Legacy location - process test_providers
    VERSIONS_FILE="$WORKSPACE_ROOT/test_providers/versions.json"
    LOCK_FILE="$WORKSPACE_ROOT/test_providers/terraform.lock.hcl"
elif [ -f "$WORKSPACE_ROOT/iac/providers/versions.json" ]; then
    # Root module context
    VERSIONS_FILE="$WORKSPACE_ROOT/iac/providers/versions.json"
    LOCK_FILE="$WORKSPACE_ROOT/iac/providers/terraform.lock.hcl"
else
    echo -e "${RED}Error: Could not find versions.json in either iac/providers/, tests/providers/, or test_providers/${NC}"
    echo "Searched in:"
    echo "  - $WORKSPACE_ROOT/iac/providers/versions.json"
    echo "  - $WORKSPACE_ROOT/tests/providers/versions.json"
    echo "  - $WORKSPACE_ROOT/test_providers/versions.json"
    exit 1
fi

if [ ! -f "$VERSIONS_FILE" ]; then
    echo -e "${RED}Error: $VERSIONS_FILE not found${NC}"
    exit 1
fi

echo -e "\n${BLUE}Updating provider versions...${NC}"

# Read current versions from versions.json
UPDATES_MADE=false
TMP_FILE=$(mktemp)

# Start building the new JSON
echo '{' > "$TMP_FILE"
echo '  "providers": {' >> "$TMP_FILE"

# Process each provider in versions.json
first=true
while IFS= read -r line; do
    # Skip lines that don't contain provider definitions
    if ! echo "$line" | grep -qE '"[^"]+/[^"]+": \[.*\]'; then
        continue
    fi

    # Extract provider
    provider=$(echo "$line" | sed -E 's/.*"([^"]+\/[^"]+)".*/\1/')

    # Extract all versions from the array
    versions_raw=$(echo "$line" | sed -E 's/.*\[(.*)\].*/\1/')

    # Parse versions into an array
    updated_versions=()
    any_updated=false
    highest_major=-1

    # Process each version in the array
    while IFS= read -r version_item; do
        # Clean up the version string (remove quotes and spaces)
        current_version=$(echo "$version_item" | tr -d '"' | tr -d ' ')
        [ -z "$current_version" ] && continue

        # Get the latest version for this major version
        result=$(get_latest_version "$provider" "$current_version")
        latest_version=$(echo "$result" | cut -d'|' -f1)
        version_highest=$(echo "$result" | cut -d'|' -f2)
        current_major=$(echo "$current_version" | cut -d'.' -f1)

        # Track highest major version available
        if [ "$version_highest" -gt "$highest_major" ] 2>/dev/null; then
            highest_major=$version_highest
        fi

        # Check if update is needed
        if [ "$latest_version" != "$current_version" ]; then
            echo -e "${GREEN}✓${NC} $provider: ${YELLOW}$current_version${NC} → ${GREEN}$latest_version${NC}"
            updated_versions+=("\"$latest_version\"")
            any_updated=true
            UPDATES_MADE=true
        else
            echo -e "${BLUE}✓${NC} $provider: $current_version (already latest)"
            updated_versions+=("\"$current_version\"")
        fi
    done < <(echo "$versions_raw" | tr ',' '\n')

    # Build status message for major version availability
    # Only show if we don't already have the highest major version
    status_msg=""
    have_highest_major=false
    for version_str in "${updated_versions[@]}"; do
        version_clean=$(echo "$version_str" | tr -d '"')
        version_major=$(echo "$version_clean" | cut -d'.' -f1)
        if [ "$version_major" -eq "$highest_major" ] 2>/dev/null; then
            have_highest_major=true
            break
        fi
    done

    if [ "$have_highest_major" = false ] && [ "$highest_major" -gt 0 ]; then
        # Check if any version is lower than the highest
        for version_str in "${updated_versions[@]}"; do
            version_clean=$(echo "$version_str" | tr -d '"')
            version_major=$(echo "$version_clean" | cut -d'.' -f1)
            if [ "$highest_major" -gt "$version_major" ] 2>/dev/null; then
                status_msg=" ${YELLOW}(major v${highest_major} available)${NC}"
                break
            fi
        done
    fi
    [ -n "$status_msg" ] && echo -e "  $status_msg"

    # Add comma if not first entry
    if [ "$first" = true ]; then
        first=false
    else
        echo ',' >> "$TMP_FILE"
    fi

    # Write the provider with all versions
    versions_string=$(IFS=', '; echo "${updated_versions[*]}")
    echo -n "    \"$provider\": [$versions_string]" >> "$TMP_FILE"

done < <(grep -E '"[^"]+/[^"]+": \[.*\]' "$VERSIONS_FILE")

# Close the JSON
echo '' >> "$TMP_FILE"
echo '  }' >> "$TMP_FILE"
echo '}' >> "$TMP_FILE"

echo ""

# Check if lock file exists
LOCK_FILE_EXISTS=true
if [ ! -f "$LOCK_FILE" ]; then
    LOCK_FILE_EXISTS=false
    echo -e "${YELLOW}Lock file does not exist, will create it${NC}"
fi

# Apply updates if not in dry-run mode
if [ "$DRY_RUN" = false ]; then
    if [ "$UPDATES_MADE" = true ]; then
        mv "$TMP_FILE" "$VERSIONS_FILE"
        echo -e "${GREEN}✓ versions.json updated successfully${NC}"
        echo ""
    else
        rm "$TMP_FILE"
    fi

    # Regenerate the lock file if updates were made or if it doesn't exist
    if [ "$UPDATES_MADE" = true ] || [ "$LOCK_FILE_EXISTS" = false ]; then
        if [ "$UPDATES_MADE" = true ]; then
            echo "Regenerating terraform.lock.hcl..."
        else
            echo "Creating terraform.lock.hcl..."
        fi

        # Create a temporary directory for terraform init
        TEMP_DIR=$(mktemp -d)
        trap "rm -rf $TEMP_DIR" EXIT

        # Create a minimal terraform configuration
        cat > "$TEMP_DIR/main.tf" << 'EOF'
terraform {
  required_version = ">= 1.0"
}
EOF

        # Copy versions.json content to terraform required_providers format
        echo "terraform {" > "$TEMP_DIR/versions.tf"
        echo "  required_providers {" >> "$TEMP_DIR/versions.tf"

        # Parse versions.json and create terraform config
        python3 -c "
import json
with open('$VERSIONS_FILE', 'r') as f:
    data = json.load(f)
    providers = data.get('providers', {})
    for provider, versions in providers.items():
        version = versions[0] if versions else '0.0.0'
        name = provider.split('/')[-1]
        print(f'    {name} = {{')
        print(f'      source  = \"{provider}\"')
        print(f'      version = \"~> {version}\"')
        print(f'    }}')
" >> "$TEMP_DIR/versions.tf"

        echo "  }" >> "$TEMP_DIR/versions.tf"
        echo "}" >> "$TEMP_DIR/versions.tf"

        # Enable terraform provider caching for faster subsequent runs
        export TF_PLUGIN_CACHE_DIR="${HOME}/.terraform.d/plugin-cache"
        mkdir -p "$TF_PLUGIN_CACHE_DIR"
        
        # Run terraform init to generate lock file (using cache)
        cd "$TEMP_DIR"
        echo "Downloading providers (using cache at $TF_PLUGIN_CACHE_DIR)..."
        terraform init -backend=false > /dev/null 2>&1

        # Generate lock file for all platforms
        echo "Generating hashes for all platforms..."
        terraform providers lock \
            -platform=linux_amd64 \
            -platform=linux_arm64 \
            -platform=darwin_amd64 \
            -platform=darwin_arm64 \
            -platform=windows_amd64 \
            > /dev/null 2>&1

        # Copy the generated lock file back
        if [ -f "$TEMP_DIR/.terraform.lock.hcl" ]; then
            cp "$TEMP_DIR/.terraform.lock.hcl" "$LOCK_FILE"
            echo -e "${GREEN}✓ terraform.lock.hcl regenerated successfully${NC}"
        else
            echo -e "${RED}Failed to generate terraform.lock.hcl${NC}"
            exit 1
        fi

        cd "$WORKSPACE_ROOT"

        # Run bazel mod tidy to update MODULE.bazel.lock
        echo ""
        echo "Running bazel mod tidy to update MODULE.bazel.lock..."
        if bazel mod tidy 2>&1 | grep -v "Loading:"; then
            echo -e "${GREEN}✓ MODULE.bazel.lock updated successfully${NC}"
        else
            echo -e "${YELLOW}⚠ Warning: bazel mod tidy may have encountered issues${NC}"
        fi

    fi
    
    # Always call the regenerate_versions script to update terraform.tf files and docs
    # This ensures that any changes to version generation logic are applied
    echo ""
    REGENERATE_SCRIPT="$WORKSPACE_ROOT/scripts/regenerate_versions.sh"
    
    if [ -f "$REGENERATE_SCRIPT" ]; then
        if [ "$VERBOSE" = true ]; then
            "$REGENERATE_SCRIPT" --verbose
        else
            "$REGENERATE_SCRIPT"
        fi
    else
        echo -e "${YELLOW}⚠${NC} regenerate_versions.sh not found at $REGENERATE_SCRIPT"
    fi
    
    if [ "$UPDATES_MADE" = true ] || [ "$LOCK_FILE_EXISTS" = false ]; then

        # Regenerate lock files for stacks using Bazel built-in rules
        echo ""
        echo "Regenerating lock files for stacks..."

        # Query for all lock file update targets
        # These are created by tf_lock_file_validation macros with names ending in _lock_file
        lock_targets=$(bazel query 'attr(name, ".*_lock_file$", //...)' 2>/dev/null)

        if [ -n "$lock_targets" ]; then
            echo "Found $(echo "$lock_targets" | wc -l) lock file targets to update"

            for target in $lock_targets; do
                log "Updating lock file: $target"
                if bazel run "$target" > /dev/null 2>&1; then
                    echo -e "${GREEN}✓${NC} Updated lock file: $target"
                else
                    echo -e "${YELLOW}⚠${NC} Failed to update lock file: $target"
                fi
            done
        else
            echo "No lock file update targets found"
        fi

    elif [ "$LOCK_FILE_EXISTS" = false ]; then
        # No updates but lock file needs to be created
        rm -f "$TMP_FILE"
        echo -e "${BLUE}No provider updates needed - all providers are at their latest versions${NC}"
    else
        rm -f "$TMP_FILE"
        echo -e "${BLUE}No provider updates needed - all providers are at their latest versions${NC}"
    fi
else
    rm -f "$TMP_FILE"
    echo -e "${YELLOW}Dry run mode - no changes made${NC}"
    echo ""
    echo "Run without --dry-run to apply updates"
fi

# Generate provider locks JSON file if updates were made or locks file doesn't exist
# Parse lock_file path from MODULE.bazel
module_bazel="$WORKSPACE_ROOT/MODULE.bazel"
LOCKS_FILE=$(grep -A 10 "tf_providers\.download(" "$module_bazel" | grep "lock_file" | sed 's/.*lock_file = "\([^"]*\)".*/\1/')
if [ -n "$LOCKS_FILE" ]; then
    LOCKS_FILE="$WORKSPACE_ROOT/$LOCKS_FILE"
else
    # Fallback for repos without lock_file specified
    LOCKS_FILE="$WORKSPACE_ROOT/tests/providers/provider_locks.json"
fi

if [ "$UPDATES_MADE" = true ] || [ ! -f "$LOCKS_FILE" ]; then
    echo ""
    echo -e "${BLUE}Generating provider lock file...${NC}"

    # Generate provider lock file directly
    generate_provider_lock_file
fi

echo ""
echo -e "${GREEN}✓ Provider update check complete${NC}"
