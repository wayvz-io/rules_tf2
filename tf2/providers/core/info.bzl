"""Information providers for Terraform rules"""

TfModuleInfo = provider(
    doc = "Information about a Terraform module",
    fields = {
        "name": "Module name",
        "srcs": "Source files",
        "deps": "Module dependencies",
        "modules": "Nested modules in this module (for complex deployments)",
        "provider_configurations": "Provider configurations required by this module",
    },
)

TfProviderInfo = provider(
    doc = "Information about a Terraform provider",
    fields = {
        "name": "Provider name (e.g., aws)",
        "namespace": "Provider namespace (e.g., hashicorp)",
        "version": "Exact version string",
        "version_constraint": "Version constraint string (e.g., ~> 6.2)",
        "full_name": "Full provider name (e.g., hashicorp/aws)",
    },
)

TfProviderLibraryInfo = provider(
    doc = "Information about a provider library with exact versions",
    fields = {
        "providers": "Dict of provider name to provider struct",
        "mirror_dir": "File object for directory containing provider mirror",
    },
)

TfProviderConfigurationsInfo = provider(
    doc = "Information about provider configurations with version constraints",
    fields = {
        "providers": "Dict of provider name to version constraint",
        "tf_version_constraint": "Terraform version constraint",
        "versions_file": "Generated versions configuration file",
    },
)

# TfStackInfo removed - functionality merged into TfModuleInfo

TfProviderMirrorInfo = provider(
    doc = "Information about a single provider mirror",
    fields = {
        "provider": "Full provider name (e.g., hashicorp/aws)",
        "version": "Exact version string",
        "provider_name": "Provider name (e.g., aws)",
        "namespace": "Provider namespace (e.g., hashicorp)",
        "mirror_dir": "Directory containing the mirrored provider",
    },
)

TfProviderCacheInfo = provider(
    doc = "Information about a shared provider cache",
    fields = {
        "cache_dir": "Directory containing all cached providers",
        "providers": "Dictionary of provider names to list of versions",
        "lock_file": "The complete .terraform.lock.hcl file with all provider hashes",
    },
)

TfProviderAliasInfo = provider(
    doc = "Information about a provider alias pointing to cached provider",
    fields = {
        "provider": "Full provider name (e.g., hashicorp/aws)",
        "version": "Exact version string",
        "provider_name": "Provider name (e.g., aws)",
        "namespace": "Provider namespace (e.g., hashicorp)",
        "cache": "Reference to the provider cache",
        "cache_dir": "Directory containing the cached provider",
    },
)
