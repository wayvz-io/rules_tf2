"""BUILD rules for creating a Terraform provider filesystem mirror at build time"""

def _provider_mirror_impl(ctx):
    """Implementation of provider_mirror rule.

    This rule aggregates individual provider binaries and creates a filesystem
    mirror structure that Terraform can use with the filesystem_mirror configuration.
    """

    # Create the output directory for the mirror
    mirror_dir = ctx.actions.declare_directory(ctx.label.name + "_mirror")

    # Collect all provider files and their target paths
    provider_inputs = []
    provider_commands = []

    for provider_spec in ctx.attr.providers:
        # Parse provider spec: "hashicorp/aws:6.12.0"
        source, version = provider_spec.split(":")
        namespace, name = source.split("/")

        # Get the current platform
        # In a real implementation, we'd detect this properly
        # For now, assume linux_amd64 as default
        platform = ctx.attr.platform or "linux_amd64"
        os_name, arch = platform.split("_")

        # Repository name from module extension
        repo_name = "@tf_provider_{}_{}_{}_{}//:binary".format(
            name,
            version.replace(".", "_"),
            os_name,
            arch,
        )

        # Get the provider files from the repository
        # This assumes the provider_binary repository exports a :binary target
        provider_target = ctx.attr.provider_binaries.get(repo_name)
        if provider_target:
            for file in provider_target.files.to_list():
                provider_inputs.append(file)

                # Target path in filesystem mirror
                target_path = "registry.terraform.io/{}/{}/{}/{}".format(
                    namespace,
                    name,
                    version,
                    platform,
                )

                # Add command to create symlink
                provider_commands.append(
                    "mkdir -p {}/{}".format(mirror_dir.path, target_path),
                )
                provider_commands.append(
                    "ln -sf {} {}/{}/{}".format(
                        file.path,
                        mirror_dir.path,
                        target_path,
                        file.basename,
                    ),
                )

    # Create the mirror structure
    script_content = "#!/usr/bin/env bash\nset -euo pipefail\n\n"
    script_content += "# Create filesystem mirror for Terraform providers\n"
    script_content += "\n".join(provider_commands)
    script_content += "\n\necho 'Provider mirror created at: {}'\n".format(mirror_dir.path)

    # Create script file
    script = ctx.actions.declare_file(ctx.label.name + "_setup.sh")
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Run the script to create the mirror
    ctx.actions.run_shell(
        inputs = provider_inputs,
        outputs = [mirror_dir],
        command = script.path,
        tools = [script],
        mnemonic = "ProviderMirror",
        progress_message = "Creating provider mirror for {}".format(ctx.label),
    )

    return [
        DefaultInfo(
            files = depset([mirror_dir]),
            runfiles = ctx.runfiles(files = [mirror_dir] + provider_inputs),
        ),
    ]

provider_mirror = rule(
    implementation = _provider_mirror_impl,
    attrs = {
        "providers": attr.string_list(
            doc = "List of provider specs in format 'namespace/name:version'",
            mandatory = True,
        ),
        "provider_binaries": attr.label_keyed_string_dict(
            doc = "Map of provider binary targets to their specs",
            allow_files = True,
        ),
        "platform": attr.string(
            doc = "Platform to use (e.g., linux_amd64, darwin_arm64)",
            default = "linux_amd64",
        ),
    },
)

def collect_required_providers(_):
    """Analyze Terraform source files to determine required providers.

    This is a simplified version - in reality, we'd parse the terraform
    configuration to extract provider requirements.

    Args:
        _: Unused parameter (would be list of Terraform source files)

    Returns:
        List of provider specs required by the configuration
    """

    # For now, return a hardcoded list
    # In a real implementation, this would parse versions.tf.json or similar
    return []
