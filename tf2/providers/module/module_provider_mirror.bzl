"""Per-module provider mirror macro for efficient provider caching.

This macro creates a provider mirror that only includes the providers
a specific module needs, rather than all providers in the global registry.

RBE Compatibility:
    This macro uses select() with platform config settings to choose the
    correct provider mirror for the target platform. Each per-platform
    mirror has target_compatible_with constraints that ensure it's only
    built for the correct platform. When building remotely with RBE,
    Bazel's platform configuration determines which mirror is selected.
"""

load("//tf2/providers/registry:filesystem_mirror.bzl", "filesystem_mirror")
load("@tf_provider_registry//:provider_locks.bzl", "PROVIDER_ALIASES")

# Platforms supported for provider downloads
_PLATFORMS = ["linux_amd64", "linux_arm64", "darwin_amd64", "darwin_arm64"]

# Platform constraint mappings for target_compatible_with
_PLATFORM_CONSTRAINTS = {
    "linux_amd64": ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    "linux_arm64": ["@platforms//os:linux", "@platforms//cpu:aarch64"],
    "darwin_amd64": ["@platforms//os:macos", "@platforms//cpu:x86_64"],
    "darwin_arm64": ["@platforms//os:macos", "@platforms//cpu:aarch64"],
}

def _normalize_provider_name(name):
    """Normalize provider name for use in target names.

    Converts names like 'hashicorp/aws' to 'aws' and ensures
    underscores are used instead of hyphens.
    """
    if "/" in name:
        name = name.split("/")[-1]
    return name.replace("-", "_")

def _version_to_underscore(version):
    """Convert semver to underscore format (e.g., '6.14.0' -> '6_14_0')."""
    return version.replace(".", "_")

def tf_module_provider_mirror(
        name,
        providers,
        visibility = None,
        testonly = None):
    """Creates a per-module provider mirror with only the needed providers.

    This macro creates platform-specific provider mirrors that only include
    the providers specified, reducing unnecessary dependencies and improving
    cache efficiency.

    Args:
        name: Name of the provider mirror target
        providers: List of provider alias names (e.g., ["aws_6", "random_3"])
                   These must match aliases defined in the tf_provider_registry.
        visibility: Visibility of the generated targets
        testonly: Whether targets are test-only

    Example:
        tf_module_provider_mirror(
            name = "my_module_providers",
            providers = ["aws_6", "random_3"],
        )

        # Use in tf_validate_test:
        tf_validate_test(
            name = "my_module_validate_test",
            srcs = [":my_module_sources"],
            provider_registry = ":my_module_providers",
        )
    """

    # Build download target lists for each platform
    platform_providers = {}
    for platform in _PLATFORMS:
        platform_providers[platform] = []

    # For each provider alias, look up version and compute download targets
    for provider_alias in providers:
        if provider_alias not in PROVIDER_ALIASES:
            fail("Unknown provider alias '{}'. Available aliases: {}".format(
                provider_alias,
                ", ".join(sorted(PROVIDER_ALIASES.keys())),
            ))

        alias_info = PROVIDER_ALIASES[provider_alias]
        provider_source = alias_info["provider"]  # e.g., "hashicorp/aws"
        version = alias_info["version"]  # e.g., "6.14.0"

        # Get the provider name (last part of source)
        provider_name = _normalize_provider_name(provider_source)
        version_underscore = _version_to_underscore(version)

        # Generate download target for each platform
        for platform in _PLATFORMS:
            target_name = "download_{}_{}_{}".format(
                provider_name,
                version_underscore,
                platform,
            )
            platform_providers[platform].append(
                "@tf_provider_registry//:{}".format(target_name),
            )

    # Create filesystem_mirror for each platform with target compatibility constraints
    # This ensures RBE selects the correct platform's providers from cache
    for platform in _PLATFORMS:
        mirror_name = "{}_{}_mirror".format(name, platform)
        wrapper_name = "{}_{}".format(name, platform)

        if platform_providers[platform]:
            # Create the actual filesystem_mirror (internal target)
            filesystem_mirror(
                name = mirror_name,
                providers = platform_providers[platform],
                visibility = ["//visibility:private"],
                testonly = testonly,
            )

            # Wrap in filegroup with target_compatible_with for RBE
            native.filegroup(
                name = wrapper_name,
                srcs = [":{}".format(mirror_name)],
                visibility = visibility,
                testonly = testonly,
                target_compatible_with = _PLATFORM_CONSTRAINTS[platform],
            )
        else:
            # Create empty filegroup if no providers
            native.filegroup(
                name = wrapper_name,
                srcs = [],
                visibility = visibility,
                testonly = testonly,
                target_compatible_with = _PLATFORM_CONSTRAINTS[platform],
            )

    # Create config_setting targets for platform selection (if not already defined)
    # These are usually defined in the provider registry, but we define local ones
    # to avoid depending on the registry's internal targets
    _define_platform_config_settings(name)

    # Create platform-aware filegroup using select()
    native.filegroup(
        name = name,
        srcs = select({
            ":{}_linux_x86_64".format(name): [":{}_linux_amd64".format(name)],
            ":{}_linux_aarch64".format(name): [":{}_linux_arm64".format(name)],
            ":{}_macos_x86_64".format(name): [":{}_darwin_amd64".format(name)],
            ":{}_macos_aarch64".format(name): [":{}_darwin_arm64".format(name)],
        }),
        visibility = visibility,
        testonly = testonly,
    )

def _define_platform_config_settings(prefix):
    """Define platform config settings with a unique prefix."""

    native.config_setting(
        name = "{}_linux_x86_64".format(prefix),
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    )

    native.config_setting(
        name = "{}_linux_aarch64".format(prefix),
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:aarch64",
        ],
    )

    native.config_setting(
        name = "{}_macos_x86_64".format(prefix),
        constraint_values = [
            "@platforms//os:macos",
            "@platforms//cpu:x86_64",
        ],
    )

    native.config_setting(
        name = "{}_macos_aarch64".format(prefix),
        constraint_values = [
            "@platforms//os:macos",
            "@platforms//cpu:aarch64",
        ],
    )
