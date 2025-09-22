"""Terraform Cloud runner rules for plan and apply operations."""

load("//tf2/runner:tf_runner.bzl", "tf_runner")

def tf_cloud_configuration(
        name,
        module,
        workspace_name,
        variables = None,
        organization = None,
        tfe_host = None,
        auto_backend = True,
        _auto_apply = False,  # Ignored, kept for backward compatibility
        _enable_local_validation = True,  # Ignored, kept for backward compatibility
        **kwargs):
    """Creates Terraform Cloud runner targets for plan and apply operations.

    Args:
        name: Base name for the targets
        module: The tf_module target to run against (replaces stack parameter)
        workspace_name: Terraform Cloud workspace name
        variables: Optional tf_variables target with tfvars files
        organization: Terraform Cloud organization (defaults to "Wayvz" if not set)
        tfe_host: Terraform Enterprise hostname (optional, defaults to app.terraform.io)
        auto_backend: Automatically generate backend configuration (default True)
        _auto_apply: Ignored, kept for backward compatibility
        _enable_local_validation: Ignored, kept for backward compatibility
        **kwargs: Additional attributes passed to all rules
    """

    # Default organization if not provided
    if not organization:
        organization = "Wayvz"

    # Filter out kwargs that tf_runner doesn't accept
    # Remove auto_apply and enable_local_validation as they're handled differently now
    filtered_kwargs = {k: v for k, v in kwargs.items() if k not in ["auto_apply", "enable_local_validation"]}

    # Main runner target - can run any terraform command
    if auto_backend:
        tf_runner(
            name = name,
            stack = module,
            variables = variables,
            backend_type = "cloud",
            backend_organization = organization,
            backend_workspace = workspace_name,
            tfe_host = tfe_host or "app.terraform.io",
            **filtered_kwargs
        )
    else:
        tf_runner(
            name = name,
            stack = module,
            variables = variables,
            backend_type = "",
            **filtered_kwargs
        )

    # Local validation target (no backend)
    tf_runner(
        name = name + "_validate",
        stack = module,
        variables = variables,
        backend_type = "",  # No backend for local validation
        default_plan_args = "",  # No args needed for validation
        init_args = "-backend=false",  # Disable backend for init
        **filtered_kwargs
    )

    # Plan target (speculative plan equivalent)
    if auto_backend:
        tf_runner(
            name = name + "_tfc_plan",
            stack = module,
            variables = variables,
            backend_type = "cloud",
            backend_organization = organization,
            backend_workspace = workspace_name,
            tfe_host = tfe_host or "app.terraform.io",
            default_plan_args = "",
            **filtered_kwargs
        )
    else:
        tf_runner(
            name = name + "_tfc_plan",
            stack = module,
            variables = variables,
            backend_type = "",
            default_plan_args = "",
            **filtered_kwargs
        )

    # Apply target
    if auto_backend:
        tf_runner(
            name = name + "_tfc_apply",
            stack = module,
            variables = variables,
            backend_type = "cloud",
            backend_organization = organization,
            backend_workspace = workspace_name,
            tfe_host = tfe_host or "app.terraform.io",
            default_command = "apply",
            default_apply_args = "-auto-approve",
            **filtered_kwargs
        )
    else:
        tf_runner(
            name = name + "_tfc_apply",
            stack = module,
            variables = variables,
            backend_type = "",
            default_command = "apply",
            default_apply_args = "-auto-approve",
            **filtered_kwargs
        )

# Alias for backwards compatibility
tf_cloud_workspace = tf_cloud_configuration
