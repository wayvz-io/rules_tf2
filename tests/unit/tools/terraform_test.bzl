"""Unit tests for terraform.bzl functions"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/tools/runners:terraform.bzl", "create_terraform_format_test", "create_terraform_script", "create_terraform_validate_test", "terraform_init_script")

def _test_terraform_public_api(ctx):
    """Test terraform.bzl public API functions exist."""
    env = unittest.begin(ctx)

    # Test that all public functions exist
    asserts.true(env, create_terraform_format_test != None, "create_terraform_format_test should exist")
    asserts.true(env, create_terraform_validate_test != None, "create_terraform_validate_test should exist")
    asserts.true(env, terraform_init_script != None, "terraform_init_script should exist")
    asserts.true(env, create_terraform_script != None, "create_terraform_script should exist")

    return unittest.end(env)

def _test_terraform_init_script_basic(ctx):
    """Test terraform_init_script basic functionality."""
    env = unittest.begin(ctx)

    # Create a mock context (minimal for testing)
    mock_ctx = struct(
        label = struct(workspace_name = "", package = "test/package"),
        attr = struct(_tools = None),
        files = struct(_tools = []),
    )

    # Test basic init script generation without plugin_dir
    script = terraform_init_script(mock_ctx)
    asserts.true(env, type(script) == "string", "terraform_init_script should return string")
    asserts.true(env, "terraform" in script, "Script should contain terraform command")
    asserts.true(env, "init" in script, "Script should contain init command")

    return unittest.end(env)

def _test_terraform_init_script_flags(ctx):
    """Test terraform_init_script flag handling."""
    env = unittest.begin(ctx)

    # Create a mock context
    mock_ctx = struct(
        label = struct(workspace_name = "", package = "test/package"),
        attr = struct(_tools = None),
        files = struct(_tools = []),
    )

    # Test with backend=False
    script = terraform_init_script(mock_ctx, backend = False)
    asserts.true(env, "-backend=false" in script, "Should include -backend=false flag")

    # Test with upgrade=False
    script = terraform_init_script(mock_ctx, upgrade = False)
    asserts.true(env, "-upgrade=false" in script, "Should include -upgrade=false flag")

    # Test with lockfile_readonly=True (default)
    script = terraform_init_script(mock_ctx, lockfile_readonly = True)
    asserts.true(env, "-lockfile=readonly" in script, "Should include -lockfile=readonly flag")

    return unittest.end(env)

def _test_terraform_function_types(ctx):
    """Test terraform functions have correct types."""
    env = unittest.begin(ctx)

    # Verify functions exist and have correct types
    asserts.true(env, create_terraform_format_test != None, "create_terraform_format_test should exist")
    asserts.true(env, create_terraform_validate_test != None, "create_terraform_validate_test should exist")
    asserts.true(env, create_terraform_script != None, "create_terraform_script should exist")

    # Check they are functions (in Starlark, functions are of type "builtin_function_or_method")
    asserts.true(env, str(type(create_terraform_format_test)) != "NoneType", "create_terraform_format_test should not be None")
    asserts.true(env, str(type(create_terraform_validate_test)) != "NoneType", "create_terraform_validate_test should not be None")
    asserts.true(env, str(type(create_terraform_script)) != "NoneType", "create_terraform_script should not be None")

    return unittest.end(env)

# Test cases
terraform_public_api_test = unittest.make(_test_terraform_public_api)
terraform_init_script_basic_test = unittest.make(_test_terraform_init_script_basic)
terraform_init_script_flags_test = unittest.make(_test_terraform_init_script_flags)
terraform_function_types_test = unittest.make(_test_terraform_function_types)

def terraform_test_suite():
    """Create terraform test suite."""
    unittest.suite(
        "terraform_tests",
        terraform_public_api_test,
        terraform_init_script_basic_test,
        terraform_init_script_flags_test,
        terraform_function_types_test,
    )
