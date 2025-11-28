"""Public API macro for creating Terraform modules with comprehensive testing"""

load("//tf2/internal:organization.bzl", "tf_organization_check_test", "tf_reorganize")
load("//tf2/internal:sources_validation.bzl", "tf_untracked_files_test")
load("//tf2/tfcore:deps.bzl", "tf_module_deps_test")
load("//tf2/tfcore:export.bzl", "tf_file_export")
load("//tf2/tfcore:module.bzl", "tf_module_deps", "tf_module_rule")
load("//tf2/tfcore:test.bzl", "tf_test")
load("//tf2/tfcore:validate.bzl", "tf_validate_test")
load("//tf2/tfcore/versions:lockfile.bzl", "tf_generate_lockfile_for_validation", "tf_no_lockfile_check_test")
load("//tf2/tfcore/versions:versions.bzl", "tf_generate_versions", "tf_generate_versions_from_mirrors", "tf_versions_check_test")
load("//tf2/tfdocs:generator.bzl", "tf_doc_test", "tf_generate_docs")
load("//tf2/tflint:format.bzl", "tf_format", "tf_format_test")
load("//tf2/tflint:test.bzl", "tf_lint_test")
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

    # Validate srcs attribute is provided (mandatory)
    if srcs == None:
        fail("tf_module '{}' requires explicit srcs attribute. ".format(name) +
             "Please add: srcs = glob([\"*.tf\"]) + [\"README.md\"]")


    # Create the dependencies filegroup
    if deps:
        tf_module_deps(
            name = name + "_deps",
            deps = deps,
            visibility = visibility,
            testonly = testonly,
        )
        module_deps = [":" + name + "_deps"]
    else:
        module_deps = []

    # Split sources for better ibazel performance:
    # - _sources: .tf files for terraform operations (validate, test, tflint)
    # - _docs: README.md and doc config for documentation generation
    # This prevents doc edits from triggering full module rebuilds

    # Extract documentation files
    doc_files = [f for f in srcs if f.endswith("README.md") or f.endswith(".tfdoc.yaml") or f.endswith(".terraform-docs.yml")]
    # Extract terraform source files (everything except docs)
    tf_source_files = [f for f in srcs if f not in doc_files]

    # Create separate filegroups for sources and docs
    native.filegroup(
        name = name + "_sources",
        srcs = tf_source_files,
        visibility = visibility,
    )

    if doc_files:
        native.filegroup(
            name = name + "_docs",
            srcs = doc_files,
            visibility = visibility,
        )

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
        visibility = visibility,
        testonly = testonly,
    )
    actual_provider_configurations = ":" + name + "_provider_config"

    # Generate lockfile for module - used by all terraform operations
    generated_lock_name = name + "_generated_lock"
    if not native.existing_rule(generated_lock_name):
        tf_generate_lockfile_for_validation(
            name = generated_lock_name,
            provider_locks = "@tf_provider_registry//:provider_locks.json",
            versions_json = actual_provider_configurations,
            visibility = visibility,
            testonly = testonly,
        )

    # Create the main module rule
    tf_module_rule(
        name = name,
        srcs = srcs + module_deps,
        deps = deps or [],
        modules = modules or [],
        provider_configurations = actual_provider_configurations,
        tflint_config = tflint_config,
        lock_file = ":" + generated_lock_name,
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
            visibility = visibility,
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
    # Note: terraform-docs needs both .tf files and README.md to validate
    if "README.md" in native.glob(["README.md"], allow_empty = True):
        tf_doc_test(
            name = name + "_doc_test",
            srcs = srcs,
            config = tfdoc_config,
            visibility = visibility,
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
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = tags,
    )

    # Create module dependency test (always runs)
    tf_module_deps_test(
        name = name + "_deps_test",
        module = ":" + name,
        srcs = srcs,
        visibility = visibility,
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
            visibility = visibility,
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
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = tags,
    )

    tf_reorganize(
        name = name + "_reorganize",
        visibility = visibility,
    )

    # Validate all .tf files in the module directory are explicitly tracked in srcs
    tf_untracked_files_test(
        name = name + "_untracked_files_test",
        srcs = srcs,
        testonly = True,
        size = "small",
        tags = tags,
    )

    # Use appropriate source files for validation:
    # - Modules with nested modules: use processed output (stages nested modules)
    # - Simple modules: use direct sources for ibazel file watching
    if modules:
        tflint_srcs = [":" + name + "_processed"]
    else:
        tflint_srcs = [":" + name + "_sources"]
    tf_tflint_validate_test(
        name = name + "_tflint_validate_test",
        srcs = tflint_srcs,
        provider_configurations = actual_provider_configurations if actual_provider_configurations else None,
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = tags,
    )

    # Create tflint fix target
    tf_tflint_fix(
        name = name + "_tflint_fix",
        provider_configurations = actual_provider_configurations if actual_provider_configurations else None,
        visibility = visibility,
        testonly = testonly,
    )

    # Create processed filegroup for modules with nested modules
    if modules:
        native.filegroup(
            name = name + "_processed",
            srcs = [":" + name],
            visibility = visibility,
        )

    # Create file export target
    tf_file_export(
        name = name + "_file_export",
        module = ":" + name,
        visibility = visibility,
        testonly = testonly,
    )

    # Auto-discover and create test targets for .tftest.hcl files
    # Note: This will be deprecated in favor of explicit tf_test declarations
    test_files = native.glob(["*.tftest.hcl", "*.tftest.json"])
    if test_files:
        provider_registry = "@tf_provider_registry//:unpacked_providers"
        test_srcs = [":" + name + "_processed"] if modules else [":" + name + "_sources"]

        tf_test(
            name = name + "_tftest",
            srcs = test_srcs,
            test_files = test_files,
            lock_file = ":" + name + "_generated_lock",
            provider_registry = provider_registry,
            visibility = visibility,
            testonly = True,
            size = "small",
            tags = tags,
        )

    # Create validation test (unless skip_validation is True)
    if not skip_validation:
        provider_registry = "@tf_provider_registry//:unpacked_providers"
        validate_srcs = [":" + name + "_processed"] if modules else [":" + name + "_sources"]

        tf_validate_test(
            name = name + "_validate_test",
            srcs = validate_srcs,
            lock_file = ":" + name + "_generated_lock",
            provider_registry = provider_registry,
            visibility = visibility,
            testonly = True,
            size = "small",
            tags = tags,
        )

    # Create test to ensure no committed lockfile exists
    tf_no_lockfile_check_test(
        name = name + "_no_lockfile_test",
        srcs = srcs,
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = tags,
    )
