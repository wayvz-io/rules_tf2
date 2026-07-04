"""Global OCI configuration for Terraform stacks."""

# Default OCI registry configuration
OCI_CONFIG = {
    "registry": "ghcr.io",
    "repository": "my-org/my-repo",
    "default_tag": "unstable",
}

def get_oci_image(stack_name, tag = None):
    """Generate OCI image URL for a stack."""
    tag = tag or OCI_CONFIG["default_tag"]
    return "{}/{}/tf/{}:{}".format(
        OCI_CONFIG["registry"],
        OCI_CONFIG["repository"],
        stack_name,
        tag,
    )
