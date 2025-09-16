#!/usr/bin/env bash
# Wrapper script for Terraform providers to run with system libraries
# This script is called by cdktf when it needs to execute a provider

# The provider binary is passed as the first argument
PROVIDER_BIN="$1"
shift

# Run the provider with Debian system libraries
# This allows the pre-compiled provider binaries to find the libraries they need
LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu:/usr/lib:/lib/aarch64-linux-gnu:/lib" \
exec "$PROVIDER_BIN" "$@"