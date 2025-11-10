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

# Function to log messages to stderr to avoid corrupting data output
log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "$1" >&2
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
        log "${RED}Failed to fetch data for $provider${NC}"
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

# Determine the correct versions.json path
if [ -f "$WORKSPACE_ROOT/tests/providers/versions.json" ]; then
    # tf2 module context - process tests/providers
    VERSIONS_FILE="$WORKSPACE_ROOT/tests/providers/versions.json"
elif [ -f "$WORKSPACE_ROOT/test_providers/versions.json" ]; then
    # Legacy location - process test_providers
    VERSIONS_FILE="$WORKSPACE_ROOT/test_providers/versions.json"
elif [ -f "$WORKSPACE_ROOT/iac/providers/versions.json" ]; then
    # Root module context
    VERSIONS_FILE="$WORKSPACE_ROOT/iac/providers/versions.json"
else
    echo -e "${RED}Error: Could not find versions.json in any expected location${NC}"
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

echo -e "\n${BLUE}Checking for provider updates...${NC}"
echo "Versions file: $VERSIONS_FILE"
echo

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
            echo -e "${GREEN}✓${NC} $provider: ${YELLOW}$current_version${NC} → ${GREEN}$latest_version${NC}" >&2
            updated_versions+=("\"$latest_version\"")
            any_updated=true
            UPDATES_MADE=true
        else
            echo -e "${BLUE}✓${NC} $provider: $current_version (already latest)" >&2
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
    [ -n "$status_msg" ] && echo -e "  $status_msg" >&2

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

# Apply updates if not in dry-run mode
if [ "$DRY_RUN" = false ]; then
    if [ "$UPDATES_MADE" = true ]; then
        mv "$TMP_FILE" "$VERSIONS_FILE"
        echo -e "${GREEN}✓ versions.json updated successfully${NC}"
        echo "Updated: $VERSIONS_FILE"
        echo ""
        echo -e "${YELLOW}Note: Run 'bazel run //:tf-mod' to regenerate locks and terraform.tf files${NC}"
    else
        rm "$TMP_FILE"
        echo -e "${BLUE}No provider updates needed - all providers are at their latest versions${NC}"
    fi
else
    rm -f "$TMP_FILE"
    echo -e "${YELLOW}Dry run mode - no changes made${NC}"
    echo ""
    echo "Run without --dry-run to apply updates"
fi

echo ""
echo -e "${GREEN}✓ Provider version check complete${NC}"