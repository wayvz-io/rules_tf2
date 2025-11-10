"""Default configurations for tflint rules."""

def get_base_rules():
    """Get the base tflint rules configuration.

    Returns:
        Dictionary of base tflint rules
    """
    return {
        "terraform_naming_convention": {"enabled": True, "format": "snake_case"},
        "terraform_documented_variables": {"enabled": True},
        "terraform_documented_outputs": {"enabled": True},
        "terraform_unused_declarations": {"enabled": True},
        "terraform_typed_variables": {"enabled": True},
    }

def get_tagged_overrides(tag):
    """Get rule overrides based on a tag.

    Args:
        tag: Tag to get overrides for

    Returns:
        Dictionary of rule overrides for the tag
    """
    if tag == "test_module":
        return {
            "terraform_naming_convention": {"enabled": False},
            "terraform_documented_variables": {"enabled": False},
            "terraform_documented_outputs": {"enabled": False},
            "terraform_unused_declarations": {"enabled": False},
        }
    return {}

def merge_rule_configs(base, overrides):
    """Merge rule configurations.

    Args:
        base: Base rule configuration
        overrides: Override configuration

    Returns:
        Merged configuration
    """
    result = dict(base)
    for rule_name, rule_config in overrides.items():
        if rule_name in result:
            if type(result[rule_name]) == "dict" and type(rule_config) == "dict":
                merged = dict(result[rule_name])
                merged.update(rule_config)
                result[rule_name] = merged
            else:
                result[rule_name] = rule_config
        else:
            result[rule_name] = rule_config
    return result