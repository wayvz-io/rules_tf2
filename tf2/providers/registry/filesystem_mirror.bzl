"""BUILD rule for creating a Terraform provider filesystem mirror"""

def _filesystem_mirror_impl(ctx):
    """Implementation of filesystem_mirror rule.

    This rule aggregates individual provider downloads and creates a filesystem
    mirror structure that Terraform can use with the filesystem_mirror configuration.
    """

    # Create the output directory for the mirror
    mirror_dir = ctx.actions.declare_directory(ctx.label.name)

    # Collect all provider files and build inline command
    provider_files = []
    command_lines = [
        "set -euo pipefail",
        "MIRROR_DIR=\"{}\"".format(mirror_dir.path),
        "mkdir -p \"$MIRROR_DIR\"",
        "",
    ]

    # Process each provider dependency
    for provider_dep in ctx.attr.providers:
        # Get the files from the provider download
        for file in provider_dep.files.to_list():
            provider_files.append(file)

            # Parse provider metadata from the target name if available
            # Expected format: download_NAME_VERSION_PLATFORM
            target_name = provider_dep.label.name
            if target_name.startswith("download_"):
                parts = target_name[9:].rsplit("_", 2)  # Remove "download_" prefix
                if len(parts) == 3:
                    name_version = parts[0]
                    os_name = parts[1]
                    arch = parts[2]
                    platform = "{}_{}".format(os_name, arch)

                    # Try to extract provider name and version
                    # This is a heuristic - ideally we'd have metadata
                    if "_" in name_version:
                        name_parts = name_version.rsplit("_", 3)
                        if len(name_parts) >= 4:
                            # Reconstruct version from last 3 parts (major_minor_patch)
                            version = "{}.{}.{}".format(name_parts[-3], name_parts[-2], name_parts[-1])
                            name = "_".join(name_parts[:-3])
                        else:
                            # Fallback
                            name = name_version
                            version = "unknown"
                    else:
                        name = name_version
                        version = "unknown"

                    # Guess namespace - this should be provided as metadata
                    if name in ["aws", "azurerm", "null", "random", "local", "archive", "time", "tls", "helm", "kubernetes", "tfe"]:
                        namespace = "hashicorp"
                    elif name == "panos":
                        namespace = "paloaltonetworks"
                    elif name == "onepassword":
                        namespace = "1password"
                    elif name == "flux":
                        namespace = "fluxcd"
                    elif name == "cloudflare":
                        namespace = "cloudflare"
                    else:
                        namespace = "unknown"

                    # Create the target directory structure
                    target_path = "registry.terraform.io/{}/{}/{}/{}".format(
                        namespace,
                        name,
                        version,
                        platform,
                    )

                    command_lines.extend([
                        "# Provider: {}/{}@{} for {}".format(namespace, name, version, platform),
                        "mkdir -p \"$MIRROR_DIR/{}\"".format(target_path),
                        "if [ -d '{}' ]; then".format(file.path),
                        "    cp -r {}/* \"$MIRROR_DIR/{}/\" 2>/dev/null || true".format(file.path, target_path),
                        "fi",
                        "",
                    ])

    # Execute inline command (no script file or shebang needed)
    ctx.actions.run_shell(
        outputs = [mirror_dir],
        inputs = provider_files,
        command = "\n".join(command_lines),
        mnemonic = "FilesystemMirror",
        progress_message = "Creating filesystem mirror with {} providers".format(len(ctx.attr.providers)),
        use_default_shell_env = True,  # This gives us access to system tools
    )

    return [
        DefaultInfo(
            files = depset([mirror_dir]),
            runfiles = ctx.runfiles(files = [mirror_dir]),
        ),
    ]

filesystem_mirror = rule(
    implementation = _filesystem_mirror_impl,
    attrs = {
        "providers": attr.label_list(
            doc = "List of provider_download targets to include in the mirror",
            allow_files = True,
        ),
    },
    doc = """Creates a filesystem mirror for Terraform providers.
    
    This rule aggregates individual provider downloads and creates the directory
    structure expected by Terraform's filesystem_mirror configuration.
    
    Example:
        filesystem_mirror(
            name = "my_mirror",
            providers = [
                ":download_aws_6_12_0_linux_amd64",
                ":download_azurerm_4_43_0_linux_amd64",
            ],
        )
    
    The output will be a directory structure like:
        registry.terraform.io/
            hashicorp/
                aws/
                    6.12.0/
                        linux_amd64/
                            terraform-provider-aws_v6.12.0_x5
    """,
)
