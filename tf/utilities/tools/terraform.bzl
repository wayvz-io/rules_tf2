"""Terraform command execution utilities"""

load("//tf/utilities/utils:runfiles.bzl", "get_runfiles_dir_script", "create_temp_dir_script", "create_runfiles_path")

def terraform_init_script(ctx, plugin_dir = None, backend = False, upgrade = False, lockfile_readonly = True):
    """Generates terraform init command with appropriate flags.
    
    Args:
        ctx: Rule context
        plugin_dir: Optional plugin directory file (for filesystem_mirror)
        backend: Whether to initialize backend
        upgrade: Whether to upgrade providers
        lockfile_readonly: Whether to enforce lock file as read-only (default: True)
        
    Returns:
        String containing terraform init command
    """
    cmd_parts = ["terraform", "init"]
    
    if not backend:
        cmd_parts.append("-backend=false")
    if not upgrade:
        cmd_parts.append("-upgrade=false")
    # Apply lockfile=readonly to enforce lock file integrity
    if lockfile_readonly:
        cmd_parts.append("-lockfile=readonly")
    
    if plugin_dir:
        plugin_path = create_runfiles_path(ctx, plugin_dir)
        # Use filesystem_mirror configuration instead of -plugin-dir
        return """
# Set up Terraform CLI configuration for filesystem mirror
# The plugin_dir is a marker file, get the actual directory
MARKER_FILE="$RUNFILES/{plugin_path}"
if [ -f "$MARKER_FILE" ]; then
    # Read the directory name from the marker
    PROVIDER_DIR_NAME=$(cat "$MARKER_FILE")
    # Get the parent directory of the marker file
    MARKER_DIR=$(dirname "$MARKER_FILE")
    
    # Dynamically find the provider directory in runfiles
    # Look for any directory matching tf*~~tf_providers~tf_provider* pattern
    PROVIDER_MIRROR_PATH=""
    
    # Try various possible locations
    for PREFIX in "_main/external" "external" "../external"; do
        for REPO in rules_tf2~~tf_providers~tf_providers_test rules_tf2~~tf_providers~tf_provider_registry tf2~~tf_providers~tf_providers_test tf2~~tf_providers~tf_provider_registry tf_provider_registry; do
            CANDIDATE="$RUNFILES/$PREFIX/$REPO/$PROVIDER_DIR_NAME"
            if [ -d "$CANDIDATE" ]; then
                PROVIDER_MIRROR_PATH="$CANDIDATE"
                break 2
            fi
        done
    done
    
    # If still not found, try a broader search
    if [ -z "$PROVIDER_MIRROR_PATH" ] || [ ! -d "$PROVIDER_MIRROR_PATH" ]; then
        # Look for the mirror directory by searching for a known provider structure
        SEARCH_PATHS=("$RUNFILES/_main/external" "$RUNFILES/external" "$RUNFILES/../external")
        for SEARCH_PATH in "${{SEARCH_PATHS[@]}}"; do
            if [ -d "$SEARCH_PATH" ]; then
                FOUND_DIR=$(find "$SEARCH_PATH" -maxdepth 2 -name "$PROVIDER_DIR_NAME" -type d 2>/dev/null | head -1)
                if [ -n "$FOUND_DIR" ] && [ -d "$FOUND_DIR" ]; then
                    PROVIDER_MIRROR_PATH="$FOUND_DIR"
                    break
                fi
            fi
        done
    fi
else
    # Fallback to direct directory path
    PROVIDER_MIRROR_PATH="$RUNFILES/{plugin_path}"
fi

if [ -d "$PROVIDER_MIRROR_PATH" ]; then
    # Create temporary CLI config file
    CLI_CONFIG_FILE="$WORK_DIR/.terraformrc"
    cat > "$CLI_CONFIG_FILE" <<'EOF'
provider_installation {{
  filesystem_mirror {{
    path = "{placeholder}"
  }}
}}
disable_checkpoint = true
EOF
    
    # Replace placeholder with actual path
    sed -i "s|{{placeholder}}|$PROVIDER_MIRROR_PATH|g" "$CLI_CONFIG_FILE" 2>/dev/null || \
    sed -i '' "s|{{placeholder}}|$PROVIDER_MIRROR_PATH|g" "$CLI_CONFIG_FILE" 2>/dev/null || true
    
    # Export CLI config file path
    export TF_CLI_CONFIG_FILE="$CLI_CONFIG_FILE"
    
    # Disable network access for providers
    export TF_DISABLE_CHECKPOINT=true
    export CHECKPOINT_DISABLE=true
    
    # Run terraform init with reduced output
    {cmd} -no-color 2>&1 | grep -v "^Initializing" | grep -v "^- Finding" | grep -v "^- Installing" | grep -v "^Terraform has been successfully initialized" | grep -v "^You may now begin working" | grep -v "^If you ever set or change" | grep -v "^rerun this command" | grep -v "^Terraform has created a lock file" | grep -v "^selections it made above" | grep -v "^so that Terraform can guarantee" | grep -v 'you run "terraform init"' | grep -v "Warning: Incomplete lock file" | grep -v "Due to your customized provider" | grep -v "to calculate lock file" | grep -v "The current .terraform.lock.hcl" | grep -v "so Terraform running on another" | grep -v "To calculate additional checksums" | grep -v "terraform providers lock" | grep -v "(where .* is the platform" || true
    
    # Check if init actually succeeded
    if [ ${{PIPESTATUS[0]}} -ne 0 ]; then
        echo "ERROR: terraform init failed"
        # Re-run to show full error output
        {cmd} -no-color
        exit 1
    fi
else
    echo "ERROR: Provider mirror directory not found at $PROVIDER_MIRROR_PATH"
    exit 1
fi
""".format(plugin_path = plugin_path, placeholder="{placeholder}", cmd = " ".join(cmd_parts))
    
    return " ".join(cmd_parts)

def copy_module_files_script(ctx, module_dir, include_versions = True):
    """Generates script to copy module files to work directory.
    
    Args:
        ctx: Rule context
        module_dir: Module directory path
        include_versions: Whether to include versions file
        
    Returns:
        Shell script string
    """
    # Always use inline version for simplicity
    repo_name = ctx.label.workspace_name
    if repo_name:
        return """
# Copy all files from the module directory (external repository)
MODULE_DIR="$RUNFILES/{repo_name}/{module_dir}"
if [ ! -d "$MODULE_DIR" ]; then
    # Try with ~~ separator (newer bazel versions)
    MODULE_DIR="$RUNFILES/{repo_name}~/{module_dir}"
fi
if [ -d "$MODULE_DIR" ]; then
    cp -r "$MODULE_DIR"/* "$WORK_DIR/" 2>/dev/null || true
    # Also copy hidden files (like .terraform.lock.hcl)
    cp -r "$MODULE_DIR"/.[^.]* "$WORK_DIR/" 2>/dev/null || true
else
    echo "ERROR: Module directory not found at $MODULE_DIR"
    ls -la "$RUNFILES/{repo_name}/" | head -20 || true
    ls -la "$RUNFILES/{repo_name}~/" | head -20 || true
fi
""".format(repo_name = repo_name, module_dir = module_dir)
    else:
        return """
# Copy all files from the module directory
MODULE_DIR="$RUNFILES/_main/{module_dir}"
if [ -d "$MODULE_DIR" ]; then
    cp -r "$MODULE_DIR"/* "$WORK_DIR/" 2>/dev/null || true
    # Also copy hidden files (like .terraform.lock.hcl)
    cp -r "$MODULE_DIR"/.[^.]* "$WORK_DIR/" 2>/dev/null || true
fi
""".format(module_dir = module_dir)

def copy_source_files_script(ctx, srcs):
    """Generates script to copy individual source files to work directory.
    
    Args:
        ctx: Rule context
        srcs: List of source files to copy
        
    Returns:
        Shell script string
    """
    if not srcs:
        return "# No source files to copy"
    
    # Always use inline version for simplicity
    copy_commands = []
    seen_basenames = {}
    module_package = ctx.label.package
    
    for src in srcs:
        # Skip files that are in the module package directory
        # These are already copied by copy_module_files_script
        if src.short_path.startswith(module_package + "/"):
            continue
        
        # Also skip files from the same package in external repositories
        # e.g., ../tf2~/tests/tf_lock_integration/file.tf when module_package is tests/tf_lock_integration
        if "/" + module_package + "/" in src.short_path:
            continue
            
        src_path = create_runfiles_path(ctx, src)
        basename = src.basename
        
        if basename in seen_basenames:
            fail("File name conflict: '{}' appears in both '{}' and '{}'".format(
                basename, 
                seen_basenames[basename],
                src.short_path
            ))
        seen_basenames[basename] = src.short_path
        
        copy_commands.append("""
# Copy {short_path} to working directory
SRC_FILE="$RUNFILES/{src_path}"
if [ -f "$SRC_FILE" ]; then
    cp "$SRC_FILE" "$WORK_DIR/{basename}"
else
    echo "WARNING: Source file not found: $SRC_FILE"
fi""".format(
            short_path = src.short_path,
            src_path = src_path, 
            basename = basename
        ))
    
    if not copy_commands:
        return "# All source files are from the module directory"
    
    return "\n".join(copy_commands)

def create_terraform_script(ctx, name, commands, srcs, extra_runfiles = None):
    """Creates a script that runs terraform commands.
    
    Args:
        ctx: Rule context
        name: Script name
        commands: List of command strings to execute
        srcs: Source files to include in runfiles
        extra_runfiles: Additional files to include in runfiles
        
    Returns:
        Script file and runfiles
    """
    script = ctx.actions.declare_file(name)
    
    # For now, always use inline script generation to avoid complexity
    # The external scripts can be used in specific rules that need them
    copy_files_script = copy_module_files_script(ctx, ctx.label.package) + "\n" + copy_source_files_script(ctx, srcs)
    
    script_content = """#!/usr/bin/env bash
set -euo pipefail

{runfiles_script}
{temp_dir_script}

# Disable Terraform from accessing the network
export TF_DISABLE_CHECKPOINT=true
export CHECKPOINT_DISABLE=true

# Copy module files
{copy_files}

# Change to work directory
cd "$WORK_DIR"

# Execute commands
{commands}
""".format(
        runfiles_script = get_runfiles_dir_script(),
        temp_dir_script = create_temp_dir_script(),
        copy_files = copy_files_script,
        commands = "\n".join(commands),
    )
    script_files = []
    
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )
    
    runfiles_files = list(srcs) + script_files
    if extra_runfiles:
        runfiles_files.extend(extra_runfiles)
    
    # Create runfiles with transitive dependencies
    return script, ctx.runfiles(
        files = runfiles_files,
        transitive_files = depset(transitive = [f.files for f in extra_runfiles if hasattr(f, "files")])
    )