#!/usr/bin/env bash
# Terraform runner script - executes terraform commands in a temporary workspace
# This script is called by the tf_runner Bazel rule

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_DIR="$1"
BACKEND_TYPE="${2:-}"
TFE_HOST="${3:-app.terraform.io}"
INIT_ARGS="${4:-}"
DEFAULT_PLAN_ARGS="${5:-}"
DEFAULT_APPLY_ARGS="${6:-}"

# Shift the fixed arguments
shift 6 || true

if [ ! -d "$STAGING_DIR" ]; then
    echo "Error: Staging directory not found at $STAGING_DIR"
    exit 1
fi

# Create a temporary working directory
WORK_DIR=$(mktemp -d -t terraform-XXXXXX)

# Ensure cleanup happens even on script exit
cleanup() {
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        chmod -R u+w "$WORK_DIR" 2>/dev/null || true
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT INT TERM

# Copy staging files to work directory
cp -r "$STAGING_DIR"/* "$WORK_DIR/" 2>/dev/null || true
cp -r "$STAGING_DIR"/.* "$WORK_DIR/" 2>/dev/null || true

# Change to work directory
cd "$WORK_DIR"

# Check if we need TFE_TOKEN for cloud operations
if [ "$BACKEND_TYPE" = "cloud" ] || [ "$BACKEND_TYPE" = "remote" ]; then
    # Default to 'plan' if no arguments provided
    COMMAND="${1:-plan}"
    case "$COMMAND" in
        init|plan|apply|refresh|import|state|taint|untaint)
            if [ -z "${TFE_TOKEN:-}" ]; then
                echo "Error: TFE_TOKEN environment variable is required for Terraform Cloud operations"
                echo "Please set TFE_TOKEN with your Terraform Cloud API token"
                echo "You can use: op run -- bazel run <target> to inject the token from 1Password"
                cleanup
                exit 1
            fi
            
            # Check if token is an unresolved 1Password reference
            if [[ "${TFE_TOKEN}" == op://* ]]; then
                echo "Error: TFE_TOKEN contains an unresolved 1Password reference: ${TFE_TOKEN}"
                echo "Please run this command with 'op run --' prefix to resolve the token:"
                echo "  op run -- bazel run <target>"
                cleanup
                exit 1
            fi
            
            # Create Terraform credentials file from TFE_TOKEN
            mkdir -p "$HOME/.terraform.d"
            cat > "$HOME/.terraform.d/credentials.tfrc.json" <<EOF
{
  "credentials": {
    "${TFE_HOST}": {
      "token": "${TFE_TOKEN}"
    }
  }
}
EOF
            export TF_CLI_CONFIG_FILE="$HOME/.terraform.d/credentials.tfrc.json"
            ;;
    esac
fi

# Initialize terraform if needed
if [ ! -d ".terraform" ] || [ "${1:-}" = "init" ]; then
    echo "Initializing Terraform..."
    # Always enforce lockfile as read-only to prevent unintended modifications
    terraform init -lockfile=readonly $INIT_ARGS
fi

# Handle command execution
if [ $# -eq 0 ]; then
    # Default to plan if no arguments
    echo "Running terraform plan..."
    exec terraform plan $DEFAULT_PLAN_ARGS
elif [ "$1" = "plan" ] && [ $# -eq 1 ]; then
    # Add default args for plan if no additional args provided
    shift
    exec terraform plan $DEFAULT_PLAN_ARGS "$@"
elif [ "$1" = "apply" ] && [ $# -eq 1 ]; then
    # Add default args for apply if no additional args provided  
    shift
    exec terraform apply $DEFAULT_APPLY_ARGS "$@"
else
    # Pass through all arguments to terraform
    exec terraform "$@"
fi