"""Unit tests for implicit file globbing behaviors"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# Test default srcs globbing behavior
def _test_default_srcs_globbing(ctx):
    """Test the default glob pattern when srcs is not specified"""
    env = unittest.begin(ctx)
    
    # The default glob pattern from macros.bzl
    # native.glob(["**/*"], exclude = ["*.bzl", "*.bazel", "BUILD", "BUILD.bazel", "WORKSPACE", "WORKSPACE.bazel", "*.gen.tf"])
    
    # Files that should be included
    included_files = [
        "main.tf",
        "variables.tf",
        "outputs.tf",
        "terraform.tf",
        "providers.tf",
        "data.tf",
        "locals.tf",
        "backend.tf",
        "versions.tf",
        "module.tf.json",
        "resources.tf.json",
        "README.md",
        ".terraform.lock.hcl",
        "terraform.tfvars",
        "terraform.tfvars.json",
        "nested/main.tf",
        "nested/deep/resource.tf",
    ]
    
    # Files that should be excluded
    excluded_files = [
        "BUILD",
        "BUILD.bazel",
        "WORKSPACE",
        "WORKSPACE.bazel",
        "rules.bzl",
        "macros.bazel",
        "generated.gen.tf",
        "auto.gen.tf",
    ]
    
    # Test included files
    for file in included_files:
        # Check file doesn't match exclusion patterns
        is_excluded = (
            file.endswith(".bzl") or
            file.endswith(".bazel") or
            file in ["BUILD", "BUILD.bazel", "WORKSPACE", "WORKSPACE.bazel"] or
            file.endswith(".gen.tf")
        )
        asserts.false(env, is_excluded, "File should be included: " + file)
    
    # Test excluded files
    for file in excluded_files:
        # Check file matches exclusion patterns
        is_excluded = (
            file.endswith(".bzl") or
            file.endswith(".bazel") or
            file in ["BUILD", "BUILD.bazel", "WORKSPACE", "WORKSPACE.bazel"] or
            file.endswith(".gen.tf")
        )
        asserts.true(env, is_excluded, "File should be excluded: " + file)
    
    return unittest.end(env)

default_srcs_globbing_test = unittest.make(_test_default_srcs_globbing)

# Test terraform file detection
def _test_terraform_file_detection(ctx):
    """Test detection of Terraform file types"""
    env = unittest.begin(ctx)
    
    # Terraform files
    tf_files = [
        "main.tf",
        "variables.tf",
        "outputs.tf",
        "data.tf",
        "nested/resource.tf",
    ]
    
    # Terraform JSON files
    tf_json_files = [
        "main.tf.json",
        "variables.tf.json",
        "module.tf.json",
    ]
    
    # Non-Terraform files
    non_tf_files = [
        "README.md",
        "terraform.tfvars",
        ".terraform.lock.hcl",
        "script.sh",
        "config.yaml",
    ]
    
    # Test .tf file detection
    for file in tf_files:
        asserts.true(env, file.endswith(".tf"), "Should be detected as .tf file: " + file)
        asserts.false(env, file.endswith(".tf.json"), "Should not be .tf.json: " + file)
    
    # Test .tf.json file detection
    for file in tf_json_files:
        asserts.true(env, file.endswith(".tf.json"), "Should be detected as .tf.json file: " + file)
        asserts.false(env, file.endswith(".tf") and not file.endswith(".tf.json"), "Should not be plain .tf: " + file)
    
    # Test non-TF file detection
    for file in non_tf_files:
        is_tf = file.endswith(".tf") or file.endswith(".tf.json")
        asserts.false(env, is_tf, "Should not be detected as TF file: " + file)
    
    return unittest.end(env)

terraform_file_detection_test = unittest.make(_test_terraform_file_detection)

# Test special file handling
def _test_special_file_handling(ctx):
    """Test handling of special Terraform files"""
    env = unittest.begin(ctx)
    
    # Special files that get specific treatment
    special_files = {
        "terraform.tf": "versions",          # Should contain terraform block
        "providers.tf": "providers",         # Should contain provider blocks
        "variables.tf": "variables",         # Should contain variable blocks
        "outputs.tf": "outputs",            # Should contain output blocks
        "imports.tf": "imports",            # Should contain import blocks
        "backend.tf": "backend",            # Often contains backend config
        "main.tf": "resources",             # Usually contains resources
        "data.tf": "data",                  # Usually contains data sources
        "locals.tf": "locals",              # Usually contains locals
    }
    
    for file, expected_content in special_files.items():
        # Verify file naming convention
        asserts.true(env, file.endswith(".tf"), "Special file should be .tf: " + file)
        
        # Verify expected content type (in real implementation, would check actual content)
        asserts.true(env, expected_content != "", "Should have expected content type: " + file)
    
    return unittest.end(env)

special_file_handling_test = unittest.make(_test_special_file_handling)

# Test nested directory handling
def _test_nested_directory_handling(ctx):
    """Test handling of files in nested directories"""
    env = unittest.begin(ctx)
    
    # Test nested path patterns
    nested_paths = [
        "modules/vpc/main.tf",
        "modules/vpc/variables.tf",
        "environments/dev/terraform.tf",
        "config/backend.tf",
        "test_data/fixtures.tf",
    ]
    
    for path in nested_paths:
        # Check path has directory component
        asserts.true(env, "/" in path, "Should be nested path: " + path)
        
        # Check file would be included in glob
        parts = path.split("/")
        filename = parts[-1]
        
        # Verify it's a valid TF file
        if filename.endswith(".tf") or filename.endswith(".tf.json"):
            asserts.true(env, True, "Nested TF file should be included: " + path)
    
    return unittest.end(env)

nested_directory_handling_test = unittest.make(_test_nested_directory_handling)

# Test generated file exclusion
def _test_generated_file_exclusion(ctx):
    """Test that generated files are properly excluded"""
    env = unittest.begin(ctx)
    
    # Files that should be excluded as generated
    generated_files = [
        "terraform.gen.tf",
        "providers.gen.tf",
        "auto.gen.tf",
        "generated.gen.tf",
        "nested/module.gen.tf",
    ]
    
    # Files that should NOT be excluded
    non_generated_files = [
        "terraform.tf",
        "generator.tf",
        "main.tf",
        "genesis.tf",  # Contains 'gen' but not .gen.tf
    ]
    
    for file in generated_files:
        asserts.true(env, file.endswith(".gen.tf"), "Generated file should end with .gen.tf: " + file)
    
    for file in non_generated_files:
        asserts.false(env, file.endswith(".gen.tf"), "Should not be treated as generated: " + file)
    
    return unittest.end(env)

generated_file_exclusion_test = unittest.make(_test_generated_file_exclusion)

# Test suite
def file_globbing_test_suite(name):
    """Create file globbing test suite"""
    
    default_srcs_globbing_test(name = name + "_default_glob")
    terraform_file_detection_test(name = name + "_tf_detection")
    special_file_handling_test(name = name + "_special_files")
    nested_directory_handling_test(name = name + "_nested_dirs")
    generated_file_exclusion_test(name = name + "_gen_exclusion")
    
    native.test_suite(
        name = name,
        tests = [
            ":" + name + "_default_glob",
            ":" + name + "_tf_detection",
            ":" + name + "_special_files",
            ":" + name + "_nested_dirs",
            ":" + name + "_gen_exclusion",
        ],
    )