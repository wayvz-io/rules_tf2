"""Rule to create tools tar layer for TFC agent images."""

load("@rules_pkg//pkg:tar.bzl", "pkg_tar")
load("//tf2/tools/runners:sh_toolchain.bzl", "SH_TOOLCHAIN_TYPE", "run_shell")

def _tools_layer_staging_impl(ctx):
    """Stage tool binaries for tar packaging.

    Copies the terraform binary to a staging directory ready for tar packaging.
    """
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.attr.name))

    # Collect all tool files
    tool_files = []
    copy_commands = ["mkdir -p '{}'".format(staging_dir.path)]

    if ctx.attr.terraform:
        for f in ctx.files.terraform:
            tool_files.append(f)
            # Copy and rename to just 'terraform'
            copy_commands.append("cp -L '{}' '{}/terraform'".format(f.path, staging_dir.path))
            copy_commands.append("chmod +x '{}/terraform'".format(staging_dir.path))
            break  # Only take first file (the binary)

    run_shell(
        ctx,
        inputs = tool_files,
        outputs = [staging_dir],
        command = "\n".join(copy_commands),
        mnemonic = "StageTools",
        progress_message = "Staging tools for %s" % ctx.label,
    )

    return [DefaultInfo(files = depset([staging_dir]))]

tools_layer_staging = rule(
    implementation = _tools_layer_staging_impl,
    attrs = {
        "terraform": attr.label(
            allow_files = True,
            doc = "Terraform binary label",
        ),
    },
    toolchains = [SH_TOOLCHAIN_TYPE],
    doc = "Stages tool binaries for tar packaging.",
)

def agent_tools_layer(
        name,
        terraform = None,
        package_dir = "/usr/local/bin",
        visibility = None):
    """Create a tar layer containing tool binaries for OCI image.

    This macro stages the terraform binary and creates a tar archive suitable
    for use as an OCI image layer.

    Args:
        name: Target name
        terraform: Terraform binary label (e.g., @terraform_tool//:bin)
        package_dir: Destination path in container (default: /usr/local/bin)
        visibility: Target visibility
    """
    # Stage tools with correct names
    tools_layer_staging(
        name = name + "_staging",
        terraform = terraform,
    )

    # Create tar archive
    pkg_tar(
        name = name,
        srcs = [":" + name + "_staging"],
        package_dir = package_dir,
        strip_prefix = name + "_staging",
        visibility = visibility,
    )

def _config_layer_staging_impl(ctx):
    """Stage configuration files for tar packaging."""
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.attr.name))

    config_files = ctx.files.terraformrc
    copy_commands = ["mkdir -p '{}'".format(staging_dir.path)]

    for f in config_files:
        # Copy as .terraformrc
        copy_commands.append("cp -L '{}' '{}/.terraformrc'".format(f.path, staging_dir.path))
        break

    run_shell(
        ctx,
        inputs = config_files,
        outputs = [staging_dir],
        command = "\n".join(copy_commands),
        mnemonic = "StageConfig",
        progress_message = "Staging config for %s" % ctx.label,
    )

    return [DefaultInfo(files = depset([staging_dir]))]

config_layer_staging = rule(
    implementation = _config_layer_staging_impl,
    attrs = {
        "terraformrc": attr.label(
            mandatory = True,
            allow_files = True,
            doc = "terraformrc file label",
        ),
    },
    toolchains = [SH_TOOLCHAIN_TYPE],
    doc = "Stages configuration files for tar packaging.",
)

def agent_config_layer(
        name,
        terraformrc,
        package_dir = "/etc/terraform",
        visibility = None):
    """Create a tar layer containing config files for OCI image.

    This macro stages the .terraformrc file and creates a tar archive
    suitable for use as an OCI image layer.

    Args:
        name: Target name
        terraformrc: terraformrc file label
        package_dir: Destination path in container (default: /etc/terraform)
        visibility: Target visibility
    """
    # Stage config files
    config_layer_staging(
        name = name + "_staging",
        terraformrc = terraformrc,
    )

    # Create tar archive
    pkg_tar(
        name = name,
        srcs = [":" + name + "_staging"],
        package_dir = package_dir,
        strip_prefix = name + "_staging",
        visibility = visibility,
    )
