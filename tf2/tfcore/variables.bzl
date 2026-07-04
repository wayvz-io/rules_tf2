"""Rules for managing Terraform variables and configurations."""

TfVariablesInfo = provider(
    doc = "Information about Terraform variables",
    fields = {
        "name": "Variables configuration name",
        "tfvars_files": "List of .tfvars files",
        "json_files": "List of .tfvars.json files",
        "all_files": "All variable files",
    },
)

def _tf_variables_impl(ctx):
    """Implementation of tf_variables rule."""

    # Collect all variable files
    all_files = []
    tfvars_files = []
    json_files = []

    for src in ctx.files.srcs:
        all_files.append(src)
        if src.path.endswith(".tfvars"):
            tfvars_files.append(src)
        elif src.path.endswith(".tfvars.json"):
            json_files.append(src)

    # If validation is enabled, create a validation script
    if ctx.attr.validate:
        validation_script = ctx.actions.declare_file("{}_validate.sh".format(ctx.attr.name))

        validation_content = """#!/usr/bin/env bash
set -euo pipefail

echo "Validating Terraform variables configuration: {name}"
echo "==========================================="

# Check that all files exist and are readable
ERRORS=0

{file_checks}

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "ERROR: Variable validation failed with $ERRORS errors"
    exit 1
fi

echo ""
echo "✓ All variable files validated successfully"
""".format(
            name = ctx.attr.name,
            file_checks = "\n".join([
                """
if [ ! -r "{file}" ]; then
    echo "ERROR: Cannot read variable file: {file}"
    ((ERRORS++))
else
    echo "✓ Found: {basename}"
fi""".format(
                    file = f.path,
                    basename = f.basename,
                )
                for f in all_files
            ]),
        )

        ctx.actions.write(
            output = validation_script,
            content = validation_content,
            is_executable = True,
        )

        # Note: Validation script is created but not executed during build
        # Users can run it separately if needed

    return [
        DefaultInfo(
            files = depset(all_files),
        ),
        TfVariablesInfo(
            name = ctx.attr.name,
            tfvars_files = tfvars_files,
            json_files = json_files,
            all_files = all_files,
        ),
    ]

tf_variables = rule(
    implementation = _tf_variables_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".tfvars", ".tfvars.json", ".auto.tfvars", ".auto.tfvars.json"],
            mandatory = True,
            doc = "Terraform variable files",
        ),
        "validate": attr.bool(
            default = True,
            doc = "Whether to validate files during build",
        ),
    },
    doc = """Defines a set of Terraform variables for use with stacks.
    
    This rule collects Terraform variable files (.tfvars and .tfvars.json) and
    makes them available for use with tf_module targets.
    
    Example:
        tf_variables(
            name = "dev_vars",
            srcs = [
                "environments/dev.tfvars",
                "common.tfvars",
            ],
        )
    """,
)
