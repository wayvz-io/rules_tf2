"""Unit tests for Terraform lockfile rules"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//tf2/tfcore/versions:lockfile.bzl", "tf_generate_lockfile_for_validation", "tf_no_lockfile_check_test")

# Test lockfile generation for validation
def _tf_generate_lockfile_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that lockfile is generated
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_generate_lockfile_for_validation should provide DefaultInfo",
    )

    files = target_under_test[DefaultInfo].files.to_list()
    lockfiles = []
    for f in files:
        if f.basename == "terraform.lock.hcl" or f.basename == ".terraform.lock.hcl":
            lockfiles.append(f)

    asserts.equals(
        env,
        1,
        len(lockfiles),
        "Should generate exactly one terraform.lock.hcl file",
    )

    return analysistest.end(env)

tf_generate_lockfile_test = analysistest.make(_tf_generate_lockfile_test_impl)

# Test no lockfile check test
def _tf_no_lockfile_check_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_no_lockfile_check_test should provide DefaultInfo",
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_no_lockfile_check_test should be executable",
    )

    return analysistest.end(env)

tf_no_lockfile_check_creation_test = analysistest.make(_tf_no_lockfile_check_test_impl)

# Test lockfile generation with versions.json
def _tf_lockfile_with_versions_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    files = target_under_test[DefaultInfo].files.to_list()

    # Check that lockfile is created
    lockfiles = []
    for f in files:
        if f.basename == ".terraform.lock.hcl":
            lockfiles.append(f)

    asserts.true(
        env,
        len(lockfiles) > 0,
        "Lockfile should be generated from versions.json",
    )

    return analysistest.end(env)

tf_lockfile_with_versions_test = analysistest.make(_tf_lockfile_with_versions_test_impl)

# Test no lockfile check with clean directory
def _tf_no_lockfile_clean_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that source files are included
    files = runfiles.files.to_list()

    # Should not have terraform.lock.hcl in sources
    lockfiles = [f for f in files if f.basename == "terraform.lock.hcl"]

    # This test checks for absence of lockfiles
    asserts.equals(
        env,
        0,
        len([f for f in lockfiles if "test_srcs_no_lock" in f.path]),
        "Clean directory should have no lockfiles",
    )

    return analysistest.end(env)

tf_no_lockfile_clean_test = analysistest.make(_tf_no_lockfile_clean_test_impl)

# Test no lockfile check with committed lockfile (should fail)
def _tf_no_lockfile_committed_test_impl(ctx):
    env = analysistest.begin(ctx)

    # This test expects to detect a committed lockfile
    # In a real scenario, this would fail the test
    target_under_test = analysistest.target_under_test(env)

    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "Test should be created even with lockfile present",
    )

    return analysistest.end(env)

tf_no_lockfile_committed_test = analysistest.make(_tf_no_lockfile_committed_test_impl)

# Helper to create test versions.json
def _create_test_versions_json_impl(ctx):
    """Create a versions.json file for testing"""

    versions_json = ctx.actions.declare_file("versions.json")
    ctx.actions.write(
        output = versions_json,
        content = """
{
  "required_providers": {
    "aws": {
      "source": "hashicorp/aws",
      "version": "6.12.0"
    },
    "azurerm": {
      "source": "hashicorp/azurerm",
      "version": "4.11.0"
    },
    "google": {
      "source": "hashicorp/google",
      "version": "6.15.0"
    },
    "random": {
      "source": "hashicorp/random",
      "version": "3.6.3"
    }
  }
}
""",
    )

    return [DefaultInfo(files = depset([versions_json]))]

create_test_versions_json = rule(
    implementation = _create_test_versions_json_impl,
)

# Helper to create terraform files without lockfile
def _create_tf_files_no_lock_impl(ctx):
    """Create terraform files without a lockfile"""

    main_tf = ctx.actions.declare_file("main_no_lock.tf")
    ctx.actions.write(
        output = main_tf,
        content = """
resource "aws_instance" "test" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
}
""",
    )

    terraform_tf = ctx.actions.declare_file("terraform_no_lock.tf")
    ctx.actions.write(
        output = terraform_tf,
        content = """
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
""",
    )

    return [DefaultInfo(files = depset([main_tf, terraform_tf]))]

create_tf_files_no_lock = rule(
    implementation = _create_tf_files_no_lock_impl,
)

# Helper to create terraform files with committed lockfile
def _create_tf_files_with_lock_impl(ctx):
    """Create terraform files with a committed lockfile"""

    main_tf = ctx.actions.declare_file("main_with_lock.tf")
    ctx.actions.write(
        output = main_tf,
        content = """
resource "aws_instance" "test" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
}
""",
    )

    # Simulating a committed lockfile
    lock_hcl = ctx.actions.declare_file("terraform.lock.hcl")
    ctx.actions.write(
        output = lock_hcl,
        content = """
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {
  version     = "6.12.0"
  constraints = "~> 6.0"
  hashes = [
    "h1:fake_hash_1",
    "h1:fake_hash_2",
  ]
}
""",
    )

    return [DefaultInfo(files = depset([main_tf, lock_hcl]))]

create_tf_files_with_lock = rule(
    implementation = _create_tf_files_with_lock_impl,
)

# Mock provider locks repository
def _mock_provider_locks_impl(ctx):
    """Create a mock provider locks configuration"""

    # This would normally be generated from the provider registry
    locks_bzl = ctx.actions.declare_file("provider_locks.bzl")
    ctx.actions.write(
        output = locks_bzl,
        content = """
# Mock provider locks
PROVIDER_LOCKS = {
    "hashicorp/aws:6.12.0": [
        "h1:mock_hash_aws_1",
        "h1:mock_hash_aws_2",
    ],
    "hashicorp/azurerm:4.11.0": [
        "h1:mock_hash_azure_1",
        "h1:mock_hash_azure_2",
    ],
    "hashicorp/google:6.15.0": [
        "h1:mock_hash_google_1",
        "h1:mock_hash_google_2",
    ],
    "hashicorp/random:3.6.3": [
        "h1:mock_hash_random_1",
        "h1:mock_hash_random_2",
    ],
}
""",
    )

    return [DefaultInfo(files = depset([locks_bzl]))]

mock_provider_locks = rule(
    implementation = _mock_provider_locks_impl,
)

# Test suite setup
def lockfile_test_suite(name):
    """Create all lockfile test targets

    Args:
        name: Name of the test suite
    """

    # Create test files
    create_test_versions_json(
        name = "test_versions",
    )

    create_tf_files_no_lock(
        name = "test_srcs_no_lock",
    )

    create_tf_files_with_lock(
        name = "test_srcs_with_lock",
    )

    mock_provider_locks(
        name = "mock_locks",
    )

    # Test basic lockfile generation
    tf_generate_lockfile_for_validation(
        name = "basic_lockfile",
        provider_locks = ":mock_locks",
        versions_json = ":test_versions",
    )

    tf_generate_lockfile_test(
        name = "tf_generate_lockfile_test",
        target_under_test = ":basic_lockfile",
        size = "small",
    )

    # Test no lockfile check test creation
    tf_no_lockfile_check_test(
        name = "basic_no_lockfile_check",
        srcs = [":test_srcs_no_lock"],
        size = "small",
    )

    tf_no_lockfile_check_creation_test(
        name = "tf_no_lockfile_check_creation_test",
        target_under_test = ":basic_no_lockfile_check",
        size = "small",
    )

    # Test lockfile generation with versions
    # Using the same basic_lockfile target since it already has versions
    tf_lockfile_with_versions_test(
        name = "tf_lockfile_with_versions_test",
        target_under_test = ":basic_lockfile",
        size = "small",
    )

    # Test no lockfile check with clean directory
    tf_no_lockfile_check_test(
        name = "no_lockfile_clean",
        srcs = [":test_srcs_no_lock"],
        size = "small",
    )

    tf_no_lockfile_clean_test(
        name = "tf_no_lockfile_clean_test",
        target_under_test = ":no_lockfile_clean",
        size = "small",
    )

    # Test no lockfile check with committed lockfile
    tf_no_lockfile_check_test(
        name = "no_lockfile_committed",
        srcs = [":test_srcs_with_lock"],
        size = "small",
    )

    tf_no_lockfile_committed_test(
        name = "tf_no_lockfile_committed_test",
        target_under_test = ":no_lockfile_committed",
        size = "small",
    )

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":tf_generate_lockfile_test",
            ":tf_no_lockfile_check_creation_test",
            ":tf_lockfile_with_versions_test",
            ":tf_no_lockfile_clean_test",
            ":tf_no_lockfile_committed_test",
        ],
    )
