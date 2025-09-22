"""Default TFLint rule configurations for each provider"""

# Base Terraform rules that are always enabled
TERRAFORM_BASE_RULES = {
    "terraform_comment_syntax": {"enabled": True},
    "terraform_deprecated_index": {"enabled": True},
    "terraform_documented_outputs": {"enabled": True},
    "terraform_documented_variables": {"enabled": True},
    "terraform_empty_list_equality": {"enabled": True},
    "terraform_naming_convention": {"enabled": True},
    "terraform_required_providers": {"enabled": True},
    "terraform_required_version": {"enabled": True},
    "terraform_standard_module_structure": {"enabled": False},  # Disabled for template modules
    "terraform_typed_variables": {"enabled": True, "force": True},
    "terraform_unused_declarations": {"enabled": True},
}

# AWS TFLint plugin rules
AWS_PLUGIN_RULES = {
    # Instance rules
    "aws_instance_invalid_type": {"enabled": True},
    "aws_instance_previous_type": {"enabled": True},
    "aws_instance_invalid_ami": {"enabled": True},
    "aws_instance_invalid_key_name": {"enabled": True},
    "aws_instance_invalid_subnet": {"enabled": True},
    "aws_instance_invalid_vpc_security_group_id": {"enabled": True},
    "aws_instance_invalid_iam_profile": {"enabled": True},

    # Security Group rules
    "aws_security_group_invalid_id": {"enabled": True},
    "aws_security_group_rule_invalid_id": {"enabled": True},

    # VPC rules
    "aws_vpc_invalid_id": {"enabled": True},
    "aws_subnet_invalid_id": {"enabled": True},
    "aws_route_table_invalid_id": {"enabled": True},

    # ELB rules
    "aws_elb_invalid_name": {"enabled": True},
    "aws_alb_invalid_name": {"enabled": True},

    # RDS rules
    "aws_db_instance_invalid_type": {"enabled": True},
    "aws_db_instance_previous_type": {"enabled": True},
    "aws_db_instance_invalid_engine": {"enabled": True},

    # S3 rules
    "aws_s3_bucket_invalid_name": {"enabled": True},
    "aws_s3_bucket_name": {"enabled": True},

    # Spot instance rules
    "aws_spot_instance_request_invalid_type": {"enabled": True},

    # Auto Scaling rules
    "aws_autoscaling_group_invalid_subnets": {"enabled": True},
    "aws_launch_configuration_invalid_image_id": {"enabled": True},

    # ECS rules
    "aws_ecs_cluster_invalid_name": {"enabled": True},
    "aws_ecs_service_invalid_name": {"enabled": True},

    # Lambda rules
    "aws_lambda_function_invalid_runtime": {"enabled": True},

    # CloudWatch rules
    "aws_cloudwatch_log_group_invalid_name": {"enabled": True},

    # IAM rules
    "aws_iam_role_invalid_name": {"enabled": True},
    "aws_iam_policy_invalid_name": {"enabled": True},

    # Deep inspection rules (disabled by default due to sandbox limitations)
    "aws_instance_invalid_ami_owner": {"enabled": False},  # Requires AWS API access
    "aws_db_instance_invalid_backup_retention_period": {"enabled": False},  # Requires AWS API access
}

# Azure TFLint plugin rules
AZURERM_PLUGIN_RULES = {
    # Virtual Machine rules
    "azurerm_virtual_machine_invalid_vm_size": {"enabled": True},
    "azurerm_virtual_machine_scale_set_invalid_vm_size": {"enabled": True},

    # Kubernetes rules
    "azurerm_kubernetes_cluster_default_node_pool_invalid_vm_size": {"enabled": True},
    "azurerm_kubernetes_cluster_node_pool_invalid_vm_size": {"enabled": True},

    # Container Instance rules
    "azurerm_container_group_invalid_os_type": {"enabled": True},

    # Network rules
    "azurerm_virtual_network_invalid_address_space": {"enabled": True},
    "azurerm_subnet_invalid_address_prefix": {"enabled": True},

    # Storage rules
    "azurerm_storage_account_invalid_name": {"enabled": True},

    # Deep inspection rules (disabled by default due to sandbox limitations)
    "azurerm_virtual_machine_invalid_image": {"enabled": False},  # Requires Azure API access
}

# Google Cloud TFLint plugin rules
GOOGLE_PLUGIN_RULES = {
    # Compute Engine rules
    "google_compute_instance_invalid_machine_type": {"enabled": True},
    "google_compute_disk_invalid_type": {"enabled": True},

    # Project rules
    "google_project_invalid_machine_type": {"enabled": True},

    # Container rules
    "google_container_cluster_invalid_machine_type": {"enabled": True},
    "google_container_node_pool_invalid_machine_type": {"enabled": True},

    # SQL rules
    "google_sql_database_instance_invalid_tier": {"enabled": True},

    # Deep inspection rules (disabled by default due to sandbox limitations)
    "google_compute_instance_invalid_image": {"enabled": False},  # Requires GCP API access
}

# OPA TFLint plugin rules (for policy as code)
OPA_PLUGIN_RULES = {
    # Policy evaluation rules
    "opa_policy": {"enabled": True},
}

# Map provider names to their default rules
PROVIDER_RULES = {
    "aws": AWS_PLUGIN_RULES,
    "azurerm": AZURERM_PLUGIN_RULES,
    "google": GOOGLE_PLUGIN_RULES,
    "opa": OPA_PLUGIN_RULES,
}

# Tagged configuration overrides
TAGGED_OVERRIDES = {
    "standalone_module": {
        # Modules intended to be inherited by other modules
        "terraform_documented_outputs": {"enabled": False},  # Outputs may not be fully documented
        "terraform_documented_variables": {"enabled": False},  # Variables may not be fully documented
        "terraform_standard_module_structure": {"enabled": False},  # May not follow standard structure
    },
    "consumer_module": {
        # Modules intended to be directly consumed
        "terraform_documented_outputs": {"enabled": True},
        "terraform_documented_variables": {"enabled": True},
        "terraform_standard_module_structure": {"enabled": True},
    },
    "test_module": {
        # Test modules may have relaxed rules
        "terraform_documented_outputs": {"enabled": False},
        "terraform_documented_variables": {"enabled": False},
        "terraform_naming_convention": {"enabled": False},
        "terraform_unused_declarations": {"enabled": False},
    },
}

def get_base_rules():
    """Get the base Terraform rules

    Returns:
        Dictionary of base Terraform rules
    """
    return TERRAFORM_BASE_RULES

def get_provider_rules(provider_name):
    """Get default rules for a specific provider

    Args:
        provider_name: Name of the provider (aws, azurerm, google, opa)

    Returns:
        Dictionary of provider-specific rules or empty dict if not found
    """
    return PROVIDER_RULES.get(provider_name, {})

def get_tagged_overrides(tag):
    """Get rule overrides for a specific tag

    Args:
        tag: Tag name

    Returns:
        Dictionary of rule overrides or empty dict if not found
    """
    return TAGGED_OVERRIDES.get(tag, {})

def merge_rule_configs(base, *overlays):
    """Merge multiple rule configurations with overlay priority

    Args:
        base: Base configuration dictionary
        *overlays: Additional configuration dictionaries to overlay

    Returns:
        Merged configuration dictionary
    """
    result = dict(base)

    for overlay in overlays:
        for rule_name, rule_config in overlay.items():
            if rule_name in result:
                # Merge rule configurations
                merged_rule = dict(result[rule_name])
                merged_rule.update(rule_config)
                result[rule_name] = merged_rule
            else:
                result[rule_name] = dict(rule_config)

    return result
