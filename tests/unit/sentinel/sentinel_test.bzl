"""Unit tests for Sentinel rules"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//tf2/sentinel:test.bzl", "tf_sentinel_fmt_test", "tf_sentinel_test")

# Test that sentinel test rule is created correctly
def _tf_sentinel_test_creation_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_sentinel_test should provide DefaultInfo",
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_sentinel_test should be executable",
    )

    return analysistest.end(env)

tf_sentinel_test_creation_test = analysistest.make(_tf_sentinel_test_creation_test_impl)

# Test sentinel test with mock files
def _tf_sentinel_with_mocks_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that mock files are included in runfiles
    files = runfiles.files.to_list()
    sentinel_files = [f for f in files if f.path.endswith(".sentinel")]

    asserts.true(
        env,
        len(sentinel_files) > 0,
        "Sentinel test should include .sentinel files in runfiles",
    )

    return analysistest.end(env)

tf_sentinel_with_mocks_test = analysistest.make(_tf_sentinel_with_mocks_test_impl)

# Test sentinel format test creation
def _tf_sentinel_fmt_test_creation_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_sentinel_fmt_test should provide DefaultInfo",
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_sentinel_fmt_test should be executable",
    )

    return analysistest.end(env)

tf_sentinel_fmt_test_creation_test = analysistest.make(_tf_sentinel_fmt_test_creation_test_impl)

# Test sentinel test includes test HCL files
def _tf_sentinel_with_test_files_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that test HCL files are included in runfiles
    files = runfiles.files.to_list()
    hcl_files = [f for f in files if f.path.endswith(".hcl")]

    asserts.true(
        env,
        len(hcl_files) > 0,
        "Sentinel test should include test .hcl files in runfiles",
    )

    return analysistest.end(env)

tf_sentinel_with_test_files_test = analysistest.make(_tf_sentinel_with_test_files_test_impl)

# Helper to create test sentinel policy file
def _create_sentinel_policy_impl(ctx):
    """Create a simple sentinel policy file"""

    policy = ctx.actions.declare_file("require_tags.sentinel")
    ctx.actions.write(
        output = policy,
        content = """# require_tags.sentinel
# Simple policy for testing

import "tfplan/v2" as tfplan

# Main rule - always passes for testing
main = rule { true }
""",
    )

    return [DefaultInfo(files = depset([policy]))]

create_sentinel_policy = rule(
    implementation = _create_sentinel_policy_impl,
)

# Helper to create test HCL file
def _create_sentinel_test_hcl_impl(ctx):
    """Create a sentinel test HCL file"""

    test_hcl = ctx.actions.declare_file("test/require_tags/pass.hcl")
    ctx.actions.write(
        output = test_hcl,
        content = """# Test case for require_tags policy

mock "tfplan/v2" {
    module {
        source = "../../mocks/mock-tfplan.sentinel"
    }
}

test {
    rules = {
        main = true
    }
}
""",
    )

    return [DefaultInfo(files = depset([test_hcl]))]

create_sentinel_test_hcl = rule(
    implementation = _create_sentinel_test_hcl_impl,
)

# Helper to create mock sentinel file
def _create_sentinel_mock_impl(ctx):
    """Create a sentinel mock file"""

    mock = ctx.actions.declare_file("mocks/mock-tfplan.sentinel")
    ctx.actions.write(
        output = mock,
        content = """# Mock tfplan for testing

resource_changes = {}
""",
    )

    return [DefaultInfo(files = depset([mock]))]

create_sentinel_mock = rule(
    implementation = _create_sentinel_mock_impl,
)

# Test suite setup
def sentinel_test_suite(name):
    """Create all sentinel test targets

    Args:
        name: Name of the test suite
    """

    # Create test files
    create_sentinel_policy(
        name = "test_policy",
    )

    create_sentinel_test_hcl(
        name = "test_hcl",
    )

    create_sentinel_mock(
        name = "test_mock",
    )

    # Test basic sentinel test creation
    tf_sentinel_test(
        name = "basic_sentinel_test",
        srcs = [":test_policy"],
        tests = [":test_hcl", ":test_mock"],
        size = "small",
    )

    tf_sentinel_test_creation_test(
        name = "tf_sentinel_test_creation_test",
        target_under_test = ":basic_sentinel_test",
        size = "small",
    )

    # Test sentinel test with mocks
    tf_sentinel_with_mocks_test(
        name = "tf_sentinel_with_mocks_test",
        target_under_test = ":basic_sentinel_test",
        size = "small",
    )

    # Test sentinel test includes test files
    tf_sentinel_with_test_files_test(
        name = "tf_sentinel_with_test_files_test",
        target_under_test = ":basic_sentinel_test",
        size = "small",
    )

    # Test format test creation
    tf_sentinel_fmt_test(
        name = "basic_fmt_test",
        srcs = [":test_policy"],
        size = "small",
    )

    tf_sentinel_fmt_test_creation_test(
        name = "tf_sentinel_fmt_test_creation_test",
        target_under_test = ":basic_fmt_test",
        size = "small",
    )

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":tf_sentinel_test_creation_test",
            ":tf_sentinel_with_mocks_test",
            ":tf_sentinel_with_test_files_test",
            ":tf_sentinel_fmt_test_creation_test",
        ],
    )
