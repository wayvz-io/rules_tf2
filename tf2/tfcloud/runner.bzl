"""Terraform Cloud runner rules for plan and apply operations."""

load("//tf2/tfcore:tf_runner.bzl", "tf_runner")

def tf_cloud_workspace(
        name,
        module,
        workspace_name,
        variables = None,
        organization = None,
        tfe_host = None,
        auto_backend = True,
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
        **kwargs: Additional attributes passed to all rules
    """

    # Default organization if not provided
    if not organization:
        organization = "Wayvz"

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
            **kwargs
        )
    else:
        tf_runner(
            name = name,
            stack = module,
            variables = variables,
            backend_type = "",
            **kwargs
        )

    # Local validation target (no backend)
    tf_runner(
        name = name + "_validate",
        stack = module,
        variables = variables,
        backend_type = "",  # No backend for local validation
        default_command = "validate",
        default_plan_args = "",  # No args needed for validation
        init_args = "-backend=false",  # Disable backend for init
        **kwargs
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
            default_command = "plan",
            default_plan_args = "",
            **kwargs
        )
    else:
        tf_runner(
            name = name + "_tfc_plan",
            stack = module,
            variables = variables,
            backend_type = "",
            default_command = "plan",
            default_plan_args = "",
            **kwargs
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
            **kwargs
        )
    else:
        tf_runner(
            name = name + "_tfc_apply",
            stack = module,
            variables = variables,
            backend_type = "",
            default_command = "apply",
            default_apply_args = "-auto-approve",
            **kwargs
        )

