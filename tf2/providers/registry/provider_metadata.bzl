"""Provider metadata rule that provides version information without downloads"""

load("//tf2/providers/core:info.bzl", "TfProviderAliasInfo")
load("//tf2/tools/runners:sh_toolchain.bzl", "SH_TOOLCHAIN_TYPE", "run_shell")

def _provider_metadata_impl(ctx):
    """Implementation of provider_metadata rule - just metadata"""

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
    run_shell(
        ctx,
        outputs = [dummy_dir],
        inputs = [],
        command = "mkdir -p {}".format(dummy_dir.path),
        mnemonic = "ProviderMetadata",
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

provider_metadata = rule(
    implementation = _provider_metadata_impl,
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
    toolchains = [SH_TOOLCHAIN_TYPE],
    doc = """Provides metadata about a provider version without downloading.

    This rule provides version information that can be used to generate
    terraform.tf configurations and tflint configs. The actual provider
    binary will be fetched individually at build time when needed.

    Example:
        provider_metadata(
            name = "aws_6",
            provider = "hashicorp/aws",
            version = "6.12.0",
        )
    """,
)
