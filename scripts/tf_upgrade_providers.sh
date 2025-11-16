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
DRY_RUN=false
VERBOSE=false
UPDATE_PROVIDERS=true
UPDATE_TOOLS=true

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
        --tools-only)
            UPDATE_PROVIDERS=false
            UPDATE_TOOLS=true
            shift
            ;;
        --skip-tools)
            UPDATE_PROVIDERS=true
            UPDATE_TOOLS=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --dry-run      Show what would be updated without making changes"
            echo "  --verbose      Show detailed output"
            echo "  --tools-only   Update only tools and TFLint plugins (skip providers)"
            echo "  --skip-tools   Update only providers (skip tools and TFLint plugins)"
            echo "  --help         Show this help message"
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

# Function to get the latest release from GitHub
get_latest_github_release() {
    local owner=$1
    local repo=$2

    log "${BLUE}Checking GitHub ${owner}/${repo}...${NC}"

    local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
    local response=$(curl -s -L "$api_url")

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log "${RED}Failed to fetch GitHub release for ${owner}/${repo}${NC}"
        echo ""
        return 1
    fi

    # Extract tag_name and remove 'v' prefix
    local version=$(echo "$response" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/"tag_name": *"\(.*\)"/\1/' | sed 's/^v//')

    if [ -z "$version" ]; then
        log "${YELLOW}Could not parse version from GitHub response${NC}"
        echo ""
        return 1
    fi

    echo "$version"
}

# Function to get the latest Terraform version from HashiCorp releases
get_latest_hashicorp_release() {
    log "${BLUE}Checking HashiCorp releases for terraform...${NC}"

    local api_url="https://releases.hashicorp.com/terraform/index.json"
    local response=$(curl -s "$api_url")

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log "${RED}Failed to fetch HashiCorp releases${NC}"
        echo ""
        return 1
    fi

    # Extract versions, filter out pre-releases, and get the latest
    local latest_version=$(echo "$response" | grep -o '"version":"[^"]*"' | sed 's/"version":"\(.*\)"/\1/' | grep -v '-' | sort -V | tail -1)

    if [ -z "$latest_version" ]; then
        log "${YELLOW}Could not parse version from HashiCorp response${NC}"
        echo ""
        return 1
    fi

    echo "$latest_version"
}

# Function to update tools section in versions.json
update_tools() {
    local versions_file=$1
    local tmp_file=$2
    local updates_made=false

    echo -e "\n${BLUE}Checking for tool updates...${NC}" >&2

    # Read current tool versions from versions.json
    local current_terraform=$(grep -o '"terraform": *"[^"]*"' "$versions_file" | sed 's/"terraform": *"\(.*\)"/\1/' || echo "")
    local current_tflint=$(grep -o '"tflint": *"[^"]*"' "$versions_file" | sed 's/"tflint": *"\(.*\)"/\1/' || echo "")
    local current_tfdocs=$(grep -o '"terraform-docs": *"[^"]*"' "$versions_file" | sed 's/"terraform-docs": *"\(.*\)"/\1/' || echo "")

    # Get latest versions
    local latest_terraform=$(get_latest_hashicorp_release)
    local latest_tflint=$(get_latest_github_release "terraform-linters" "tflint")
    local latest_tfdocs=$(get_latest_github_release "terraform-docs" "terraform-docs")

    # Build tools section
    echo '  "tools": {' >> "$tmp_file"

    # Terraform
    if [ -n "$latest_terraform" ] && [ "$latest_terraform" != "$current_terraform" ]; then
        echo -e "${GREEN}✓${NC} terraform: ${YELLOW}$current_terraform${NC} → ${GREEN}$latest_terraform${NC}" >&2
        echo "    \"terraform\": \"$latest_terraform\"," >> "$tmp_file"
        updates_made=true
    else
        echo -e "${BLUE}✓${NC} terraform: ${current_terraform:-$latest_terraform} (already latest)" >&2
        echo "    \"terraform\": \"${current_terraform:-$latest_terraform}\"," >> "$tmp_file"
    fi

    # TFLint
    if [ -n "$latest_tflint" ] && [ "$latest_tflint" != "$current_tflint" ]; then
        echo -e "${GREEN}✓${NC} tflint: ${YELLOW}$current_tflint${NC} → ${GREEN}$latest_tflint${NC}" >&2
        echo "    \"tflint\": \"$latest_tflint\"," >> "$tmp_file"
        updates_made=true
    else
        echo -e "${BLUE}✓${NC} tflint: ${current_tflint:-$latest_tflint} (already latest)" >&2
        echo "    \"tflint\": \"${current_tflint:-$latest_tflint}\"," >> "$tmp_file"
    fi

    # terraform-docs
    if [ -n "$latest_tfdocs" ] && [ "$latest_tfdocs" != "$current_tfdocs" ]; then
        echo -e "${GREEN}✓${NC} terraform-docs: ${YELLOW}$current_tfdocs${NC} → ${GREEN}$latest_tfdocs${NC}" >&2
        echo "    \"terraform-docs\": \"$latest_tfdocs\"" >> "$tmp_file"
        updates_made=true
    else
        echo -e "${BLUE}✓${NC} terraform-docs: ${current_tfdocs:-$latest_tfdocs} (already latest)" >&2
        echo "    \"terraform-docs\": \"${current_tfdocs:-$latest_tfdocs}\"" >> "$tmp_file"
    fi

    echo '  },' >> "$tmp_file"

    echo "$updates_made"
}

# Function to update TFLint plugins section in versions.json
update_tflint_plugins() {
    local versions_file=$1
    local tmp_file=$2
    local updates_made=false

    echo -e "\n${BLUE}Checking for TFLint plugin updates...${NC}" >&2

    # Define plugins to check
    local plugins=("aws" "azurerm" "google" "opa")

    # Build plugins section
    echo '  "tflint_plugins": {' >> "$tmp_file"

    local first=true
    for plugin in "${plugins[@]}"; do
        # Read current version
        local current_version=$(grep -o "\"$plugin\": *\"[^\"]*\"" "$versions_file" | sed "s/\"$plugin\": *\"\(.*\)\"/\1/" || echo "")

        # Get latest version from GitHub
        local latest_version=$(get_latest_github_release "terraform-linters" "tflint-ruleset-$plugin")

        # Add comma if not first
        if [ "$first" = false ]; then
            # Update last line to add comma
            sed -i '$ s/$/,/' "$tmp_file"
        fi
        first=false

        # Check if update needed
        if [ -n "$latest_version" ] && [ "$latest_version" != "$current_version" ]; then
            echo -e "${GREEN}✓${NC} $plugin: ${YELLOW}$current_version${NC} → ${GREEN}$latest_version${NC}" >&2
            echo "    \"$plugin\": \"$latest_version\"" >> "$tmp_file"
            updates_made=true
        else
            echo -e "${BLUE}✓${NC} $plugin: ${current_version:-$latest_version} (already latest)" >&2
            echo "    \"$plugin\": \"${current_version:-$latest_version}\"" >> "$tmp_file"
        fi
    done

    echo '  }' >> "$tmp_file"

    echo "$updates_made"
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

echo -e "\n${BLUE}Checking for updates...${NC}"
echo "Versions file: $VERSIONS_FILE"
echo

# Read current versions from versions.json
UPDATES_MADE=false
TOOLS_UPDATES=false
PLUGINS_UPDATES=false
TMP_FILE=$(mktemp)

# Start building the new JSON
echo '{' > "$TMP_FILE"

# Process providers if enabled
if [ "$UPDATE_PROVIDERS" = true ]; then
    echo -e "\n${BLUE}Checking for provider updates...${NC}"
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

    # Close providers section
    echo '' >> "$TMP_FILE"
    echo '  },' >> "$TMP_FILE"
else
    # If skipping providers, read them from current file
    echo '  "providers": {' >> "$TMP_FILE"
    first=true
    while IFS= read -r line; do
        if ! echo "$line" | grep -qE '"[^"]+/[^"]+": \[.*\]'; then
            continue
        fi
        if [ "$first" = false ]; then
            echo ',' >> "$TMP_FILE"
        fi
        first=false
        echo "    $line" >> "$TMP_FILE"
    done < <(grep -E '"[^"]+/[^"]+": \[.*\]' "$VERSIONS_FILE")
    echo '' >> "$TMP_FILE"
    echo '  },' >> "$TMP_FILE"
fi

# Process tools if enabled
if [ "$UPDATE_TOOLS" = true ]; then
    TOOLS_UPDATES=$(update_tools "$VERSIONS_FILE" "$TMP_FILE")
    if [ "$TOOLS_UPDATES" = "true" ]; then
        UPDATES_MADE=true
    fi

    # Process TFLint plugins
    PLUGINS_UPDATES=$(update_tflint_plugins "$VERSIONS_FILE" "$TMP_FILE")
    if [ "$PLUGINS_UPDATES" = "true" ]; then
        UPDATES_MADE=true
    fi
else
    # If skipping tools, read them from current file
    # Extract tools section
    echo '  "tools": {' >> "$TMP_FILE"
    tools_lines=$(grep -A 3 '"tools":' "$VERSIONS_FILE" | tail -n +2 | head -n -1)
    if [ -n "$tools_lines" ]; then
        echo "$tools_lines" | sed 's/^  /    /' >> "$TMP_FILE"
    fi
    echo '  },' >> "$TMP_FILE"

    # Extract tflint_plugins section
    echo '  "tflint_plugins": {' >> "$TMP_FILE"
    plugins_lines=$(grep -A 5 '"tflint_plugins":' "$VERSIONS_FILE" | tail -n +2 | head -n -1)
    if [ -n "$plugins_lines" ]; then
        echo "$plugins_lines" | sed 's/^  /    /' >> "$TMP_FILE"
    fi
    echo '  }' >> "$TMP_FILE"
fi

# Close the JSON
echo '}' >> "$TMP_FILE"

echo ""

# Apply updates if not in dry-run mode
if [ "$DRY_RUN" = false ]; then
    if [ "$UPDATES_MADE" = true ]; then
        mv "$TMP_FILE" "$VERSIONS_FILE"
        echo -e "${GREEN}✓ versions.json updated successfully${NC}"
        echo "Updated: $VERSIONS_FILE"
        echo ""
        if [ "$UPDATE_PROVIDERS" = true ]; then
            echo -e "${YELLOW}Note: Run 'bazel run ${TARGET_PREFIX}:tf-mod' to regenerate locks and terraform.tf files${NC}"
        fi
    else
        rm "$TMP_FILE"
        echo -e "${BLUE}No updates needed - all versions are at their latest${NC}"
    fi
else
    rm -f "$TMP_FILE"
    echo -e "${YELLOW}Dry run mode - no changes made${NC}"
    echo ""
    echo "Run without --dry-run to apply updates"
fi

echo ""
if [ "$UPDATE_PROVIDERS" = true ] && [ "$UPDATE_TOOLS" = true ]; then
    echo -e "${GREEN}✓ Version check complete (providers, tools, and plugins)${NC}"
elif [ "$UPDATE_PROVIDERS" = true ]; then
    echo -e "${GREEN}✓ Provider version check complete${NC}"
else
    echo -e "${GREEN}✓ Tool and plugin version check complete${NC}"
fi