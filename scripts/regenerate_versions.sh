#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to log messages
log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "$1"
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

cd "$WORKSPACE_ROOT"

# Regenerate all terraform.tf files
echo ""
echo "Regenerating versions in terraform.tf files..."

# Query for all _generate_versions targets
targets=$(bazel query 'attr(name, ".*_generate_versions", //...)' 2>/dev/null)

if [ -n "$targets" ]; then
    echo "Found $(echo "$targets" | wc -l) targets to regenerate"
    echo "Running all version generation targets..."
    
    # Count total and successful targets
    total_targets=$(echo "$targets" | wc -l)
    success_count=0
    
    # Run targets individually for better control and error reporting
    for target in $targets; do
        if [ "$VERBOSE" = true ]; then
            log "Regenerating: $target"
        fi
        
        if bazel run "$target" > /dev/null 2>&1; then
            success_count=$((success_count + 1))
            if [ "$VERBOSE" = true ]; then
                echo -e "${GREEN}✓${NC} Regenerated: $target"
            fi
        else
            echo -e "${YELLOW}⚠${NC} Failed to regenerate: $target"
        fi
    done
    
    echo -e "${GREEN}✓${NC} Regenerated $success_count/$total_targets version targets"
else
    echo "No version generation targets found"
fi

# Query for all _generate_docs targets
echo ""
echo "Regenerating documentation..."
doc_targets=$(bazel query 'attr(name, ".*_generate_docs", //...)' 2>/dev/null)

if [ -n "$doc_targets" ]; then
    echo "Found $(echo "$doc_targets" | wc -l) documentation targets"
    echo "Running all documentation targets..."
    
    # Count total and successful targets
    total_doc_targets=$(echo "$doc_targets" | wc -l)
    doc_success_count=0
    
    # Run targets individually for better control and error reporting
    for target in $doc_targets; do
        if [ "$VERBOSE" = true ]; then
            log "Regenerating docs: $target"
        fi
        
        if bazel run "$target" > /dev/null 2>&1; then
            doc_success_count=$((doc_success_count + 1))
            if [ "$VERBOSE" = true ]; then
                echo -e "${GREEN}✓${NC} Regenerated docs: $target"
            fi
        else
            echo -e "${YELLOW}⚠${NC} Failed to regenerate docs: $target"
        fi
    done
    
    echo -e "${GREEN}✓${NC} Regenerated $doc_success_count/$total_doc_targets documentation targets"
else
    echo "No documentation generation targets found"
fi

echo ""
echo -e "${GREEN}✓ Version and documentation regeneration complete${NC}"