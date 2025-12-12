"""Unit tests for OPA rules"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//tf2/opa:test.bzl", "tf_opa_fmt_test", "tf_opa_test")

# Test that OPA test rule is created correctly
def _tf_opa_test_creation_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_opa_test should provide DefaultInfo",
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_opa_test should be executable",
    )

    return analysistest.end(env)

tf_opa_test_creation_test = analysistest.make(_tf_opa_test_creation_test_impl)

# Test OPA test includes rego files in runfiles
def _tf_opa_with_rego_files_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that rego files are included in runfiles
    files = runfiles.files.to_list()
    rego_files = [f for f in files if f.path.endswith(".rego")]

    asserts.true(
        env,
        len(rego_files) > 0,
        "OPA test should include .rego files in runfiles",
    )

    return analysistest.end(env)

tf_opa_with_rego_files_test = analysistest.make(_tf_opa_with_rego_files_test_impl)

# Test OPA format test creation
def _tf_opa_fmt_test_creation_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_opa_fmt_test should provide DefaultInfo",
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_opa_fmt_test should be executable",
    )

    return analysistest.end(env)

tf_opa_fmt_test_creation_test = analysistest.make(_tf_opa_fmt_test_creation_test_impl)

# Test OPA test with data files
def _tf_opa_with_data_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that data files are included in runfiles
    files = runfiles.files.to_list()
    json_files = [f for f in files if f.path.endswith(".json")]

    asserts.true(
        env,
        len(json_files) > 0,
        "OPA test should include .json data files in runfiles",
    )

    return analysistest.end(env)

tf_opa_with_data_test = analysistest.make(_tf_opa_with_data_test_impl)

# Helper to create test rego policy file
def _create_opa_policy_impl(ctx):
    """Create a simple OPA policy file"""

    policy = ctx.actions.declare_file("authz.rego")
    ctx.actions.write(
        output = policy,
        content = "package authz\n\n# Default deny\ndefault allow := false\n\n# Allow admin users\nallow if {\n\tinput.user == \"admin\"\n}\n\n# Allow read access for any authenticated user\nallow if {\n\tinput.action == \"read\"\n\tinput.authenticated == true\n}\n",
    )

    return [DefaultInfo(files = depset([policy]))]

create_opa_policy = rule(
    implementation = _create_opa_policy_impl,
)

# Helper to create test rego file with test_ rules
def _create_opa_test_file_impl(ctx):
    """Create an OPA test file"""

    test_file = ctx.actions.declare_file("authz_test.rego")
    ctx.actions.write(
        output = test_file,
        content = "package authz\n\n# Test admin is allowed\ntest_admin_allowed if {\n\tallow with input as {\"user\": \"admin\", \"action\": \"write\"}\n}\n\n# Test authenticated user can read\ntest_authenticated_read if {\n\tallow with input as {\"authenticated\": true, \"action\": \"read\"}\n}\n\n# Test unauthenticated user denied\ntest_unauthenticated_denied if {\n\tnot allow with input as {\"authenticated\": false, \"action\": \"read\"}\n}\n",
    )

    return [DefaultInfo(files = depset([test_file]))]

create_opa_test_file = rule(
    implementation = _create_opa_test_file_impl,
)

# Helper to create test data JSON file
def _create_opa_data_impl(ctx):
    """Create an OPA data JSON file"""

    data = ctx.actions.declare_file("data.json")
    ctx.actions.write(
        output = data,
        content = """{"users": ["admin", "guest"]}
""",
    )

    return [DefaultInfo(files = depset([data]))]

create_opa_data = rule(
    implementation = _create_opa_data_impl,
)

# Test suite setup
def opa_test_suite(name):
    """Create all OPA test targets

    Args:
        name: Name of the test suite
    """

    # Create test files
    create_opa_policy(
        name = "test_policy",
    )

    create_opa_test_file(
        name = "test_rego",
    )

    create_opa_data(
        name = "test_data",
    )

    # Test basic OPA test creation
    tf_opa_test(
        name = "basic_opa_test",
        srcs = [":test_policy", ":test_rego"],
        size = "small",
    )

    tf_opa_test_creation_test(
        name = "tf_opa_test_creation_test",
        target_under_test = ":basic_opa_test",
        size = "small",
    )

    # Test OPA test with rego files
    tf_opa_with_rego_files_test(
        name = "tf_opa_with_rego_files_test",
        target_under_test = ":basic_opa_test",
        size = "small",
    )

    # Test OPA test with data files
    tf_opa_test(
        name = "opa_test_with_data",
        srcs = [":test_policy", ":test_rego"],
        data = [":test_data"],
        size = "small",
    )

    tf_opa_with_data_test(
        name = "tf_opa_with_data_test",
        target_under_test = ":opa_test_with_data",
        size = "small",
    )

    # Test format test creation
    tf_opa_fmt_test(
        name = "basic_fmt_test",
        srcs = [":test_policy"],
        size = "small",
    )

    tf_opa_fmt_test_creation_test(
        name = "tf_opa_fmt_test_creation_test",
        target_under_test = ":basic_fmt_test",
        size = "small",
    )

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":tf_opa_test_creation_test",
            ":tf_opa_with_rego_files_test",
            ":tf_opa_with_data_test",
            ":tf_opa_fmt_test_creation_test",
        ],
    )
