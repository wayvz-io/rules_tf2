"""Provider alias rule for referencing providers from the registry"""

load("//tf2/core/rules:info.bzl", "TfProviderAliasInfo")

def _provider_registry_alias_impl(ctx):
    """Implementation of provider_registry_alias rule"""
    
    # Validate version is semver (basic check)
    version_parts = ctx.attr.version.split(".")
    if len(version_parts) != 3:
        fail("Version must be in semver format (X.Y.Z), got: " + ctx.attr.version)
    
    for part in version_parts:
        if not part.isdigit():
            fail("Version components must be numeric, got: " + ctx.attr.version)
    
    # Extract provider name from namespace/name format
    provider_parts = ctx.attr.provider.split("/")
    if len(provider_parts) != 2:
        fail("Provider must be in format 'namespace/name', got: " + ctx.attr.provider)
    
    namespace, provider_name = provider_parts
    
    # For registry-based providers, we just need to reference the registry directory
    # The aggregation will handle copying the specific provider files
    
    # Create a marker file that identifies this provider
    marker = ctx.actions.declare_file(ctx.label.name + "_provider.json")
    ctx.actions.write(
        output = marker,
        content = json.encode({
            "provider": ctx.attr.provider,
            "version": ctx.attr.version,
            "namespace": namespace,
            "provider_name": provider_name,
            "registry": str(ctx.attr.registry_files.label),
        }),
    )
    
    return [
        TfProviderAliasInfo(
            provider = ctx.attr.provider,
            version = ctx.attr.version,
            provider_name = provider_name,
            namespace = namespace,
            cache = None,  # No cache reference for registry-based providers
            cache_dir = ctx.files.registry_files[0] if ctx.files.registry_files else marker,  # Use the registry directory
        ),
        DefaultInfo(
            files = depset([marker] + ctx.files.registry_files),
            runfiles = ctx.runfiles(files = [marker] + ctx.files.registry_files),
        ),
    ]

provider_registry_alias = rule(
    implementation = _provider_registry_alias_impl,
    attrs = {
        "provider": attr.string(
            doc = "Provider in format 'namespace/name' (e.g., 'hashicorp/aws')",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "Exact semver version (e.g., '6.2.0')",
            mandatory = True,
        ),
        "registry_files": attr.label(
            doc = "Reference to the provider registry filegroup",
            mandatory = True,
            allow_files = True,
        ),
    },
    doc = """Creates an alias to a specific provider version from the registry.
    
    This rule references a provider that has been downloaded by the
    terraform_provider_registry repository rule during the loading phase.
    
    Example:
        provider_registry_alias(
            name = "aws_6",
            provider = "hashicorp/aws",
            version = "6.2.0",
            registry_files = "@tf_provider_registry//:all_providers",
        )
    """,
)