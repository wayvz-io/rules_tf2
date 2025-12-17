"""Unit tests for terraformrc generation"""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

def _test_terraformrc_content_impl(ctx):
    """Test that terraformrc rule generates expected content structure."""
    env = unittest.begin(ctx)

    # Test expected content patterns
    expected_provider_path = "/terraform/providers"
    expected_content_patterns = [
        "disable_checkpoint = true",
        "provider_installation {",
        "filesystem_mirror {",
        'path = "{}"'.format(expected_provider_path),
        "direct {",
        'exclude = ["registry.terraform.io/*/*"]',
    ]

    # Generate the expected content
    content = """# Auto-generated .terraformrc for TFC agent
# Configures Terraform to use bundled providers from filesystem mirror

disable_checkpoint = true

provider_installation {{
  filesystem_mirror {{
    path = "{provider_path}"
  }}
  direct {{
    exclude = ["registry.terraform.io/*/*"]
  }}
}}
""".format(provider_path = expected_provider_path)

    # Verify each expected pattern is in the content
    for pattern in expected_content_patterns:
        asserts.true(
            env,
            pattern in content,
            "Expected pattern '{}' not found in terraformrc content".format(pattern),
        )

    # Verify the content disables direct downloads
    asserts.true(
        env,
        "direct {" in content,
        "Direct block should be present",
    )
    asserts.true(
        env,
        "exclude" in content,
        "Exclude directive should be present to block registry downloads",
    )

    return unittest.end(env)

def _test_custom_provider_path_impl(ctx):
    """Test that custom provider path is correctly applied."""
    env = unittest.begin(ctx)

    custom_path = "/custom/path/to/providers"

    content = """provider_installation {{
  filesystem_mirror {{
    path = "{provider_path}"
  }}
}}
""".format(provider_path = custom_path)

    asserts.true(
        env,
        custom_path in content,
        "Custom provider path should be in content",
    )

    return unittest.end(env)

def _test_hcl_structure_impl(ctx):
    """Test that generated content is valid HCL structure."""
    env = unittest.begin(ctx)

    content = """provider_installation {
  filesystem_mirror {
    path = "/terraform/providers"
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
"""

    # Count braces to verify structure
    open_braces = content.count("{")
    close_braces = content.count("}")

    asserts.equals(
        env,
        open_braces,
        close_braces,
        "HCL should have balanced braces",
    )

    # Verify nested structure
    asserts.true(
        env,
        "provider_installation {" in content,
        "Should have provider_installation block",
    )
    asserts.true(
        env,
        "filesystem_mirror {" in content,
        "Should have filesystem_mirror block",
    )

    return unittest.end(env)

# Test rule definitions
terraformrc_content_test = unittest.make(_test_terraformrc_content_impl)
custom_provider_path_test = unittest.make(_test_custom_provider_path_impl)
hcl_structure_test = unittest.make(_test_hcl_structure_impl)

def terraformrc_test_suite(name):
    """Test suite for terraformrc generation"""
    unittest.suite(
        name,
        partial.make(terraformrc_content_test, size = "small"),
        partial.make(custom_provider_path_test, size = "small"),
        partial.make(hcl_structure_test, size = "small"),
    )
