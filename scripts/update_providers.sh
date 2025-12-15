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
            echo "Update Terraform provider versions in versions.json"
            echo ""
            echo "After running this script, provider hashes will be automatically"
            echo "generated on the next bazel build and stored in MODULE.bazel.lock."
            echo ""
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

echo -e "${BLUE}=== Terraform Provider Update Workflow ===${NC}"
echo ""

# Find workspace root to run bazel commands
WORKSPACE_ROOT="${BUILD_WORKSPACE_DIRECTORY:-}"
if [ -z "$WORKSPACE_ROOT" ]; then
    WORKSPACE_ROOT="$(pwd)"
    while [ "$WORKSPACE_ROOT" != "/" ]; do
        if [ -f "$WORKSPACE_ROOT/MODULE.bazel" ] || [ -f "$WORKSPACE_ROOT/WORKSPACE" ] || [ -f "$WORKSPACE_ROOT/WORKSPACE.bazel" ]; then
            break
        fi
        WORKSPACE_ROOT="$(dirname "$WORKSPACE_ROOT")"
    done
fi

cd "$WORKSPACE_ROOT"

# Update provider versions
echo -e "${BLUE}Checking for provider version updates...${NC}"

UPGRADE_ARGS=()
if [ "$DRY_RUN" = true ]; then
    UPGRADE_ARGS+=("--dry-run")
fi
if [ "$VERBOSE" = true ]; then
    UPGRADE_ARGS+=("--verbose")
fi

if ! bazel run ${TARGET_PREFIX}scripts:tf_upgrade_providers -- "${UPGRADE_ARGS[@]}"; then
    echo -e "${RED}Error: Provider version update failed${NC}"
    exit 1
fi

echo ""
if [ "$DRY_RUN" = false ]; then
    echo -e "${GREEN}✓ Provider versions updated${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Run 'bazel build //...' to generate provider hashes"
    echo -e "  2. Run 'bazel run ${TARGET_PREFIX}:regenerate' to update terraform.tf configs"
else
    echo -e "${YELLOW}Dry run complete. No changes made.${NC}"
fi
