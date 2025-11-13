"""Configuration for Terraform Registry publishing."""

REGISTRY_CONFIG = {
    # Default registry hostname for HCP Terraform/Terraform Enterprise
    "registry": "app.terraform.io",

    # Default namespace (will be overridden by organization in most cases)
    "namespace": "private",

    # Default version increment type
    "default_version_increment": "patch",

    # API paths
    "api_base_path": "/api/v2",

    # Module registry name (for HCP Terraform/TFE, this is always "private")
    "registry_name": "private",
}
