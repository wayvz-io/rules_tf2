"""Module metadata rule that provides information about external Terraform modules.

External modules are simple file providers - they don't go through the full
tf_module test machinery (lint, validate, organization checks). They just
provide files that get staged into ./modules/{alias}/.
"""

load("//tf2/modules/core:info.bzl", "TfExternalModuleInfo")

def _parse_source(source, source_type):
    """Parse source string into components based on type.

    Args:
        source: Module source string
        source_type: One of 'registry', 'git', or 'private'

    Returns:
        Tuple of (namespace, name, provider_name)
    """
    if source_type == "registry":
        # Format: namespace/name/provider
        parts = source.split("/")
        if len(parts) == 3:
            return parts[0], parts[1], parts[2]
        fail("Registry source must be 'namespace/name/provider', got: " + source)

    elif source_type == "private":
        # Format: hostname/org/name/provider
        parts = source.split("/")
        if len(parts) == 4:
            return parts[1], parts[2], parts[3]  # org, name, provider
        fail("Private source must be 'hostname/org/name/provider', got: " + source)

    elif source_type == "git":
        # Format: github.com/owner/repo or git::https://...
        if source.startswith("github.com/"):
            parts = source.split("/")
            if len(parts) >= 3:
                return parts[1], parts[2], ""  # owner, repo, no provider
        elif source.startswith("git::"):
            # Extract owner/repo from URL
            url = source[5:]  # Remove git:: prefix
            parts = url.replace(".git", "").split("/")
            if len(parts) >= 2:
                return parts[-2], parts[-1], ""
        fail("Git source must be 'github.com/owner/repo' or 'git::https://...', got: " + source)

    fail("Unknown source_type: " + source_type)

def _module_metadata_impl(ctx):
    """Implementation of module_metadata rule."""
    source = ctx.attr.source
    source_type = ctx.attr.source_type
    version = ctx.attr.version

    # Parse source to get components
    namespace, name, provider_name = _parse_source(source, source_type)

    # Get files from the files attribute (label to module filegroup)
    files_target = ctx.attr.files
    module_files = files_target[DefaultInfo].files if files_target else depset()

    # Generate source URL for Terraform config
    if source_type == "registry":
        source_url = source  # e.g., terraform-aws-modules/vpc/aws
    elif source_type == "private":
        source_url = source  # e.g., app.terraform.io/my-org/my-module/aws
    else:
        # For git, keep original source
        source_url = source

    # Note: The alias is determined by ctx.label.name, which is set by the
    # tf_modules extension when creating these targets. The extension applies
    # the aliasing scheme (e.g., vpc_aws_5 for registry, owner_repo_v1_0_0 for git).

    return [
        TfExternalModuleInfo(
            name = name,
            namespace = namespace,
            provider_name = provider_name,
            version = version,
            source_type = source_type,
            source_url = source_url,
            alias = ctx.label.name,  # Use the target name as alias
            files = module_files,
        ),
        DefaultInfo(
            files = module_files,
            runfiles = ctx.runfiles(transitive_files = module_files),
        ),
    ]

module_metadata = rule(
    implementation = _module_metadata_impl,
    attrs = {
        "source": attr.string(
            doc = "Module source (e.g., 'terraform-aws-modules/vpc/aws' or 'github.com/owner/repo')",
            mandatory = True,
        ),
        "source_type": attr.string(
            doc = "Source type: 'registry', 'git', or 'private'",
            mandatory = True,
            values = ["registry", "git", "private"],
        ),
        "version": attr.string(
            doc = "Module version or git ref",
            mandatory = True,
        ),
        "files": attr.label(
            doc = "Label to filegroup containing module files",
            allow_files = True,
        ),
    },
    doc = """Provides metadata about an external Terraform module.

    This rule provides module information that can be used to integrate
    external modules into tf_module targets. The module files are downloaded
    by the module extension during repository phase.

    Example:
        module_metadata(
            name = "vpc_aws_5",
            source = "terraform-aws-modules/vpc/aws",
            source_type = "registry",
            version = "5.0.0",
            files = ":vpc_aws_5_files",
        )
    """,
)
