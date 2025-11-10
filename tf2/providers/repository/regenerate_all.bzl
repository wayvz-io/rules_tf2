"""Macro for creating targets that regenerate versions and docs across the workspace"""

load("//tf2/tools/runners:shell_utils.bzl", "get_workspace_dir_script")

def _tf_regenerate_all_impl(ctx):
    """Implementation of tf_regenerate_all rule"""

    # Create script to regenerate versions and docs
    script = ctx.actions.declare_file(ctx.label.name + "_regenerate.sh")

    script_content = """#!/usr/bin/env bash
set -euo pipefail

{workspace_script}

echo "Regenerating versions and documentation across workspace..."
echo ""

# Find and run version generation targets
echo "Finding version generation targets..."
cd "$WORKSPACE_DIR"
VERSION_TARGETS=$(bazel query 'attr(name, ".*_generate_versions", //...)' 2>/dev/null || echo "")

if [ -n "$VERSION_TARGETS" ]; then
    TARGET_COUNT=$(echo "$VERSION_TARGETS" | wc -l)
    echo "Found $TARGET_COUNT version generation targets"
    echo ""

    SUCCESS_COUNT=0
    FAILURE_COUNT=0

    while IFS= read -r target; do
        [ -z "$target" ] && continue

        echo "Regenerating: $target"
        cd "$WORKSPACE_DIR"
        if bazel run "$target" > /dev/null 2>&1; then
            echo "✓ Regenerated: $target"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "✗ Failed: $target"
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
        fi
    done <<< "$VERSION_TARGETS"

    echo ""
    echo "✓ Regenerated $SUCCESS_COUNT/$TARGET_COUNT version targets"
    if [ $FAILURE_COUNT -gt 0 ]; then
        echo "⚠ Failed to regenerate $FAILURE_COUNT targets"
    fi
else
    echo "No version generation targets found"
fi

# Find and run documentation generation targets
echo ""
echo "Finding documentation generation targets..."
cd "$WORKSPACE_DIR"
DOC_TARGETS=$(bazel query 'attr(name, ".*_generate_docs", //...)' 2>/dev/null || echo "")

if [ -n "$DOC_TARGETS" ]; then
    DOC_COUNT=$(echo "$DOC_TARGETS" | wc -l)
    echo "Found $DOC_COUNT documentation targets"
    echo ""

    DOC_SUCCESS=0
    DOC_FAILURE=0

    while IFS= read -r target; do
        [ -z "$target" ] && continue

        echo "Regenerating docs: $target"
        cd "$WORKSPACE_DIR"
        if bazel run "$target" > /dev/null 2>&1; then
            echo "✓ Regenerated docs: $target"
            DOC_SUCCESS=$((DOC_SUCCESS + 1))
        else
            echo "✗ Failed docs: $target"
            DOC_FAILURE=$((DOC_FAILURE + 1))
        fi
    done <<< "$DOC_TARGETS"

    echo ""
    echo "✓ Regenerated $DOC_SUCCESS/$DOC_COUNT documentation targets"
    if [ $DOC_FAILURE -gt 0 ]; then
        echo "⚠ Failed to regenerate $DOC_FAILURE documentation targets"
    fi
else
    echo "No documentation generation targets found"
fi

echo ""
echo "✓ Version and documentation regeneration complete"
""".format(
        workspace_script = get_workspace_dir_script(),
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([script]),
            executable = script,
            runfiles = ctx.runfiles(files = [script]),
        ),
    ]

tf_regenerate_all = rule(
    implementation = _tf_regenerate_all_impl,
    attrs = {},
    executable = True,
    doc = """Regenerates all version and documentation targets in the workspace.

    This rule creates an executable that uses 'bazel query' to find all targets
    matching the patterns '*_generate_versions' and '*_generate_docs', then runs
    each one to regenerate terraform.tf files and documentation.

    Example:
        tf_regenerate_all(
            name = "regenerate_all",
        )

    Usage:
        bazel run //:regenerate_all
    """,
)
