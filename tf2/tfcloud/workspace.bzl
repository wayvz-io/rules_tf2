"""Terraform Cloud workspace management utilities"""

def workspace_config(
        name,
        organization,
        workspace_name,
        description = None,
        terraform_version = None,
        working_directory = None,
        vcs_repo = None,
        auto_apply = False,
        execution_mode = "remote",
        **kwargs):
    """Create workspace configuration for Terraform Cloud.

    This is a utility function to help standardize workspace configurations.
    The actual workspace creation is handled by tf_cloud_configuration in runner.bzl.

    Args:
        name: Workspace configuration name
        organization: Terraform Cloud organization
        workspace_name: Name of the workspace in Terraform Cloud
        description: Optional workspace description
        terraform_version: Terraform version constraint
        working_directory: Working directory within the repository
        vcs_repo: VCS repository configuration
        auto_apply: Whether to automatically apply changes
        execution_mode: Execution mode (remote, local, agent)
        **kwargs: Additional workspace settings

    Returns:
        Dictionary with workspace configuration
    """
    config = {
        "name": name,
        "organization": organization,
        "workspace_name": workspace_name,
        "auto_apply": auto_apply,
        "execution_mode": execution_mode,
    }

    if description:
        config["description"] = description
    if terraform_version:
        config["terraform_version"] = terraform_version
    if working_directory:
        config["working_directory"] = working_directory
    if vcs_repo:
        config["vcs_repo"] = vcs_repo

    config.update(kwargs)
    return config

def workspace_variable(name, value, category = "terraform", sensitive = False, description = None):
    """Create a workspace variable configuration.

    Args:
        name: Variable name
        value: Variable value
        category: Variable category (terraform, env)
        sensitive: Whether the variable is sensitive
        description: Optional variable description

    Returns:
        Dictionary with variable configuration
    """
    return {
        "name": name,
        "value": value,
        "category": category,
        "sensitive": sensitive,
        "description": description,
    }
