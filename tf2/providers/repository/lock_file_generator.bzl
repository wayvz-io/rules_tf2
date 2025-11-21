"""Rule for generating Terraform lock files from stored provider hashes"""

def _tf_lock_file_generator_impl(ctx):
    """Generate a .terraform.lock.hcl file from stored provider lock data"""

    # Output lock file
    output_lock = ctx.actions.declare_file(".terraform.lock.hcl")

    # Use hcl_tool to generate the lock file from JSON
    # provider_locks.json is already in the format expected by hcl_tool
    args = ctx.actions.args()
    args.add("extract-module-lock")
    args.add("--versions", ctx.file.versions_file)
    args.add("--output", output_lock)
    args.add(ctx.file.provider_locks)

    ctx.actions.run(
        outputs = [output_lock],
        inputs = [ctx.file.provider_locks, ctx.file.versions_file],
        executable = ctx.executable._hcl_tool,
        arguments = [args],
        mnemonic = "GenerateLockFile",
        progress_message = "Generating Terraform lock file from stored hashes",
    )

    return [
        DefaultInfo(
            files = depset([output_lock]),
        ),
    ]

tf_lock_file_generator = rule(
    implementation = _tf_lock_file_generator_impl,
    attrs = {
        "provider_locks": attr.label(
            doc = "The provider_locks.json file containing all provider hashes",
            allow_single_file = [".json"],
            mandatory = True,
        ),
        "versions_file": attr.label(
            doc = "The provider specifications from Bazel module system",
            allow_single_file = [".json"],
            mandatory = True,
        ),
        "_hcl_tool": attr.label(
            default = "@rules_tf2//hcl_tool",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = """Generates a .terraform.lock.hcl file from stored provider lock data.

    This rule reads the provider specifications to determine which providers are needed,
    then looks up the corresponding hashes from the centralized provider_locks.json
    file and generates a proper .terraform.lock.hcl file.

    This avoids the need to regenerate lock files on each machine, as the hashes
    are already stored centrally.

    Example:
        tf_lock_file_generator(
            name = "stack_lock",
            provider_locks = "@tf_provider_registry//:provider_locks.json",
            versions_file = ":versions.tf.json",
        )
    """,
)
