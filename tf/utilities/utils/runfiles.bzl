"""Utilities for handling runfiles in Terraform rules"""

def create_runfiles_path(ctx, file):
    """Creates a runfiles-compatible path for a file.
    
    Args:
        ctx: Rule context
        file: File object
        
    Returns:
        String path that works in runfiles
    """
    # For directories in bazel-out, we need to use the full path including the configuration
    if file.short_path.startswith("bazel-out/"):
        return file.short_path
    return "_main/{}".format(file.short_path)

def get_runfiles_dir_script():
    """Returns shell script snippet to find runfiles directory.
    
    Returns:
        Shell script string that sets RUNFILES variable
    """
    return """
# Find the runfiles directory
if [ -n "${RUNFILES_DIR:-}" ]; then
    RUNFILES="$RUNFILES_DIR"
elif [ -f "$0.runfiles_manifest" ]; then
    RUNFILES="$0.runfiles"
else
    RUNFILES="$0.runfiles"
fi
"""

def get_workspace_dir_script():
    """Returns shell script snippet to find workspace directory.
    
    Returns:
        Shell script string that sets WORKSPACE_DIR variable
    """
    return """
# Get the workspace directory
if [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
    WORKSPACE_DIR="$BUILD_WORKSPACE_DIRECTORY"
else
    # Find workspace root by looking for MODULE.bazel
    WORKSPACE_DIR="$PWD"
    while [ ! -f "$WORKSPACE_DIR/MODULE.bazel" ] && [ "$WORKSPACE_DIR" != "/" ]; do
        WORKSPACE_DIR=$(dirname "$WORKSPACE_DIR")
    done
fi
"""

def create_temp_dir_script():
    """Returns shell script snippet to create a temporary directory with cleanup.
    
    Returns:
        Shell script string that creates WORK_DIR with trap cleanup
    """
    return """
# Create temporary directory with cleanup
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT
"""