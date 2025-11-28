"""Core Terraform module rule implementation"""

load("//tf2/providers/core:info.bzl", "TfModuleInfo", "TfProviderConfigurationsInfo")
load(":nested.bzl", "process_nested_modules")

def _tf_module_impl(ctx):
    """Implementation of tf_module rule"""

    # Split input files into terraform sources and docs
    tf_files = []
    doc_files = []
    for f in ctx.files.srcs:
        if f.basename.endswith("README.md") or f.basename.endswith(".tfdoc.yaml") or f.basename.endswith(".terraform-docs.yml"):
            doc_files.append(f)
        else:
            tf_files.append(f)

    # Process nested modules if any are specified (only for terraform files)
    if ctx.attr.modules:
        all_files, _ = process_nested_modules(ctx, tf_files, ctx.attr.modules)
        output_files = depset(all_files)
    else:
        output_files = depset(tf_files)

    # Get the lock file if provided
    lock_file = ctx.files.lock_file[0] if ctx.attr.lock_file and ctx.files.lock_file else None

    return [
        DefaultInfo(files = output_files),  # Only terraform files
        TfModuleInfo(
            name = ctx.label.name,
            srcs = output_files,  # Only terraform files
            docs = depset(doc_files),  # Documentation files
            deps = ctx.attr.deps if hasattr(ctx.attr, "deps") else [],
            modules = ctx.attr.modules if hasattr(ctx.attr, "modules") else [],
            provider_configurations = ctx.attr.provider_configurations,
            lock_file = lock_file,
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
            doc = "Module source files (.tf files and documentation). Docs will be separated into the docs field of TfModuleInfo.",
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
        "lock_file": attr.label(
            allow_single_file = [".terraform.lock.hcl"],
            doc = "Terraform lock file",
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
