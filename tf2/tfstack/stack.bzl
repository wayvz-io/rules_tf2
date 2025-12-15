"""Core Terraform Stack rule implementation"""

load("//tf2/providers/core:info.bzl", "TfModuleInfo", "TfProviderConfigurationsInfo", "TfStackInfo")

def _aggregate_providers_from_modules(modules):
    """Aggregate provider configurations from all referenced modules.

    Args:
        modules: List of tf_module targets

    Returns:
        Dict of provider name to version constraint
    """
    providers = {}

    for module in modules:
        if TfModuleInfo not in module:
            continue

        module_info = module[TfModuleInfo]
        if module_info.provider_configurations:
            # Get provider configurations from the module
            provider_config = module_info.provider_configurations
            if TfProviderConfigurationsInfo in provider_config:
                config_info = provider_config[TfProviderConfigurationsInfo]
                for provider_name, version in config_info.providers.items():
                    # Use the first version seen (could also implement version conflict detection)
                    if provider_name not in providers:
                        providers[provider_name] = version

    return providers

def _tf_stack_impl(ctx):
    """Implementation of tf_stack_rule"""

    # Categorize source files
    component_files = []
    deploy_files = []
    data_files = []

    for src_file in ctx.files.srcs:
        if src_file.path.endswith(".tfcomponent.hcl"):
            component_files.append(src_file)
        elif src_file.path.endswith(".tfdeploy.hcl"):
            deploy_files.append(src_file)
        elif src_file.path.endswith(".json"):
            data_files.append(src_file)

        # Other files are just passed through

    # Aggregate providers from all referenced modules
    aggregated_providers = _aggregate_providers_from_modules(ctx.attr.modules)

    # Get lock file if provided
    lock_file = ctx.file.lock_file if ctx.attr.lock_file else None

    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        TfStackInfo(
            name = ctx.label.name,
            srcs = depset(ctx.files.srcs),
            component_files = depset(component_files),
            deploy_files = depset(deploy_files),
            data_files = depset(data_files),
            modules = ctx.attr.modules,
            provider_configurations = aggregated_providers,
            lock_file = lock_file,
            terraform_version = ctx.attr.terraform_version,
        ),
    ]

tf_stack_rule = rule(
    implementation = _tf_stack_impl,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = [".tfcomponent.hcl", ".tfdeploy.hcl", ".json"],
            doc = "Stack source files (.tfcomponent.hcl, .tfdeploy.hcl, and data files)",
        ),
        "modules": attr.label_list(
            providers = [TfModuleInfo],
            doc = "tf_module targets referenced by components (staged to ./components/)",
        ),
        "lock_file": attr.label(
            allow_single_file = [".terraform.lock.hcl"],
            doc = "Generated Terraform lock file",
        ),
        "terraform_version": attr.string(
            default = "1.14.1",
            doc = "Terraform version for .terraform-version file generation",
        ),
    },
    doc = "Creates a Terraform Stack target with provider aggregation from modules",
)
