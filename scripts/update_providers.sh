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
            echo "Complete Terraform provider update workflow"
            echo "This script:"
            echo "  1. Updates provider versions (tf-upgrade-providers)"
            echo "  2. Generates locks and updates terraform.tf files (tf-mod)"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be updated without making changes"
            echo "  --verbose    Show detailed output"
            echo "  --help       Show this help message"
            echo ""
            echo "Individual commands:"
            echo "  bazel run ${TARGET_PREFIX}:tf-upgrade-providers  # Update versions only"
            echo "  bazel run ${TARGET_PREFIX}:tf-mod                # Generate locks and terraform.tf files"
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

# Step 1: Update provider versions
echo -e "${BLUE}Step 1: Checking for provider version updates...${NC}"

UPGRADE_ARGS=()
if [ "$DRY_RUN" = true ]; then
    UPGRADE_ARGS+=("--dry-run")
fi
if [ "$VERBOSE" = true ]; then
    UPGRADE_ARGS+=("--verbose")
fi

if ! bazel run ${TARGET_PREFIX}:tf-upgrade-providers -- "${UPGRADE_ARGS[@]}"; then
    echo -e "${RED}Error: Provider version update failed${NC}"
    exit 1
fi

# Step 2: Generate locks and update terraform.tf files (only if not dry-run)
if [ "$DRY_RUN" = false ]; then
    echo ""
    echo -e "${BLUE}Step 2: Generating provider locks and updating terraform.tf files...${NC}"

    MOD_ARGS=()
    if [ "$VERBOSE" = true ]; then
        MOD_ARGS+=("--verbose")
    fi

    if ! bazel run ${TARGET_PREFIX}:tf-mod -- "${MOD_ARGS[@]}"; then
        echo -e "${RED}Error: Provider lock generation failed${NC}"
        exit 1
    fi
else
    echo ""
    echo -e "${YELLOW}Dry run mode: Skipping lock generation${NC}"
    echo "Run without --dry-run to apply changes and generate locks"
fi

echo ""
echo -e "${GREEN}✓ Terraform provider update workflow complete${NC}"