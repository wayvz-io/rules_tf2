"""File utilities for Terraform rules"""

def compare_files(ctx, file1, file2, name):
    """Creates an action that compares two files and fails if they differ.
    
    Args:
        ctx: Rule context
        file1: First file to compare
        file2: Second file to compare
        name: Name for the comparison action
        
    Returns:
        A File containing the comparison result
    """
    result = ctx.actions.declare_file(name + "_result")
    
    ctx.actions.run_shell(
        inputs = [file1, file2],
        outputs = [result],
        command = """
if cmp -s "$1" "$2"; then
    echo "Files match" > "$3"
    exit 0
else
    echo "ERROR: Files differ" >&2
    echo "File 1 ($1):" >&2
    cat "$1" >&2
    echo "" >&2
    echo "File 2 ($2):" >&2
    cat "$2" >&2
    exit 1
fi
""",
        arguments = [file1.path, file2.path, result.path],
        mnemonic = "CompareFiles",
        progress_message = "Comparing {} and {}".format(file1.short_path, file2.short_path),
    )
    
    return result

def copy_to_source_dir(ctx, source_file, target_path):
    """Creates a script that copies a file to the source directory.
    
    Args:
        ctx: Rule context
        source_file: File to copy
        target_path: Target path relative to workspace root
        
    Returns:
        Executable script file
    """
    script = ctx.actions.declare_file(ctx.label.name + "_copy.sh")
    
    script_content = """#!/usr/bin/env bash
set -euo pipefail

# Get the workspace directory
if [ -n "${{BUILD_WORKSPACE_DIRECTORY:-}}" ]; then
    WORKSPACE_DIR="$BUILD_WORKSPACE_DIRECTORY"
else
    # Find workspace root by looking for MODULE.bazel
    WORKSPACE_DIR="$PWD"
    while [ ! -f "$WORKSPACE_DIR/MODULE.bazel" ] && [ "$WORKSPACE_DIR" != "/" ]; do
        WORKSPACE_DIR=$(dirname "$WORKSPACE_DIR")
    done
fi

# Source and target paths
SOURCE_FILE="$0.runfiles/_main/{source}"
TARGET_FILE="$WORKSPACE_DIR/{target}"

# Create directory if needed
TARGET_DIR=$(dirname "$TARGET_FILE")
mkdir -p "$TARGET_DIR"

# Copy the file
cp -f "$SOURCE_FILE" "$TARGET_FILE"

echo "Copied to $TARGET_FILE"
""".format(
        source = source_file.short_path,
        target = target_path,
    )
    
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )
    
    return script

def read_file_content(ctx, file):
    """Reads file content into a string during analysis phase.
    
    Note: This only works for source files, not generated files.
    
    Args:
        ctx: Rule context
        file: File to read
        
    Returns:
        String content of the file
    """
    return ctx.read(file)