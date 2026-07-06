"""Terraform Cloud runner rules for plan and apply operations."""

load("//tf2/tfcore:tf_runner.bzl", "tf_runner")

def tfc_workspace(
        name,
        module,
        workspace_name,
        variables = None,
        organization = None,
        tfe_host = None,
        auto_backend = True,
        **kwargs):
    """Creates Terraform Cloud runner targets for plan and apply operations.

    Wires a `tf_module` to a Terraform Cloud / Enterprise workspace and generates
    the `cloud` backend configuration automatically. Produces a runner target that
    can execute any terraform command against the workspace, plus a local
    `name_validate` target with no backend.

    Example:

    ```starlark
    load("@rules_tf2//tf2:def.bzl", "tfc_workspace")

    tfc_workspace(
        name = "prod",
        module = ":my_module",
        workspace_name = "my-workspace-prod",
        organization = "my-org",
    )
    ```

    Args:
        name: Base name for the targets
        module: The tf_module target to run against (replaces stack parameter)
        workspace_name: Terraform Cloud workspace name
        variables: Optional tf_variables target with tfvars files
        organization: Terraform Cloud organization (required)
        tfe_host: Terraform Enterprise hostname (optional, defaults to app.terraform.io)
        auto_backend: Automatically generate backend configuration (default True)
        **kwargs: Additional attributes passed to all rules
    """

    # Organization is required - there is no sensible default.
    if not organization:
        fail("tfc_workspace requires an 'organization' (your Terraform Cloud/Enterprise org name).")

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
