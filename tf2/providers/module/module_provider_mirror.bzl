"""Per-module provider mirror macro for efficient provider caching.

This macro validates that requested provider aliases exist and creates
an alias to the global provider mirror. Terraform only uses providers
declared in the module's terraform.tf, so having extra providers in
the mirror doesn't affect behavior.

RBE Compatibility:
    Uses the global platform-aware provider mirror from @tf_provider_registry,
    which uses select() to choose the correct platform's providers.
"""

load("@tf_provider_registry//:provider_locks.bzl", "PROVIDER_ALIASES")

def tf_module_provider_mirror(
        name,
        providers,
        visibility = None,
        testonly = None):
    """Creates an alias to the global provider mirror after validating aliases.

    This macro validates that all requested provider aliases exist in the
    provider registry, then creates a simple alias to the global mirror.
    Terraform only uses providers declared in the module's terraform.tf,
    so having extra providers in the mirror doesn't affect behavior.

    Performance: Creates 1 target instead of 9 (was: 4 filesystem_mirrors +
    4 filegroup wrappers + 1 select-based filegroup).

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

    # Validate that all requested provider aliases exist
    for provider_alias in providers:
        if provider_alias not in PROVIDER_ALIASES:
            fail("Unknown provider alias '{}'. Available aliases: {}".format(
                provider_alias,
                ", ".join(sorted(PROVIDER_ALIASES.keys())),
            ))

    # Create a simple alias to the global provider mirror
    # The global mirror already handles platform selection via select()
    # Terraform only uses providers declared in the module's terraform.tf,
    # so having extra providers in the mirror doesn't affect behavior
    native.alias(
        name = name,
        actual = "@tf_provider_registry//:unpacked_providers",
        visibility = visibility,
    )
