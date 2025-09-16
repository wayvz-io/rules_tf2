"""Terraform module rule implementation"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":info.bzl", "TfModuleInfo", "TfProviderConfigurationsInfo")
load(":nested_modules.bzl", "process_nested_modules")

def _tf_module_impl(ctx):
    """Implementation of tf_module rule"""
    
    # Process nested modules if any are specified
    if ctx.attr.modules:
        all_files, module_mappings = process_nested_modules(ctx, ctx.files.srcs, ctx.attr.modules)
        output_files = depset(all_files)
    else:
        output_files = depset(ctx.files.srcs)
        module_mappings = {}
    
    return [
        DefaultInfo(files = output_files),
        TfModuleInfo(
            name = ctx.label.name,
            srcs = output_files,
            deps = ctx.attr.deps if hasattr(ctx.attr, "deps") else [],
            modules = ctx.attr.modules if hasattr(ctx.attr, "modules") else [],
            provider_configurations = ctx.attr.provider_configurations,
        ),
    ]

def _tf_module_deps_impl(ctx):
    """Implementation of tf_module_deps rule"""
    
    # Collect all transitive sources from dependencies
    transitive_srcs = []
    for dep in ctx.attr.deps:
        if TfModuleInfo in dep:
            # srcs is already a depset, so just append it
            if type(dep[TfModuleInfo].srcs) == "depset":
                transitive_srcs.append(dep[TfModuleInfo].srcs)
            else:
                # If it's a list, convert to depset
                transitive_srcs.append(depset(dep[TfModuleInfo].srcs))
    
    # Create a combined depset
    all_files = depset(transitive = transitive_srcs) if transitive_srcs else depset()
    
    return [DefaultInfo(files = all_files)]

tf_module_rule = rule(
    implementation = _tf_module_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Module source files (defaults to all files in the module directory)",
        ),
        "deps": attr.label_list(
            doc = "Other tf_module dependencies",
            providers = [TfModuleInfo],
        ),
        "modules": attr.label_list(
            doc = "Nested modules in this module (for complex deployments)",
            providers = [TfModuleInfo],
        ),
        "provider_configurations": attr.label(
            doc = "Provider configurations with version constraints",
            providers = [TfProviderConfigurationsInfo],
        ),
        "tflint_config": attr.label(
            allow_single_file = [".hcl"],
            doc = "TFLint configuration file",
        ),
    },
    doc = "Defines a Terraform module (can contain nested modules for complex deployments)",
)

tf_module_deps = rule(
    implementation = _tf_module_deps_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "tf_module dependencies",
            providers = [TfModuleInfo],
        ),
    },
    doc = "Collects transitive dependencies from tf_module targets",
)