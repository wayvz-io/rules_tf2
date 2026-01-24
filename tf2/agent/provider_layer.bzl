"""Rule to create provider tar layer for TFC agent images."""

load("@rules_pkg//pkg:tar.bzl", "pkg_tar")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")
load("//tf2/tools/runners:sh_toolchain.bzl", "SH_TOOLCHAIN_TYPE", "run_shell")

def _provider_layer_staging_impl(ctx):
    """Stage providers for tar packaging with correct structure.

    Creates a staging directory with the filesystem mirror structure:
    registry.terraform.io/hashicorp/aws/terraform-provider-aws_6.26.0_linux_amd64.zip

    The provider_mirror input already has this structure, so we just symlink it.
    """
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.attr.name))

    # Collect all provider files from the mirror
    provider_files = ctx.files.provider_mirror

    # Create staging directory structure
    commands = ["mkdir -p '{}'".format(staging_dir.path)]

    for f in provider_files:
        # The provider_mirror already has the correct structure
        # Files are like: mirror_linux_amd64/registry.terraform.io/hashicorp/aws/terraform-provider-aws_...
        # We need to strip the leading mirror name and keep the rest

        # Find the registry.terraform.io part and preserve from there
        src_path = f.path
        if "registry.terraform.io" in src_path:
            idx = src_path.find("registry.terraform.io")
            rel_path = src_path[idx:]
            dest_dir = staging_dir.path + "/" + rel_path.rsplit("/", 1)[0]
            commands.append("mkdir -p '{}'".format(dest_dir))
            commands.append("cp -L '{}' '{}/{}'".format(f.path, staging_dir.path, rel_path))
        else:
            # Skip non-provider files (like .empty marker)
            continue

    run_shell(
        ctx,
        inputs = provider_files,
        outputs = [staging_dir],
        command = "\n".join(commands) if len(commands) > 1 else "mkdir -p '{}'".format(staging_dir.path),
        mnemonic = "StageProviders",
        progress_message = "Staging providers for %s" % ctx.label,
    )

    return [DefaultInfo(files = depset([staging_dir]))]

provider_layer_staging = rule(
    implementation = _provider_layer_staging_impl,
    attrs = {
        "provider_mirror": attr.label(
            mandatory = True,
            allow_files = True,
            doc = "Provider mirror label (e.g., @tf_provider_registry//:mirror_linux_amd64)",
        ),
    },
    toolchains = [SH_TOOLCHAIN_TYPE],
    doc = "Stages provider files for tar packaging.",
)

def _extract_module_providers_impl(ctx):
    """Extract provider aliases from a tf_module's TfModuleInfo."""
    module_info = ctx.attr.module[TfModuleInfo]

    # Get provider configurations
    provider_configs = module_info.provider_configurations
    if not provider_configs:
        fail("Module {} does not have provider_configurations".format(ctx.attr.module.label))

    # Output the provider aliases as JSON
    out = ctx.actions.declare_file("{}_providers.json".format(ctx.attr.name))

    # The provider_configurations contains TfProviderConfigurationsInfo
    # We need to extract the provider aliases
    # For now, output the configured providers
    ctx.actions.write(
        output = out,
        content = "{}",  # Placeholder - actual implementation needs to introspect providers
    )

    return [DefaultInfo(files = depset([out]))]

extract_module_providers = rule(
    implementation = _extract_module_providers_impl,
    attrs = {
        "module": attr.label(
            mandatory = True,
            providers = [TfModuleInfo],
            doc = "tf_module to extract providers from",
        ),
    },
    doc = "Extracts provider aliases from a tf_module for filtering the provider mirror.",
)

def agent_provider_layer(
        name,
        provider_mirror,
        package_dir = "/terraform/providers",
        visibility = None):
    """Create a tar layer containing provider files for OCI image.

    This macro stages the provider mirror files and creates a tar archive
    suitable for use as an OCI image layer.

    Args:
        name: Target name
        provider_mirror: Provider mirror label (e.g., @tf_provider_registry//:mirror_linux_amd64)
        package_dir: Destination path in container (default: /terraform/providers)
        visibility: Target visibility
    """
    # Stage providers with correct structure
    provider_layer_staging(
        name = name + "_staging",
        provider_mirror = provider_mirror,
    )

    # Create tar archive
    pkg_tar(
        name = name,
        srcs = [":" + name + "_staging"],
        package_dir = package_dir,
        strip_prefix = name + "_staging",
        visibility = visibility,
    )
