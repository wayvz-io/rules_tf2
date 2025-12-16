"""Public API macro for creating Terraform modules with comprehensive testing"""

load("//tf2/internal:organization.bzl", "tf_reorganize")
load("//tf2/internal:sources_validation.bzl", "tf_untracked_files_test")
load("//tf2/providers/module:module_provider_mirror.bzl", "tf_module_provider_mirror")
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

def _extract_provider_aliases(providers):
    """Extract provider alias names from provider label strings.

    Args:
        providers: List of provider labels like ["@tf_provider_registry:aws_6"]

    Returns:
        List of alias names like ["aws_6"]
    """
    aliases = []
    for provider in providers:
        # Handle both @tf_provider_registry:alias and @tf_provider_registry//:alias formats
        if ":" in str(provider):
            alias = str(provider).split(":")[-1]
            aliases.append(alias)
    return aliases

def _tf_module_impl(
        name,
        visibility,
        srcs,
        deps,
        modules,
        providers,
        tflint_config,
        tfdoc_config,
        skip_validation,
        terraform_version,
        testonly,
        tags):
    """Implementation of tf_module symbolic macro.

    Creates a Terraform module with associated build and test targets:
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
    """

    # Normalize None values to empty lists for iteration
    actual_deps = deps if deps else []
    actual_modules = modules if modules else []
    actual_providers = providers if providers else []
    actual_tags = tags if tags else []

    # Require providers list (unless modules are specified that can provide them)
    if not actual_providers and not actual_modules:
        fail("providers attribute is required for tf_module (unless modules are specified that provide them)")

    # Create the dependencies filegroup
    if actual_deps:
        tf_module_deps(
            name = name + "_deps",
            deps = actual_deps,
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
    doc_files = [f for f in srcs if str(f).endswith("README.md") or str(f).endswith(".tfdoc.yaml") or str(f).endswith(".terraform-docs.yml")]

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

    # Generate versions configuration from providers
    # Include nested modules to collect their providers
    tf_generate_versions_from_mirrors(
        name = name + "_provider_config",
        providers = actual_providers,
        modules = actual_modules,  # Pass modules to collect their providers
        terraform_version = terraform_version if terraform_version else "1.13.2",
        visibility = visibility,
        testonly = testonly,
    )
    actual_provider_configurations = ":" + name + "_provider_config"

    # Generate lockfile for module - used by all terraform operations
    generated_lock_name = name + "_generated_lock"
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
        srcs = list(srcs) + module_deps,
        deps = actual_deps,
        modules = actual_modules,
        provider_configurations = actual_provider_configurations,
        tflint_config = tflint_config,
        lock_file = ":" + generated_lock_name,
        visibility = visibility,
        testonly = testonly,
    )

    # Create format test and formatter (only for .tf files)
    tf_srcs = [src for src in srcs if str(src).endswith(".tf")]
    if tf_srcs:
        tf_format_test(
            name = name + "_format_test",
            srcs = tf_srcs,
            visibility = visibility,
            testonly = True,
            size = "small",
            tags = actual_tags if actual_tags else None,
        )

        tf_format(
            name = name + "_format",
            srcs = tf_srcs,
            visibility = visibility,
        )

    # Create doc test if README.md exists in srcs
    # Note: terraform-docs needs both .tf files and README.md to validate
    has_readme = any([str(f).endswith("README.md") for f in srcs])
    if has_readme:
        tf_doc_test(
            name = name + "_doc_test",
            srcs = srcs,
            config = tfdoc_config,
            visibility = visibility,
            testonly = True,
            size = "small",
            tags = actual_tags if actual_tags else None,
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
        tags = actual_tags if actual_tags else None,
    )

    # Create module dependency test (always runs)
    tf_module_deps_test(
        name = name + "_deps_test",
        module = ":" + name,
        srcs = srcs,
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = actual_tags if actual_tags else None,
    )

    # Create versions check test and generator
    tf_versions_check_test(
        name = name + "_versions_check_test",
        srcs = srcs,
        provider_configurations = actual_provider_configurations,
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = actual_tags if actual_tags else None,
    )

    tf_generate_versions(
        name = name + "_generate_versions",
        provider_configurations = actual_provider_configurations,
        visibility = visibility,
        testonly = testonly,
    )

    # Create reorganize target (organization check removed for performance)
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
        tags = actual_tags if actual_tags else None,
    )

    # Use appropriate source files for validation:
    # - Modules with nested modules: use processed output (stages nested modules)
    # - Simple modules: use direct sources for ibazel file watching
    if actual_modules:
        tflint_srcs = [":" + name + "_processed"]
    else:
        tflint_srcs = [":" + name + "_sources"]
    tf_tflint_validate_test(
        name = name + "_tflint_validate_test",
        srcs = tflint_srcs,
        provider_configurations = actual_provider_configurations,
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = actual_tags if actual_tags else None,
    )

    # Create tflint fix target
    tf_tflint_fix(
        name = name + "_tflint_fix",
        provider_configurations = actual_provider_configurations,
        visibility = visibility,
        testonly = testonly,
    )

    # Create processed filegroup for modules with nested modules
    if actual_modules:
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

    # Create validation test (unless skip_validation is True)
    if not skip_validation:
        # Create per-module provider mirror with only the needed providers
        # This ensures each module only caches the providers it actually uses
        provider_mirror_name = name + "_provider_mirror"
        provider_aliases = _extract_provider_aliases(actual_providers)

        # Also collect provider aliases from nested modules if any
        # (Their providers are already included via tf_generate_versions_from_mirrors)
        if provider_aliases:
            tf_module_provider_mirror(
                name = provider_mirror_name,
                providers = provider_aliases,
                visibility = visibility,
                testonly = True,
            )
            provider_registry = ":" + provider_mirror_name
        else:
            # Fallback to global registry if no direct providers specified
            # This shouldn't happen with properly configured modules
            provider_registry = "@tf_provider_registry//:unpacked_providers"

        validate_srcs = [":" + name + "_processed"] if actual_modules else [":" + name + "_sources"]

        tf_validate_test(
            name = name + "_validate_test",
            srcs = validate_srcs,
            lock_file = ":" + name + "_generated_lock",
            provider_registry = provider_registry,
            visibility = visibility,
            testonly = True,
            size = "small",
            tags = actual_tags if actual_tags else None,
        )

    # Create test to ensure no committed lockfile exists
    tf_no_lockfile_check_test(
        name = name + "_no_lockfile_test",
        srcs = srcs,
        visibility = visibility,
        testonly = True,
        size = "small",
        tags = actual_tags if actual_tags else None,
    )

tf_module = macro(
    doc = """Creates a Terraform module with comprehensive test suite.

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
    """,
    implementation = _tf_module_impl,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
            configurable = False,
            doc = "Source files (.tf files and README.md). Use glob([\"*.tf\"]) + [\"README.md\"]",
        ),
        "deps": attr.label_list(
            configurable = False,
            doc = "Dependencies on other tf_module targets",
        ),
        "modules": attr.label_list(
            configurable = False,
            doc = "Nested modules in this module (for complex deployments)",
        ),
        "providers": attr.label_list(
            configurable = False,
            doc = "List of provider_mirror targets like @tf_provider_registry//:aws_6",
        ),
        "tflint_config": attr.label(
            allow_single_file = True,
            configurable = False,
            doc = "TFLint configuration file",
        ),
        "tfdoc_config": attr.label(
            allow_single_file = True,
            configurable = False,
            doc = "terraform-docs configuration file",
        ),
        "skip_validation": attr.bool(
            default = False,
            configurable = False,
            doc = "Skip terraform validate test (for template modules)",
        ),
        "terraform_version": attr.string(
            configurable = False,
            doc = "Terraform version constraint (defaults to 1.13.2)",
        ),
        "testonly": attr.bool(
            default = False,
            configurable = False,
            doc = "Whether this is a test-only module",
        ),
        "tags": attr.string_list(
            configurable = False,
            doc = "Tags to apply to test targets",
        ),
    },
)
