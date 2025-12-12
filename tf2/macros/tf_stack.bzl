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

def _extract_provider_aliases(modules):
    """Extract provider alias names from modules.

    Args:
        modules: List of tf_module labels

    Returns:
        List of provider alias names
    """

    # Provider aliases will be extracted from modules at analysis time
    # For now, return an empty list - the tf_generate_versions_from_mirrors
    # rule will handle provider aggregation
    return []

def tf_stack(
        name = "tf_stack",
        srcs = None,
        modules = None,
        providers = None,
        tflint_config = None,
        skip_validation = None,
        terraform_version = None,
        visibility = None,
        testonly = None,
        tags = None,
        **kwargs):
    """Creates a Terraform Stack with associated build and test targets.

    This macro creates multiple targets:
    - name: The main stack target
    - name_srcs: Filegroup of all sources
    - name_format_test: Format checking test for HCL files
    - name_format: Format fixer for HCL files
    - name_validate_test: Stack validation test (terraform stacks validate)
    - name_deps_test: Component dependency validation test
    - name_untracked_files_test: Test that no untracked files exist
    - name_file_export: Export stack to a directory

    Args:
        name: Name of the stack (defaults to "tf_stack")
        srcs: Source files (.tfcomponent.hcl, .tfdeploy.hcl, and data files)
        modules: List of tf_module targets referenced by components
        providers: Additional provider_mirror targets (optional)
        tflint_config: TFLint configuration file (for template modules)
        skip_validation: Skip terraform stacks validate test
        terraform_version: Terraform version constraint
        visibility: Visibility of the stack
        testonly: Whether this is a test-only stack
        tags: Tags to apply to test targets
        **kwargs: Additional arguments passed to the underlying rule
    """

    # Validate srcs attribute is provided
    if srcs == None:
        fail("tf_stack '{}' requires explicit srcs attribute. ".format(name) +
             "Please add: srcs = glob([\"*.tfcomponent.hcl\", \"*.tfdeploy.hcl\"])")

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
        providers = providers or [],
        modules = modules or [],
        terraform_version = terraform_version or "1.14.1",
        visibility = visibility,
        testonly = testonly,
    )
    actual_provider_configurations = ":" + name + "_provider_config"

    # Generate lockfile for the stack
    generated_lock_name = name + "_generated_lock"
    if not native.existing_rule(generated_lock_name):
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
        modules = modules or [],
        lock_file = ":" + generated_lock_name,
        terraform_version = terraform_version or "1.14.1",
        visibility = visibility,
        testonly = testonly,
        **kwargs
    )

    # Create format test and formatter for HCL files
    tf_stack_format_test(
        name = name + "_format_test",
        stack = ":" + name,
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = tags,
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
        tags = tags,
    )

    # Validate all files in the stack directory are explicitly tracked in srcs
    tf_untracked_files_test(
        name = name + "_untracked_files_test",
        srcs = srcs,
        testonly = True,
        size = "small",
        tags = tags,
    )

    # Create validation test (unless skip_validation is True)
    if not skip_validation:
        # Create per-stack provider mirror with providers from all modules
        provider_mirror_name = name + "_provider_mirror"

        # Collect provider aliases from modules
        # For now, we'll rely on the modules to provide their providers
        # and use the global registry as fallback
        if modules:
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
            tags = tags,
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
