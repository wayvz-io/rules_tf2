"""Public API macro for creating Terraform modules with comprehensive testing"""

load("//tf2/internal:organization.bzl", "tf_organization_check_test", "tf_reorganize")
load("//tf2/tfcore:deps.bzl", "tf_module_deps_test")
load("//tf2/tfcore:module.bzl", "tf_module_deps", "tf_module_rule")
load("//tf2/tfcore:test.bzl", "tf_test")
load("//tf2/tfcore:validate.bzl", "tf_validate_test")
load("//tf2/tfcore/versions:lockfile.bzl", "tf_generate_lockfile_for_validation", "tf_no_lockfile_check_test")
load("//tf2/tfcore/versions:versions.bzl", "tf_generate_versions", "tf_generate_versions_from_mirrors", "tf_versions_check_test")
load("//tf2/tfdocs:generator.bzl", "tf_doc_test", "tf_generate_docs")
load("//tf2/tflint:config.bzl", "tf_generate_tflint_config")
load("//tf2/tflint:format.bzl", "tf_format", "tf_format_test")
load("//tf2/tflint:test.bzl", "tf_lint", "tf_lint_test")
load("//tf2/tflint:validate.bzl", "tf_tflint_fix", "tf_tflint_validate_test")

def tf_module(
        name,
        srcs = None,
        deps = None,
        modules = None,
        providers = None,
        tflint_config = None,
        tfdoc_config = None,
        skip_validation = None,
        terraform_version = None,
        visibility = None,
        testonly = None,
        tags = None,
        **kwargs):
    """Creates a Terraform module with associated build and test targets.

    This macro creates multiple targets:
    - name: The main module target
    - name_deps: Module dependencies target (if deps specified)
    - name_validate_test: Validation test (if not skip_validation)
    - name_format_test: Format checking test
    - name_doc_test: Documentation validation test (if README.md exists)
    - name_lint_test: Linting test
    - name_versions_check_test: Provider versions validation test
    - name_generate_versions: Generate terraform.tf versions
    - name_generate_docs: Generate README.md
    - name_no_lockfile_test: Test that no committed lockfile exists

    Args:
        name: Name of the module
        srcs: Source files (defaults to all .tf and .tf.json files)
        deps: Dependencies on other tf_module targets
        modules: Nested modules in this module (for complex deployments)
        providers: List of provider_mirror targets
        tflint_config: TFLint configuration file
        tfdoc_config: terraform-docs configuration file
        skip_validation: Skip terraform validate test (for template modules)
        terraform_version: Terraform version constraint
        visibility: Visibility of the module
        testonly: Whether this is a test-only module
        tags: Tags to apply to test targets
        **kwargs: Additional arguments passed to the underlying rule
    """
    
    # Default to all files in the module directory if srcs not specified
    # This follows the Terraform convention that modules include all files in their directory
    if srcs == None:
        srcs = native.glob(["**/*"], exclude = ["*.bzl", "*.bazel", "BUILD", "BUILD.bazel", "WORKSPACE", "WORKSPACE.bazel", "*.gen.tf", "test_data/**/*"])

    # The glob pattern above already includes all .tf files
    # No need to explicitly add versions.tf - it will be included if it exists

    # Create the dependencies filegroup
    if deps:
        tf_module_deps(
            name = name + "_deps",
            deps = deps,
            visibility = ["//visibility:private"],
            testonly = testonly,
        )
        module_deps = [":" + name + "_deps"]
    else:
        module_deps = []

    # Require providers list (unless modules are specified that can provide them)
    if not providers and not modules:
        fail("providers attribute is required for tf_module (unless modules are specified that provide them)")

    # Generate versions configuration from providers
    # Include nested modules to collect their providers
    tf_generate_versions_from_mirrors(
        name = name + "_provider_config",
        providers = providers,
        modules = modules,  # Pass modules to collect their providers
        terraform_version = terraform_version or "1.13.2",  # Use configured version from tf_tools
        visibility = ["//visibility:private"],
        testonly = testonly,
    )
    actual_provider_configurations = ":" + name + "_provider_config"
    
    # Create the main module rule  
    tf_module_rule(
        name = name,
        srcs = srcs + module_deps,
        deps = deps or [],
        modules = modules or [],
        provider_configurations = actual_provider_configurations,
        tflint_config = tflint_config,
        visibility = visibility,
        testonly = testonly,
        **kwargs
    )

    # Create format test and formatter (only for .tf files)
    tf_srcs = [src for src in srcs if src.endswith(".tf")]
    if tf_srcs:
        tf_format_test(
            name = name + "_format_test",
            srcs = tf_srcs,
            visibility = ["//visibility:private"],
            testonly = True,
            size = "small",
            tags = tags,
        )

        tf_format(
            name = name + "_format",
            srcs = tf_srcs,
            visibility = visibility,
        )

    # Create doc test if README.md exists
    if "README.md" in native.glob(["README.md"], allow_empty = True):
        tf_doc_test(
            name = name + "_doc_test",
            srcs = srcs,
            config = tfdoc_config,
            visibility = ["//visibility:private"],
            testonly = True,
            size = "small",
            tags = tags,
        )

        tf_generate_docs(
            name = name + "_generate_docs",
            config = tfdoc_config,
            visibility = visibility,
        )
    
    # Create lint test (always runs)
    tf_lint_test(
        name = name + "_lint_test",
        srcs = srcs,
        config = tflint_config,
        visibility = ["//visibility:private"],
        testonly = True,
        size = "small",
        tags = tags,
    )
    
    # Create module dependency test (always runs)
    tf_module_deps_test(
        name = name + "_deps_test",
        module = ":" + name,
        srcs = srcs,
        visibility = ["//visibility:private"],
        testonly = True,
        size = "small",
        tags = tags,
    )

    # Create versions check test and generator if provider configurations are specified
    if actual_provider_configurations:
        tf_versions_check_test(
            name = name + "_versions_check_test",
            srcs = srcs,
            provider_configurations = actual_provider_configurations,
            visibility = ["//visibility:private"],
            testonly = True,
            size = "small",
            tags = tags,
        )

        tf_generate_versions(
            name = name + "_generate_versions",
            provider_configurations = actual_provider_configurations,
            visibility = visibility,
            testonly = testonly,
        )

    # Create organization check test and reorganize target
    tf_organization_check_test(
        name = name + "_organization_check_test",
        srcs = srcs,
        visibility = ["//visibility:private"],
        testonly = True,
        size = "small",
        tags = tags,
    )

    tf_reorganize(
        name = name + "_reorganize",
        visibility = visibility,
    )

    # Create new hybrid tflint validation test
    # Use processed sources if modules exist, otherwise raw sources (same logic as validate_test)
    tflint_srcs = [":" + name + "_processed"] if modules else srcs
    tf_tflint_validate_test(
        name = name + "_tflint_validate_test",
        srcs = tflint_srcs,
        provider_configurations = actual_provider_configurations if actual_provider_configurations else None,
        visibility = ["//visibility:private"],
        testonly = True,
        size = "small",
        tags = tags,
    )

    # Create new hybrid tflint fix target
    tf_tflint_fix(
        name = name + "_tflint_fix",
        provider_configurations = actual_provider_configurations if actual_provider_configurations else None,
        visibility = visibility,
        testonly = testonly,
    )

    # For modules with nested modules, create a processed filegroup (used by both tests and validation)
    if modules:
        native.filegroup(
            name = name + "_processed",
            srcs = [":" + name],
            visibility = ["//visibility:private"],
        )

    # Create test targets for any .tftest.hcl files
    test_files = native.glob(["*.tftest.hcl", "*.tftest.json"])
    if test_files:
        # Use unpacked providers for filesystem_mirror
        provider_registry = "@tf_provider_registry//:unpacked_providers"

        # For modules with nested modules, we need to use the processed output
        if modules:
            test_srcs = [":" + name + "_processed"]
        else:
            test_srcs = srcs

        tf_test(
            name = name + "_test",
            srcs = test_srcs,
            test_files = test_files,
            lock_file = ":" + name + "_generated_lock",
            provider_registry = provider_registry,
            visibility = ["//visibility:private"],
            testonly = True,
            size = "small",
            tags = tags,
        )

    # Create validation test (unless skip_validation is True)
    if not skip_validation:
        # Use unpacked providers for filesystem_mirror
        provider_registry = "@tf_provider_registry//:unpacked_providers"

        # For modules with nested modules, we need to use the processed output
        if modules:
            validate_srcs = [":" + name + "_processed"]
        else:
            validate_srcs = srcs

        # Generate lockfile for validation
        tf_generate_lockfile_for_validation(
            name = name + "_generated_lock",
            provider_locks = "@tf_provider_registry//:provider_locks.bzl",
            versions_json = actual_provider_configurations,
            visibility = ["//visibility:private"],
            testonly = testonly,
        )

        tf_validate_test(
            name = name + "_validate_test",
            srcs = validate_srcs,
            lock_file = ":" + name + "_generated_lock",
            provider_registry = provider_registry,
            visibility = ["//visibility:private"],
            testonly = True,
            size = "small",
            tags = tags,
        )

    # Create test to ensure no committed lockfile exists
    tf_no_lockfile_check_test(
        name = name + "_no_lockfile_test",
        srcs = srcs,
        visibility = ["//visibility:private"],
        testonly = True,
        size = "small",
        tags = tags,
    )
