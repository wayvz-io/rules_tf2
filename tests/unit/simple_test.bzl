"""Simple unit tests for tf2 Bazel rules using Skylib unittest framework"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest", "unittest")

# Simple test to verify testing framework works
def _simple_test_impl(ctx):
    env = unittest.begin(ctx)
    
    # Basic assertions
    asserts.equals(env, 2, 1 + 1, "Basic math test")
    asserts.true(env, True, "True is true")
    asserts.false(env, False, "False is false")
    
    # Test string operations
    asserts.equals(env, "hello world", "hello " + "world", "String concatenation")
    
    # Test list operations
    test_list = [1, 2, 3]
    asserts.equals(env, 3, len(test_list), "List length")
    asserts.equals(env, 1, test_list[0], "List indexing")
    
    return unittest.end(env)

simple_test = unittest.make(_simple_test_impl)

# Test for checking rule attributes
def _attribute_test_impl(ctx):
    env = unittest.begin(ctx)
    
    # Test that we can check attributes
    test_dict = {"key": "value", "number": 42}
    asserts.equals(env, "value", test_dict["key"], "Dict access")
    asserts.equals(env, 42, test_dict["number"], "Dict number access")
    
    # Test that we can handle None
    asserts.equals(env, None, test_dict.get("missing"), "Missing key returns None")
    
    return unittest.end(env)

attribute_test = unittest.make(_attribute_test_impl)

# Test for path operations
def _path_test_impl(ctx):
    env = unittest.begin(ctx)
    
    # Test path operations
    path = "foo/bar/baz.txt"
    parts = path.split("/")
    asserts.equals(env, 3, len(parts), "Path split")
    asserts.equals(env, "baz.txt", parts[-1], "Filename extraction")
    
    # Test extension extraction
    filename = "test.tf"
    asserts.true(env, filename.endswith(".tf"), "Extension check")
    
    return unittest.end(env)

path_test = unittest.make(_path_test_impl)

# Analysis test - test that a rule produces expected providers
def _provider_test_impl(ctx):
    env = analysistest.begin(ctx)
    
    target_under_test = analysistest.target_under_test(env)
    
    # Check that DefaultInfo is always present
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "All targets should have DefaultInfo"
    )
    
    return analysistest.end(env)

provider_test = analysistest.make(_provider_test_impl)

# Helper rule for testing
def _dummy_rule_impl(ctx):
    """A simple rule for testing"""
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
    ]

dummy_rule = rule(
    implementation = _dummy_rule_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
    },
)

def simple_test_suite(name):
    """Create simple test suite"""
    
    # Create basic unit tests
    simple_test(name = name + "_simple")
    attribute_test(name = name + "_attribute")
    path_test(name = name + "_path")
    
    # Create a dummy target for analysis testing
    dummy_rule(
        name = name + "_dummy",
        srcs = [],
    )
    
    provider_test(
        name = name + "_provider",
        target_under_test = ":" + name + "_dummy",
    )
    
    # Aggregate tests
    native.test_suite(
        name = name,
        tests = [
            ":" + name + "_simple",
            ":" + name + "_attribute",
            ":" + name + "_path",
            ":" + name + "_provider",
        ],
    )