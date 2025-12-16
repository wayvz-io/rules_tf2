"""Public API macro for creating Terraform Stacks with comprehensive testing"""

load("//tf2/internal:sources_validation.bzl", "tf_untracked_files_test")
load("//tf2/providers/module:module_provider_mirror.bzl", "tf_module_provider_mirror")
load("//tf2/tfcore/versions:lockfile.bzl", "tf_generate_lockfile_for_validation")
load("//tf2/tfcore/versions:versions.bzl", "tf_generate_versions_from_mirrors")
load("//tf2/tfstack:deps.bzl", "tf_stack_deps_test")
load("//tf2/tfstack:export.bzl", "tf_stack_file_export")
load("//tf2/tfstack:format.bzl", "tf_stack_format", "tf_stack_format_test")
load("//tf2/tfstack:generate_versions.bzl", "tf_stack_generate_versions")
load("//tf2/tfstack:stack.bzl", "tf_stack_rule")
load("//tf2/tfstack:validate.bzl", "tf_stack_validate_test")

def _tf_stack_impl(
        name,
        visibility,
        srcs,
        modules,
        module_aliases,
        providers,
        tflint_config,
        skip_validation,
        terraform_version,
        testonly,
        tags):
    """Implementation of tf_stack symbolic macro.

    Creates a Terraform Stack with associated build and test targets:
    - name: The main stack target
    - name_srcs: Filegroup of all sources
    - name_format_test: Format checking test for HCL files
    - name_format: Format fixer for HCL files
    - name_validate_test: Stack validation test (terraform stacks validate)
    - name_deps_test: Component dependency validation test
    - name_untracked_files_test: Test that no untracked files exist
    - name_file_export: Export stack to a directory
    """

    # Normalize None values to empty lists for iteration
    actual_modules = modules if modules else []
    actual_providers = providers if providers else []
    actual_tags = tags if tags else []

    # Create filegroup for sources
    native.filegroup(
        name = name + "_srcs",
        srcs = srcs,
        visibility = visibility,
    )

    # Generate provider configurations from modules
    # This aggregates providers from all referenced tf_modules
    tf_generate_versions_from_mirrors(
        name = name + "_provider_config",
        providers = actual_providers,
        modules = actual_modules,
        terraform_version = terraform_version if terraform_version else "1.14.1",
        visibility = visibility,
        testonly = testonly,
    )
    actual_provider_configurations = ":" + name + "_provider_config"

    # Generate lockfile for the stack
    generated_lock_name = name + "_generated_lock"
    tf_generate_lockfile_for_validation(
        name = generated_lock_name,
        provider_locks = "@tf_provider_registry//:provider_locks.json",
        versions_json = actual_provider_configurations,
        visibility = visibility,
        testonly = testonly,
    )

    # Create the main stack rule
    tf_stack_rule(
        name = name,
        srcs = srcs,
        modules = actual_modules,
        module_aliases = module_aliases if module_aliases else {},
        lock_file = ":" + generated_lock_name,
        terraform_version = terraform_version if terraform_version else "1.14.1",
        visibility = visibility,
        testonly = testonly,
    )

    # Create format test and formatter for HCL files
    tf_stack_format_test(
        name = name + "_format_test",
        stack = ":" + name,
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = actual_tags if actual_tags else None,
    )

    tf_stack_format(
        name = name + "_format",
        stack = ":" + name,
        visibility = visibility,
    )

    # Create dependency validation test
    tf_stack_deps_test(
        name = name + "_deps_test",
        stack = ":" + name,
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = actual_tags if actual_tags else None,
    )

    # Validate all files in the stack directory are explicitly tracked in srcs
    tf_untracked_files_test(
        name = name + "_untracked_files_test",
        srcs = srcs,
        testonly = True,
        size = "small",
        tags = actual_tags if actual_tags else None,
    )

    # Create validation test (unless skip_validation is True)
    if not skip_validation:
        # Create per-stack provider mirror with providers from all modules
        provider_mirror_name = name + "_provider_mirror"

        # Collect provider aliases from modules
        # For now, we'll rely on the modules to provide their providers
        # and use the global registry as fallback
        if actual_modules:
            tf_module_provider_mirror(
                name = provider_mirror_name,
                providers = [],  # Will be populated from modules
                visibility = visibility,
                testonly = True,
            )
            provider_registry = ":" + provider_mirror_name
        else:
            provider_registry = "@tf_provider_registry//:unpacked_providers"

        tf_stack_validate_test(
            name = name + "_validate_test",
            stack = ":" + name,
            provider_registry = provider_registry,
            visibility = visibility,
            testonly = True,
            size = "medium",  # Stack validation may take longer
            tags = actual_tags if actual_tags else None,
        )

    # Create file export target
    tf_stack_file_export(
        name = name + "_file_export",
        stack = ":" + name,
        visibility = visibility,
        testonly = testonly,
    )

    # Create generate_versions target for tf_regenerate_all compatibility
    # This reports provider configuration inherited from modules
    tf_stack_generate_versions(
        name = name + "_generate_versions",
        stack = ":" + name,
        provider_configurations = actual_provider_configurations,
        visibility = visibility,
        testonly = testonly,
    )

tf_stack = macro(
    doc = """Creates a Terraform Stack with comprehensive test suite.

    This macro creates multiple targets:
    - name: The main stack target
    - name_srcs: Filegroup of all sources
    - name_format_test: Format checking test for HCL files
    - name_format: Format fixer for HCL files
    - name_validate_test: Stack validation test (terraform stacks validate)
    - name_deps_test: Component dependency validation test
    - name_untracked_files_test: Test that no untracked files exist
    - name_file_export: Export stack to a directory
    """,
    implementation = _tf_stack_impl,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            configurable = False,
            doc = "Source files (.tfcomponent.hcl, .tfdeploy.hcl, and data files)",
        ),
        "modules": attr.label_list(
            configurable = False,
            doc = "List of tf_module targets referenced by components",
        ),
        "module_aliases": attr.string_dict(
            configurable = False,
            doc = "Dict mapping module label strings to custom component names (e.g., {'//path/to:module': 'custom_name'})",
        ),
        "providers": attr.label_list(
            configurable = False,
            doc = "Additional provider_mirror targets (optional)",
        ),
        "tflint_config": attr.label(
            allow_single_file = True,
            configurable = False,
            doc = "TFLint configuration file (for template modules)",
        ),
        "skip_validation": attr.bool(
            default = False,
            configurable = False,
            doc = "Skip terraform stacks validate test",
        ),
        "terraform_version": attr.string(
            configurable = False,
            doc = "Terraform version constraint (defaults to 1.14.1)",
        ),
        "testonly": attr.bool(
            default = False,
            configurable = False,
            doc = "Whether this is a test-only stack",
        ),
        "tags": attr.string_list(
            configurable = False,
            doc = "Tags to apply to test targets",
        ),
    },
)
