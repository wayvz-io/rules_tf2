"""Default TFLint rule configurations for each provider"""

# Base Terraform rules that are always enabled
# NOTE: terraform_required_providers from upstream is disabled because we use
# the enhanced version from the tf2 plugin (supports allowlists, version validation, autofix)
TERRAFORM_BASE_RULES = {
    "terraform_comment_syntax": {"enabled": True},
    "terraform_deprecated_index": {"enabled": True},
    "terraform_deprecated_interpolation": {"enabled": True},
    "terraform_deprecated_lookup": {"enabled": True},
    "terraform_documented_outputs": {"enabled": True},
    "terraform_documented_variables": {"enabled": True},
    "terraform_empty_list_equality": {"enabled": True},
    "terraform_naming_convention": {"enabled": True},
    "terraform_required_providers": {"enabled": False},  # Replaced by tf2 plugin version
    "terraform_required_version": {"enabled": True},
    "terraform_standard_module_structure": {"enabled": False},  # Disabled for template modules
    "terraform_typed_variables": {"enabled": True, "force": True},
    "terraform_unused_declarations": {"enabled": True},
}

# AWS TFLint plugin rules
# See: https://github.com/terraform-linters/tflint-ruleset-aws/blob/master/docs/rules/README.md
AWS_PLUGIN_RULES = {
    # EC2 Instance rules
    "aws_instance_invalid_ami": {"enabled": True},
    "aws_instance_invalid_iam_profile": {"enabled": True},
    "aws_instance_invalid_key_name": {"enabled": True},
    "aws_instance_invalid_subnet": {"enabled": True},
    "aws_instance_invalid_vpc_security_group": {"enabled": True},
    "aws_instance_previous_type": {"enabled": True},

    # ALB/ELB rules
    "aws_alb_invalid_security_group": {"enabled": True},
    "aws_alb_invalid_subnet": {"enabled": True},
    "aws_elb_invalid_instance": {"enabled": True},
    "aws_elb_invalid_security_group": {"enabled": True},
    "aws_elb_invalid_subnet": {"enabled": True},

    # RDS rules
    "aws_db_instance_invalid_db_subnet_group": {"enabled": True},
    "aws_db_instance_invalid_engine": {"enabled": True},
    "aws_db_instance_invalid_option_group": {"enabled": True},
    "aws_db_instance_invalid_parameter_group": {"enabled": True},
    "aws_db_instance_invalid_type": {"enabled": True},
    "aws_db_instance_invalid_vpc_security_group": {"enabled": True},
    "aws_db_instance_default_parameter_group": {"enabled": True},
    "aws_db_instance_previous_type": {"enabled": True},

    # Security Group rules
    "aws_security_group_invalid_protocol": {"enabled": True},
    "aws_security_group_rule_invalid_protocol": {"enabled": True},
    "aws_security_group_inline_rules": {"enabled": True},
    "aws_security_group_rule_deprecated": {"enabled": True},

    # S3 rules
    "aws_s3_bucket_name": {"enabled": True},

    # Route rules
    "aws_route_invalid_egress_only_gateway": {"enabled": True},
    "aws_route_invalid_gateway": {"enabled": True},
    "aws_route_invalid_instance": {"enabled": True},
    "aws_route_invalid_nat_gateway": {"enabled": True},
    "aws_route_invalid_network_interface": {"enabled": True},
    "aws_route_invalid_route_table": {"enabled": True},
    "aws_route_invalid_vpc_peering_connection": {"enabled": True},
    "aws_route_not_specified_target": {"enabled": True},
    "aws_route_specified_multiple_targets": {"enabled": True},

    # Launch Configuration rules
    "aws_launch_configuration_invalid_iam_profile": {"enabled": True},
    "aws_launch_configuration_invalid_image_id": {"enabled": True},

    # Lambda rules
    "aws_lambda_function_deprecated_runtime": {"enabled": True},

    # ElastiCache rules
    "aws_elasticache_cluster_invalid_parameter_group": {"enabled": True},
    "aws_elasticache_cluster_invalid_security_group": {"enabled": True},
    "aws_elasticache_cluster_invalid_subnet_group": {"enabled": True},
    "aws_elasticache_cluster_invalid_type": {"enabled": True},
    "aws_elasticache_cluster_default_parameter_group": {"enabled": True},
    "aws_elasticache_cluster_previous_type": {"enabled": True},
    "aws_elasticache_replication_group_invalid_type": {"enabled": True},
    "aws_elasticache_replication_group_default_parameter_group": {"enabled": True},
    "aws_elasticache_replication_group_previous_type": {"enabled": True},

    # IAM rules
    "aws_iam_group_policy_too_long": {"enabled": True},
    "aws_iam_policy_sid_invalid_characters": {"enabled": True},
    "aws_iam_policy_too_long_policy": {"enabled": True},
    "aws_iam_role_deprecated_policy_attributes": {"enabled": True},
    "aws_iam_policy_attachment_exclusive_attachment": {"enabled": True},

    # DynamoDB rules
    "aws_dynamodb_table_invalid_stream_view_type": {"enabled": True},

    # API Gateway rules
    "aws_api_gateway_model_invalid_name": {"enabled": True},

    # Elastic Beanstalk rules
    "aws_elastic_beanstalk_environment_invalid_name_format": {"enabled": True},

    # MQ rules
    "aws_mq_broker_invalid_engine_type": {"enabled": True},
    "aws_mq_configuration_invalid_engine_type": {"enabled": True},

    # Spot Fleet rules
    "aws_spot_fleet_request_invalid_excess_capacity_termination_policy": {"enabled": True},

    # Best practices
    "aws_acm_certificate_lifecycle": {"enabled": True},
    "aws_ephemeral_resources": {"enabled": True},
}

# Azure TFLint plugin rules
# See: https://github.com/terraform-linters/tflint-ruleset-azurerm
# Note: Azure plugin has many auto-generated rules; only explicitly configure rules that exist
AZURERM_PLUGIN_RULES = {
    # Virtual Machine rules (validated to exist in v0.27.0)
    "azurerm_virtual_machine_invalid_vm_size": {"enabled": True},
    "azurerm_resources_missing_prevent_destroy": {"enabled": False},
}

# Google Cloud TFLint plugin rules
# See: https://github.com/terraform-linters/tflint-ruleset-google
GOOGLE_PLUGIN_RULES = {
    # Compute Engine rules
    "google_compute_instance_invalid_machine_type": {"enabled": True},
    "google_compute_instance_template_invalid_machine_type": {"enabled": True},
    "google_compute_reservation_invalid_machine_type": {"enabled": True},

    # Container/GKE rules
    "google_container_cluster_invalid_machine_type": {"enabled": True},
    "google_container_node_pool_invalid_machine_type": {"enabled": True},

    # Composer rules
    "google_composer_environment_invalid_machine_type": {"enabled": True},

    # Dataflow rules
    "google_dataflow_job_invalid_machine_type": {"enabled": True},

    # IAM rules
    "google_project_iam_audit_config_invalid_member": {"enabled": True},
    "google_project_iam_binding_invalid_member": {"enabled": True},
    "google_project_iam_member_invalid_member": {"enabled": True},
    "google_project_iam_policy_invalid_member": {"enabled": True},

    # Deep checking (requires API access)
    "google_disabled_api": {"enabled": False},  # Requires GCP API access
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

                # Handle case where rule_config is a dict vs a string
                if type(rule_config) == "dict":
                    merged_rule.update(rule_config)
                else:
                    # If it's not a dict, assume it's enabled/disabled status
                    merged_rule["enabled"] = rule_config
                result[rule_name] = merged_rule
            else:
                # Handle case where rule_config is a dict vs a string
                if type(rule_config) == "dict":
                    result[rule_name] = dict(rule_config)
                else:
                    # If it's not a dict, assume it's enabled/disabled status
                    result[rule_name] = {"enabled": rule_config}

    return result
