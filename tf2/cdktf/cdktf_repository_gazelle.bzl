"""Repository rule for generating CDKTF bindings with proper Gazelle integration - cleaned up"""

load("//tf2/cdktf:cdktf_common.bzl", "create_build_bazel", "create_cdktf_json", "create_go_mod", "get_environment_for_cdktf")

def _cdktf_bindings_repository_gazelle_impl(repository_ctx):
    """Implementation of cdktf_bindings_repository_gazelle rule"""

    # Get attributes
    provider_name = repository_ctx.attr.provider_name
    provider_source = repository_ctx.attr.provider_source
    provider_version = repository_ctx.attr.provider_version
    major_version = provider_version.split(".")[0]

    # Create cdktf.json configuration
    repository_ctx.file("cdktf.json", create_cdktf_json(
        provider_name,
        provider_source,
        provider_version,
        major_version,
    ))

    # Create go.mod with proper import path
    repository_ctx.file("go.mod", create_go_mod(provider_name, major_version))

    # Copy the generation script
    script_label = Label("//tf2/cdktf/scripts:generate_cdktf.sh")
    repository_ctx.symlink(script_label, "generate_cdktf.sh")
    repository_ctx.execute(["chmod", "+x", "generate_cdktf.sh"])

    # Run generation script
    result = repository_ctx.execute(
        ["./generate_cdktf.sh", provider_name, provider_source, provider_version],
        timeout = 600,
        environment = get_environment_for_cdktf(repository_ctx),
    )

    if result.return_code != 0:
        # Generation failed but continue anyway
        # Don't fail here, let's see if files were generated anyway
        pass
    else:
        # Generation completed successfully
        pass

    # Fix import paths in generated Go files
    fix_script_label = Label("//tf2/cdktf/scripts:fix_imports.sh")
    repository_ctx.symlink(fix_script_label, "fix_imports.sh")
    repository_ctx.execute(["chmod", "+x", "fix_imports.sh"])

    fix_imports_result = repository_ctx.execute(
        ["./fix_imports.sh", provider_name, major_version],
        timeout = 300,
    )

    if fix_imports_result.return_code != 0:
        # Warning: Could not fix import paths
        pass

    # Clean up generation scripts
    repository_ctx.delete("generate_cdktf.sh")
    repository_ctx.delete("fix_imports.sh")
    repository_ctx.delete("cdktf.json")

    # Create a BUILD.bazel file that declares gazelle and dependencies
    repository_ctx.file("BUILD.bazel", create_build_bazel(
        provider_name,
        provider_version,
        major_version,
    ))

    # Create a simple WORKSPACE file (needed for gazelle to work properly)
    repository_ctx.file("WORKSPACE", "")

    # Now run gazelle to generate all the BUILD files
    # Running gazelle to generate BUILD files

    # Run gazelle directly - assumes we're already in the nix environment
    gazelle_env = get_environment_for_cdktf(repository_ctx)

    gazelle_result = repository_ctx.execute(
        ["sh", "-c", """
if command -v gazelle >/dev/null 2>&1; then
    gazelle -go_prefix cdktf_{provider_name}_{major_version} -mode fix -build_file_name BUILD.bazel
else
    echo "Warning: Gazelle not found in PATH"
    exit 0
fi
""".format(
            provider_name = provider_name,
            major_version = major_version,
        )],
        timeout = 60,
        environment = gazelle_env if gazelle_env.get("PATH") else None,
    )

    if gazelle_result.return_code != 0:
        # Gazelle failed but continue
        pass

    # Fix the load statements in generated BUILD files
    # Gazelle might generate with @io_bazel_rules_go but we use @rules_go
    fix_result = repository_ctx.execute(
        ["sh", "-c", """
find . -name "BUILD.bazel" -type f -exec sed -i.bak 's/@io_bazel_rules_go/@rules_go/g' {} \\;
find . -name "*.bak" -type f -delete
"""],
        timeout = 30,
    )

    if fix_result.return_code != 0:
        # Warning: Could not fix load statements
        pass

    # Clean up temporary files but keep go.mod and go.sum
    repository_ctx.delete("WORKSPACE")

cdktf_bindings_repository_gazelle = repository_rule(
    implementation = _cdktf_bindings_repository_gazelle_impl,
    attrs = {
        "provider_name": attr.string(
            mandatory = True,
            doc = "Name of the Terraform provider",
        ),
        "provider_source": attr.string(
            mandatory = True,
            doc = "Source of the Terraform provider (e.g., hashicorp/aws)",
        ),
        "provider_version": attr.string(
            mandatory = True,
            doc = "Version of the Terraform provider",
        ),
    },
    doc = """Repository rule that generates CDKTF bindings with proper Gazelle integration.

    Example:
        cdktf_bindings_repository_gazelle(
            name = "cdktf_aws_6",
            provider_name = "aws",
            provider_source = "hashicorp/aws",
            provider_version = "6.2.0",
        )
    """,
)
