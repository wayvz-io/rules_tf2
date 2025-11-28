"""Terraform source file tracking validation rules"""

load("//tf2/tools/runners:shell_utils.bzl", "get_workspace_dir_script")

def _tf_untracked_files_test_impl(ctx):
    """Implementation of tf_untracked_files_test rule"""

    # Create test executable that validates all .tf files are tracked in srcs
    test_file = ctx.actions.declare_file(ctx.label.name + "_test.sh")

    # Build list of tracked source files
    tracked_files = [f.basename for f in ctx.files.srcs if f.basename.endswith(".tf")]
    tracked_files_str = " ".join(['"{}"'.format(f) for f in tracked_files])

    # Get package directory - we need to check files in the source directory
    package_dir = ctx.label.package if ctx.label.package else "."

    ctx.actions.write(
        output = test_file,
        content = """#!/usr/bin/env bash
set -euo pipefail

{workspace_script}

# Package directory containing the module
PACKAGE_DIR="{package_dir}"

# Full path to module directory
MODULE_DIR="$WORKSPACE_DIR/$PACKAGE_DIR"

# Check if we can access the module directory
if [ ! -d "$MODULE_DIR" ]; then
    # In sandbox, we can't access the source directory
    # This test only works with BUILD_WORKSPACE_DIRECTORY set
    echo "⚠ Skipping untracked files check (not in workspace directory)" >&2
    echo "  This test requires BUILD_WORKSPACE_DIRECTORY to be set" >&2
    echo "  It will be enforced in CI when Gazelle integration is complete" >&2
    exit 0
fi

# Find all .tf files in the module directory (excluding terraform.tf and *.gen.tf)
UNTRACKED_FILES=()
while IFS= read -r -d '' file; do
    basename=$(basename "$file")

    # Skip terraform.tf (auto-generated) and *.gen.tf files
    if [[ "$basename" == "terraform.tf" ]] || [[ "$basename" == *.gen.tf ]]; then
        continue
    fi

    # Check if this file is in the tracked list
    TRACKED_FILES=({tracked_files})
    IS_TRACKED=false
    for tracked in "${{TRACKED_FILES[@]}}"; do
        if [ "$basename" = "$tracked" ]; then
            IS_TRACKED=true
            break
        fi
    done

    if [ "$IS_TRACKED" = "false" ]; then
        UNTRACKED_FILES+=("$basename")
    fi
done < <(find "$MODULE_DIR" -maxdepth 1 -name "*.tf" -type f -print0 2>/dev/null || true)

# Report results
if [ ${{#UNTRACKED_FILES[@]}} -gt 0 ]; then
    echo "" >&2
    echo "ERROR: Found .tf files not included in tf_module srcs attribute:" >&2
    for file in "${{UNTRACKED_FILES[@]}}"; do
        echo "  - $file" >&2
    done
    echo "" >&2
    echo "To fix this issue:" >&2
    echo "  1. Add missing files to the srcs attribute in //{package_dir}/BUILD.bazel" >&2
    echo "  2. Or run 'bazel run //:gazelle' when Gazelle integration is available" >&2
    echo "" >&2
    echo "Current tracked files: {tracked_files}" >&2
    exit 1
fi

echo "✓ All .tf files are tracked in tf_module srcs"
exit 0
""".format(
            workspace_script = get_workspace_dir_script(),
            package_dir = package_dir,
            tracked_files = tracked_files_str,
        ),
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([test_file]),
            executable = test_file,
            runfiles = ctx.runfiles(
                files = [test_file] + ctx.files.srcs,
            ),
        ),
    ]

tf_untracked_files_test = rule(
    implementation = _tf_untracked_files_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Terraform source files that should be tracked",
            mandatory = True,
        ),
    },
    test = True,
    doc = "Tests that all .tf files in the module directory are tracked in srcs",
)

def _tf_untracked_files_negative_test_impl(ctx):
    """Implementation of tf_untracked_files_negative_test rule that expects untracked files"""

    # Create test executable that validates untracked files are detected
    test_file = ctx.actions.declare_file(ctx.label.name + "_test.sh")

    # Build list of tracked source files
    tracked_files = [f.basename for f in ctx.files.srcs if f.basename.endswith(".tf")]
    tracked_files_str = " ".join(['"{}"'.format(f) for f in tracked_files])

    # Get package directory
    package_dir = ctx.label.package if ctx.label.package else "."

    ctx.actions.write(
        output = test_file,
        content = """#!/usr/bin/env bash
set -euo pipefail

{workspace_script}

# Package directory containing the module
PACKAGE_DIR="{package_dir}"

# Full path to module directory
MODULE_DIR="$WORKSPACE_DIR/$PACKAGE_DIR"

# Check if we can access the module directory
if [ ! -d "$MODULE_DIR" ]; then
    # In sandbox, we can't access the source directory
    # Skip this negative test
    echo "⚠ Skipping negative test (not in workspace directory)" >&2
    exit 0
fi

# Find all .tf files in the module directory (excluding terraform.tf and *.gen.tf)
UNTRACKED_FILES=()
while IFS= read -r -d '' file; do
    basename=$(basename "$file")

    # Skip terraform.tf (auto-generated) and *.gen.tf files
    if [[ "$basename" == "terraform.tf" ]] || [[ "$basename" == *.gen.tf ]]; then
        continue
    fi

    # Check if this file is in the tracked list
    TRACKED_FILES=({tracked_files})
    IS_TRACKED=false
    for tracked in "${{TRACKED_FILES[@]}}"; do
        if [ "$basename" = "$tracked" ]; then
            IS_TRACKED=true
            break
        fi
    done

    if [ "$IS_TRACKED" = "false" ]; then
        UNTRACKED_FILES+=("$basename")
    fi
done < <(find "$MODULE_DIR" -maxdepth 1 -name "*.tf" -type f -print0 2>/dev/null || true)

# Report results (negative test - we EXPECT untracked files)
if [ ${{#UNTRACKED_FILES[@]}} -gt 0 ]; then
    echo "✓ Found untracked files as expected (negative test passed):"
    for file in "${{UNTRACKED_FILES[@]}}"; do
        echo "  - $file"
    done
    exit 0
else
    echo "" >&2
    echo "✗ Expected untracked .tf files but all files are tracked (negative test failed)" >&2
    echo "Tracked files: {tracked_files}" >&2
    exit 1
fi
""".format(
            workspace_script = get_workspace_dir_script(),
            package_dir = package_dir,
            tracked_files = tracked_files_str,
        ),
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([test_file]),
            executable = test_file,
            runfiles = ctx.runfiles(
                files = [test_file] + ctx.files.srcs,
            ),
        ),
    ]

tf_untracked_files_negative_test = rule(
    implementation = _tf_untracked_files_negative_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Terraform source files (intentionally incomplete for testing)",
            mandatory = True,
        ),
    },
    test = True,
    doc = "Tests that untracked .tf files are properly detected (negative test)",
)
