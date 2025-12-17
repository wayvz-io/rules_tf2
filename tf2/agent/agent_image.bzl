"""Main macro for building TFC agent Docker images."""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_image_index", "oci_push")
load(":filtered_mirror.bzl", "filtered_provider_mirror")
load(":provider_layer.bzl", "agent_provider_layer")
load(":terraformrc.bzl", "terraformrc")
load(":tools_layer.bzl", "agent_config_layer", "agent_tools_layer")

def _extract_alias_from_label(label_str):
    """Extract provider alias from a label string.

    Args:
        label_str: Provider label like "@tf_provider_registry//:aws_6"

    Returns:
        Alias string like "aws_6"
    """
    # Handle Label objects and strings
    label = str(label_str)

    # Extract the target name after "//"
    if "//:" in label:
        return label.split("//:")[1]
    elif "//" in label:
        # Handle @repo//path:target format
        return label.split(":")[-1]
    return label

# Platform configuration
_PLATFORMS = {
    "linux_amd64": {
        "os": "linux",
        "architecture": "amd64",
        "base": "@tfc_agent_base_linux_amd64",
        "provider_mirror": "@tf_provider_registry//:mirror_linux_amd64",
        "terraform": "@tf_tool_registry//:terraform",
        "tfstacks": "@tf_tool_registry//:stacksplugin",
    },
    "linux_arm64": {
        "os": "linux",
        "architecture": "arm64",
        "base": "@tfc_agent_base_linux_arm64",
        "provider_mirror": "@tf_provider_registry//:mirror_linux_arm64",
        "terraform": "@tf_tool_registry//:terraform",
        "tfstacks": "@tf_tool_registry//:stacksplugin",
    },
}

def _build_platform_image(
        name,
        platform,
        provider_mirror = None,
        provider_aliases = None,
        module = None,
        include_terraform = True,
        include_tfstacks = True,
        terraformrc_target = None,
        visibility = None):
    """Build OCI image for a specific platform.

    Args:
        name: Base target name
        platform: Platform key (linux_amd64 or linux_arm64)
        provider_mirror: Override provider mirror label (uses full mirror)
        provider_aliases: List of provider aliases to include (filtered mirror)
        module: tf_module label to extract providers from (filtered mirror)
        include_terraform: Whether to include terraform binary
        include_tfstacks: Whether to include tfstacks binary
        terraformrc_target: Label for terraformrc file
        visibility: Target visibility
    """
    platform_config = _PLATFORMS.get(platform)
    if not platform_config:
        fail("Unknown platform: {}. Supported: {}".format(platform, _PLATFORMS.keys()))

    # Determine provider mirror to use
    if provider_aliases or module:
        # Create filtered mirror for this platform
        filtered_mirror_name = "{}_filtered_mirror".format(name)
        filtered_provider_mirror(
            name = filtered_mirror_name,
            full_mirror = platform_config["provider_mirror"],
            provider_aliases = provider_aliases,
            module = module,
        )
        mirror = ":" + filtered_mirror_name
    else:
        # Use full mirror or override
        mirror = provider_mirror or platform_config["provider_mirror"]

    # Create provider layer
    provider_layer_name = "{}_providers".format(name)
    agent_provider_layer(
        name = provider_layer_name,
        provider_mirror = mirror,
    )

    # Create tools layer
    tools_layer_name = "{}_tools".format(name)
    agent_tools_layer(
        name = tools_layer_name,
        terraform = platform_config["terraform"] if include_terraform else None,
        tfstacks = platform_config["tfstacks"] if include_tfstacks else None,
    )

    # Create config layer
    config_layer_name = "{}_config".format(name)
    agent_config_layer(
        name = config_layer_name,
        terraformrc = terraformrc_target,
    )

    # Build the OCI image
    # Note: os and architecture are inherited from base image, don't override
    oci_image(
        name = name,
        base = platform_config["base"],
        tars = [
            ":" + provider_layer_name,
            ":" + tools_layer_name,
            ":" + config_layer_name,
        ],
        env = {
            "TF_CLI_CONFIG_FILE": "/etc/terraform/.terraformrc",
        },
        visibility = visibility,
    )

def tfc_agent_image(
        name,
        providers = None,
        module = None,
        platforms = ["linux_amd64", "linux_arm64"],
        include_terraform = True,
        include_tfstacks = True,
        registry = "ghcr.io",
        repository = None,
        tag = "latest",
        tags = None,
        visibility = None):
    """Build a custom TFC agent Docker image with bundled providers.

    Creates a multi-architecture OCI image containing:
    - TFC agent base image (hashicorp/tfc-agent)
    - Terraform binary
    - tfstacks plugin
    - Provider filesystem mirror
    - .terraformrc configuration

    Provider Selection:
    - If neither `providers` nor `module` is specified, includes ALL providers
      from @tf_provider_registry
    - If `providers` is specified, creates a filtered mirror with only those providers
    - If `module` is specified, extracts providers from that tf_module's dependencies

    Args:
        name: Target name for the image
        providers: List of provider aliases (e.g., ["aws_6", "random_3"]) or
                   provider labels (e.g., ["@tf_provider_registry//:aws_6"]).
                   If None and module is None, uses all providers.
        module: tf_module label to extract providers from (mutually exclusive with providers)
        platforms: List of target platforms (default: ["linux_amd64", "linux_arm64"])
        include_terraform: Include terraform binary (default: True)
        include_tfstacks: Include tfstacks plugin (default: True)
        registry: OCI registry hostname (default: ghcr.io)
        repository: Repository path for push target (e.g., "org/image-name")
        tag: Image tag (default: "latest")
        tags: Bazel tags for the targets
        visibility: Target visibility

    Example:
        # All providers from versions.json
        tfc_agent_image(
            name = "full_agent",
            repository = "my-org/tfc-agent-full",
        )

        # Specific providers only
        tfc_agent_image(
            name = "aws_agent",
            providers = [
                "@tf_provider_registry//:aws_6",
                "@tf_provider_registry//:random_3",
            ],
            repository = "my-org/tfc-agent-aws",
        )

    Generated Targets:
        :{name} - Multi-arch OCI image index
        :{name}_linux_amd64 - AMD64 platform image
        :{name}_linux_arm64 - ARM64 platform image
        :{name}_push - Push target (if repository specified)
        :{name}_terraformrc - Generated .terraformrc file
    """
    if providers and module:
        fail("Cannot specify both 'providers' and 'module' - they are mutually exclusive")

    # Validate platforms
    for p in platforms:
        if p not in _PLATFORMS:
            fail("Unknown platform '{}'. Supported: {}".format(p, _PLATFORMS.keys()))

    # Generate .terraformrc
    terraformrc_name = name + "_terraformrc"
    terraformrc(
        name = terraformrc_name,
        tags = tags,
    )

    # Extract provider aliases if providers list is specified
    provider_aliases = None
    if providers:
        provider_aliases = [_extract_alias_from_label(p) for p in providers]

    # Build per-platform images
    platform_images = []
    for platform in platforms:
        platform_image_name = "{}_{}".format(name, platform)

        _build_platform_image(
            name = platform_image_name,
            platform = platform,
            provider_aliases = provider_aliases,
            module = module,
            include_terraform = include_terraform,
            include_tfstacks = include_tfstacks,
            terraformrc_target = ":" + terraformrc_name,
            visibility = ["//visibility:private"],
        )
        platform_images.append(":" + platform_image_name)

    # Create multi-arch image index
    oci_image_index(
        name = name,
        images = platform_images,
        tags = tags,
        visibility = visibility,
    )

    # Create push target if repository specified
    if repository:
        oci_push(
            name = name + "_push",
            image = ":" + name,
            repository = "{}/{}".format(registry, repository),
            remote_tags = [tag],
            tags = tags,
            visibility = visibility,
        )
