"""Information providers for external Terraform modules."""

TfExternalModuleInfo = provider(
    doc = "Information about an external Terraform module from a registry or git repository",
    fields = {
        "name": "Module name (e.g., 'vpc')",
        "namespace": "Module namespace (e.g., 'terraform-aws-modules')",
        "provider_name": "Provider name for registry modules (e.g., 'aws'), empty for git modules",
        "version": "Version string or git ref (tag or short commit hash)",
        "source_type": "Source type: 'registry', 'git', or 'private'",
        "source_url": "Full source URL for Terraform config (e.g., 'terraform-aws-modules/vpc/aws')",
        "alias": "Alias name for referencing (e.g., 'vpc_aws_5')",
        "files": "Module source files (depset of Files)",
    },
)
