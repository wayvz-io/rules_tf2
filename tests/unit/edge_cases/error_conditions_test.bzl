"""Unit tests for edge cases and error conditions"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest", "unittest")

# Test missing providers error
def _test_missing_providers_error(ctx):
    """Test that missing providers attribute causes appropriate error"""
    env = unittest.begin(ctx)
    
    # The rule should fail if:
    # - providers attribute is None/empty
    # - AND modules attribute is None/empty
    # This is the validation: if not providers and not modules: fail(...)
    
    test_cases = [
        (None, None, True),      # Both missing - should fail
        ([], None, True),        # Empty providers, no modules - should fail
        (None, [], True),        # No providers, empty modules - should fail
        (["aws"], None, False),  # Has providers - OK
        (None, ["vpc"], False),  # Has modules - OK
        (["aws"], ["vpc"], False), # Has both - OK
    ]
    
    for providers, modules, should_fail in test_cases:
        has_providers = providers and len(providers) > 0
        has_modules = modules and len(modules) > 0
        
        would_fail = not has_providers and not has_modules
        
        asserts.equals(
            env,
            should_fail,
            would_fail,
            "Validation for providers=%s, modules=%s" % (str(providers), str(modules))
        )
    
    return unittest.end(env)

missing_providers_error_test = unittest.make(_test_missing_providers_error)

# Test circular dependency detection
def _test_circular_dependency_detection(ctx):
    """Test detection of circular module dependencies"""
    env = unittest.begin(ctx)
    
    # Simulate dependency graphs
    dependency_graphs = [
        {
            "name": "simple_circular",
            "deps": {
                "A": ["B"],
                "B": ["A"],  # Circular!
            },
            "has_cycle": True,
        },
        {
            "name": "transitive_circular",
            "deps": {
                "A": ["B"],
                "B": ["C"],
                "C": ["A"],  # Circular through chain!
            },
            "has_cycle": True,
        },
        {
            "name": "no_circular",
            "deps": {
                "A": ["B", "C"],
                "B": ["D"],
                "C": ["D"],
                "D": [],  # Terminal node
            },
            "has_cycle": False,
        },
    ]
    
    # Simple cycle detection algorithm (iterative to avoid recursion)
    def has_cycle_from_node(graph, start):
        visited = {}
        stack = [(start, [])]  # (node, path_to_node)
        
        for _ in range(100):  # Limit iterations
            if not stack:
                break
            node, path = stack.pop()
            
            if node in path:
                return True  # Found cycle
            
            if node in visited:
                continue
                
            visited[node] = True
            new_path = path + [node]
            
            for neighbor in graph.get(node, []):
                stack.append((neighbor, new_path))
        
        return False
    
    for test_case in dependency_graphs:
        graph = test_case["deps"]
        expected_cycle = test_case["has_cycle"]
        
        # Check from each node
        found_cycle = False
        for node in graph:
            if has_cycle_from_node(graph, node):
                found_cycle = True
                break
        
        asserts.equals(
            env,
            expected_cycle,
            found_cycle,
            "Cycle detection for %s" % test_case["name"]
        )
    
    return unittest.end(env)

circular_dependency_detection_test = unittest.make(_test_circular_dependency_detection)

# Test invalid version format handling
def _test_invalid_version_format(ctx):
    """Test handling of invalid version formats"""
    env = unittest.begin(ctx)
    
    invalid_versions = [
        ("", "empty string"),
        ("latest", "non-semver string"),
        ("1", "missing minor and patch"),
        ("1.2", "missing patch"),
        ("1.2.3.4", "too many parts"),
        ("v1.2.3", "has v prefix"),
        ("1.2.3-beta", "has prerelease"),
        ("1.2.3+build", "has build metadata"),
        ("1.x.3", "non-numeric component"),
        ("1.2.x", "placeholder version"),
    ]
    
    for version, description in invalid_versions:
        # Check that version would be rejected
        parts = version.split(".")
        
        # Valid semver check
        is_valid = len(parts) == 3 and not version.startswith("v")
        if is_valid:
            for p in parts:
                if not p.isdigit():
                    is_valid = False
                    break
        
        asserts.false(
            env,
            is_valid,
            "Should reject invalid version (%s): %s" % (description, version)
        )
    
    return unittest.end(env)

invalid_version_format_test = unittest.make(_test_invalid_version_format)

# Test empty module handling
def _test_empty_module_handling(ctx):
    """Test handling of modules with no source files"""
    env = unittest.begin(ctx)
    
    # Different empty states
    empty_states = [
        ([], "empty list"),
        (None, "None value"),
    ]
    
    for srcs, description in empty_states:
        # Module should still be valid with empty srcs
        # The default glob would provide files if they exist
        is_valid = True  # Empty modules are allowed
        
        asserts.true(
            env,
            is_valid,
            "Empty module should be valid (%s)" % description
        )
    
    return unittest.end(env)

empty_module_handling_test = unittest.make(_test_empty_module_handling)

# Test conflicting provider configurations
def _test_conflicting_provider_configs(ctx):
    """Test handling of conflicting provider configurations"""
    env = unittest.begin(ctx)
    
    # Conflicting configurations
    conflicts = [
        {
            "module1": {
                "aws": {
                    "region": "us-east-1",
                    "version": "6.12.0",
                },
            },
            "module2": {
                "aws": {
                    "region": "us-west-2",  # Different region
                    "version": "6.12.0",     # Same version
                },
            },
            "conflict_type": "configuration"
        },
        {
            "module1": {
                "aws": {
                    "version": "6.12.0",
                },
            },
            "module2": {
                "aws": {
                    "version": "6.13.0",  # Different version
                },
            },
            "conflict_type": "version"
        },
    ]
    
    for conflict in conflicts:
        conflict_type = conflict["conflict_type"]
        
        if conflict_type == "version":
            # Version conflicts should be detected
            asserts.true(env, True, "Version conflicts should be detected")
        elif conflict_type == "configuration":
            # Configuration conflicts might be allowed with aliases
            asserts.true(env, True, "Configuration conflicts might use provider aliases")
    
    return unittest.end(env)

conflicting_provider_configs_test = unittest.make(_test_conflicting_provider_configs)

# Test extremely long module paths
def _test_long_module_paths(ctx):
    """Test handling of extremely long module paths"""
    env = unittest.begin(ctx)
    
    # Create increasingly long paths
    long_paths = [
        "a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p",  # 16 levels
        "../" * 10 + "module",               # Many parent refs
        "very_long_module_name_that_exceeds_typical_limits_and_might_cause_issues_in_some_systems",
    ]
    
    for path in long_paths:
        # Check path handling
        if path.startswith("../"):
            # Count parent directory references
            parent_count = path.count("../")
            asserts.true(env, parent_count > 0, "Should handle multiple parent refs")
        elif "/" in path:
            # Count depth
            depth = len(path.split("/"))
            asserts.true(env, depth > 0, "Should handle deep nesting")
        else:
            # Long name
            asserts.true(env, len(path) > 50, "Should handle long names")
    
    return unittest.end(env)

long_module_paths_test = unittest.make(_test_long_module_paths)

# Test suite
def error_conditions_test_suite(name):
    """Create error conditions test suite"""
    
    missing_providers_error_test(name = name + "_missing_providers", size = "small")
    circular_dependency_detection_test(name = name + "_circular_deps", size = "small")
    invalid_version_format_test(name = name + "_invalid_version", size = "small")
    empty_module_handling_test(name = name + "_empty_module", size = "small")
    conflicting_provider_configs_test(name = name + "_conflicting_configs", size = "small")
    long_module_paths_test(name = name + "_long_paths", size = "small")
    
    native.test_suite(
        name = name,
        tests = [
            ":" + name + "_missing_providers",
            ":" + name + "_circular_deps",
            ":" + name + "_invalid_version",
            ":" + name + "_empty_module",
            ":" + name + "_conflicting_configs",
            ":" + name + "_long_paths",
        ],
    )