"""Rules for managing Terraform versions using the HCL tool"""

def _tf_update_versions_impl(ctx):
    """Update terraform version requirements in .tf files"""

    # Create a script that runs the hcl_tool
    script = ctx.actions.declare_file(ctx.label.name + "_update.sh")

    # Build the script content
    script_content = """#!/usr/bin/env bash
set -euo pipefail

# Get the workspace directory
WORKSPACE_DIR="$(pwd)"

# Navigate to the target directory
cd "{package}"

# Run the HCL tool to update versions
"{hcl_tool}" write-versions \\
    --dir . \\
    --lock-file "{lock_file}" \\
    --tf-version "{tf_version}"

echo "Updated Terraform versions in {package}"
""".format(
        package = ctx.label.package,
        hcl_tool = ctx.executable.hcl_tool.short_path,
        lock_file = ctx.file.lock_file.path if ctx.file.lock_file else "",
        tf_version = ctx.attr.tf_version,
    )

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Collect runfiles
    runfiles = ctx.runfiles(files = [ctx.executable.hcl_tool])
    if ctx.file.lock_file:
        runfiles = runfiles.merge(ctx.runfiles(files = [ctx.file.lock_file]))

    return [
        DefaultInfo(
            executable = script,
            runfiles = runfiles,
        ),
    ]

tf_update_versions = rule(
    implementation = _tf_update_versions_impl,
    attrs = {
        "hcl_tool": attr.label(
            default = "@rules_tf2//go/hcl_tool",
            executable = True,
            cfg = "exec",
            doc = "The HCL tool binary",
        ),
        "lock_file": attr.label(
            allow_single_file = [".hcl"],
            doc = "Path to terraform.lock.hcl file",
        ),
        "tf_version": attr.string(
            default = ">= 1.0",
            doc = "Terraform version constraint",
        ),
    },
    executable = True,
    doc = "Updates Terraform version requirements in .tf files",
)

def _tf_parse_lock_impl(ctx):
    """Parse a terraform.lock.hcl file and output JSON"""

    # Declare output file
    output = ctx.actions.declare_file(ctx.label.name + "_providers.json")

    # Run the HCL tool
    ctx.actions.run(
        outputs = [output],
        inputs = [ctx.file.lock_file],
        executable = ctx.executable.hcl_tool,
        arguments = [
            "parse-lock",
            ctx.file.lock_file.path,
        ],
        mnemonic = "ParseLockFile",
        # Capture stdout to output file
        use_default_shell_env = False,
        env = {},
    )

    return [
        DefaultInfo(files = depset([output])),
        OutputGroupInfo(
            providers_json = depset([output]),
        ),
    ]

tf_parse_lock = rule(
    implementation = _tf_parse_lock_impl,
    attrs = {
        "lock_file": attr.label(
            allow_single_file = [".hcl"],
            mandatory = True,
            doc = "The terraform.lock.hcl file to parse",
        ),
        "hcl_tool": attr.label(
            default = "@rules_tf2//go/hcl_tool",
            executable = True,
            cfg = "exec",
            doc = "The HCL tool binary",
        ),
    },
    doc = "Parses a terraform.lock.hcl file and outputs provider information as JSON",
)

def _tf_read_versions_impl(ctx):
    """Read terraform version requirements from .tf files"""

    # Declare output file
    output = ctx.actions.declare_file(ctx.label.name + "_versions.json")

    # Create a temporary directory with all source files
    # For simplicity, we'll just run on the first source file's directory
    # In practice, you'd want to handle this better

    if not ctx.files.srcs:
        # No sources, output empty JSON
        ctx.actions.write(
            output = output,
            content = "{}",
        )
    else:
        # Get the directory of the first source file
        src_dir = ctx.files.srcs[0].dirname

        ctx.actions.run_shell(
            outputs = [output],
            inputs = ctx.files.srcs,
            command = """
                cd {src_dir}
                {hcl_tool} read-versions . > {output}
            """.format(
                src_dir = src_dir,
                hcl_tool = ctx.executable.hcl_tool.path,
                output = output.path,
            ),
            mnemonic = "ReadVersions",
        )

    return [
        DefaultInfo(files = depset([output])),
    ]

tf_read_versions = rule(
    implementation = _tf_read_versions_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".tf", ".tf.json"],
            doc = "Terraform source files to read versions from",
        ),
        "hcl_tool": attr.label(
            default = "@rules_tf2//go/hcl_tool",
            executable = True,
            cfg = "exec",
            doc = "The HCL tool binary",
        ),
    },
    doc = "Reads terraform version requirements from .tf files and outputs as JSON",
)
