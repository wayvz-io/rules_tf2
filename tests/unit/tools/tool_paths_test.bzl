"""Unit tests for tool path resolution functionality"""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/tools/runners:tool_paths.bzl", "TOOLS_ATTR", "get_terraform_docs_path", "get_terraform_path", "get_tflint_path", "get_tflint_plugin_path")

def _test_tool_paths_api(ctx):
    """Test tool path functions exist."""
    env = unittest.begin(ctx)

    # Test that all required functions exist
    asserts.true(env, get_terraform_path != None, "get_terraform_path should exist")
    asserts.true(env, get_tflint_path != None, "get_tflint_path should exist")
    asserts.true(env, get_terraform_docs_path != None, "get_terraform_docs_path should exist")
    asserts.true(env, get_tflint_plugin_path != None, "get_tflint_plugin_path should exist")

    return unittest.end(env)

def _test_tools_attr_exists(ctx):
    """Test TOOLS_ATTR exists and has basic structure."""
    env = unittest.begin(ctx)

    # Test that TOOLS_ATTR exists and has the right structure
    asserts.true(env, TOOLS_ATTR != None, "TOOLS_ATTR should exist")
    asserts.true(env, type(TOOLS_ATTR) == "dict", "TOOLS_ATTR should be a dictionary")
    asserts.true(env, "_tools" in TOOLS_ATTR, "TOOLS_ATTR should contain _tools attribute")

    return unittest.end(env)

def _test_module_exports(ctx):
    """Test that the module exports expected symbols."""
    env = unittest.begin(ctx)

    # Check that key functions are exported
    expected_functions = [
        get_terraform_path,
        get_tflint_path,
        get_terraform_docs_path,
        get_tflint_plugin_path,
    ]

    for func in expected_functions:
        asserts.true(env, func != None, "Function should exist")

    # Check that TOOLS_ATTR is exported
    asserts.true(env, TOOLS_ATTR != None, "TOOLS_ATTR should be exported")

    return unittest.end(env)

tool_paths_api_test = unittest.make(_test_tool_paths_api)
tools_attr_test = unittest.make(_test_tools_attr_exists)
module_exports_test = unittest.make(_test_module_exports)

def tool_paths_test_suite():
    """Create tool paths test suite."""
    unittest.suite(
        "tool_paths_tests",
        partial.make(tool_paths_api_test, size = "small"),
        partial.make(tools_attr_test, size = "small"),
        partial.make(module_exports_test, size = "small"),
    )
