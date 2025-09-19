"""Provider alias rule for referencing cached providers"""

load("//tf2/core/rules:info.bzl", "TfProviderAliasInfo", "TfProviderCacheInfo")

def _provider_alias_impl(ctx):
    """Implementation of provider_alias rule - references a cached provider"""
    
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
    
    # Get cache info
    if TfProviderCacheInfo not in ctx.attr.cache:
        fail("cache attribute must reference a provider_cache rule")
    
    cache_info = ctx.attr.cache[TfProviderCacheInfo]
    
    # Verify the provider and version exist in the cache
    if ctx.attr.provider not in cache_info.providers:
        fail("Provider {} not found in cache".format(ctx.attr.provider))
    
    if ctx.attr.version not in cache_info.providers[ctx.attr.provider]:
        fail("Version {} not found for provider {} in cache".format(
            ctx.attr.version,
            ctx.attr.provider,
        ))
    
    return [
        TfProviderAliasInfo(
            provider = ctx.attr.provider,
            version = ctx.attr.version,
            provider_name = provider_name,
            namespace = namespace,
            cache = ctx.attr.cache,
            cache_dir = cache_info.cache_dir,
        ),
        DefaultInfo(
            files = depset([cache_info.cache_dir]),
            runfiles = ctx.runfiles(files = [cache_info.cache_dir]),
        ),
    ]

provider_alias = rule(
    implementation = _provider_alias_impl,
    attrs = {
        "provider": attr.string(
            doc = "Provider in format 'namespace/name' (e.g., 'hashicorp/aws')",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "Exact semver version (e.g., '6.2.0')",
            mandatory = True,
        ),
        "cache": attr.label(
            doc = "Reference to the provider_cache containing this provider",
            providers = [TfProviderCacheInfo],
            mandatory = True,
        ),
    },
    doc = """Creates an alias to a specific provider version in the cache.
    
    This rule references a provider that has already been downloaded by a
    provider_cache rule. It provides a lightweight way to reference specific
    provider versions without re-downloading.
    
    Example:
        provider_alias(
            name = "aws_6",
            provider = "hashicorp/aws",
            version = "6.2.0",
            cache = "//iac/providers:shared_cache",
        )
    """,
)