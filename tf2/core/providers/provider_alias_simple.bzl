"""Simple provider alias rule that doesn't require a cache"""

load("//tf2/core/rules:info.bzl", "TfProviderAliasInfo")

def _provider_alias_simple_impl(ctx):
    """Implementation of provider_alias_simple rule - just metadata"""
    
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
    
    # Create a dummy directory to satisfy the runfiles requirement
    dummy_dir = ctx.actions.declare_directory(ctx.label.name + "_providers")
    ctx.actions.run_shell(
        outputs = [dummy_dir],
        command = "mkdir -p {}".format(dummy_dir.path),
        mnemonic = "ProviderAlias",
    )
    
    return [
        TfProviderAliasInfo(
            provider = ctx.attr.provider,
            version = ctx.attr.version,
            provider_name = provider_name,
            namespace = namespace,
            cache = None,  # No cache dependency
            cache_dir = dummy_dir,  # Use dummy directory
        ),
        DefaultInfo(
            files = depset([dummy_dir]),
            runfiles = ctx.runfiles(files = [dummy_dir]),
        ),
    ]

provider_alias_simple = rule(
    implementation = _provider_alias_simple_impl,
    attrs = {
        "provider": attr.string(
            doc = "Provider in format 'namespace/name' (e.g., 'hashicorp/aws')",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "Exact semver version (e.g., '6.2.0')",
            mandatory = True,
        ),
    },
    doc = """Creates a simple alias to a provider version without downloading.
    
    This rule just provides metadata about a provider version. The actual
    provider binary will be fetched individually at build time when needed.
    
    Example:
        provider_alias_simple(
            name = "aws_6",
            provider = "hashicorp/aws",
            version = "6.12.0",
        )
    """,
)