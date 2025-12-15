"""Unit tests for module alias generation."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")

# Test functions for alias generation logic
# These test the same logic used in extensions.bzl

def _sanitize_ref(ref):
    """Sanitize a git ref for use in repository names."""
    sanitized = ref.replace(".", "_").replace("-", "_").replace("/", "_")
    if sanitized.startswith("v"):
        sanitized = sanitized[1:]
    return sanitized

def _generate_module_alias(source, source_type, version):
    """Generate an alias name for a module."""
    major_version = version.split(".")[0] if "." in version else _sanitize_ref(version)

    if source_type == "registry":
        parts = source.split("/")
        if len(parts) == 3:
            name, provider = parts[1], parts[2]
            return "{}_{}_{}".format(name, provider, major_version)
        return "{}_{}".format(parts[-1], major_version)

    elif source_type == "private":
        parts = source.split("/")
        if len(parts) == 4:
            name, provider = parts[2], parts[3]
            return "{}_{}_{}".format(name.replace("-", "_"), provider, major_version)
        return "{}".format(parts[-1].replace("-", "_"))

    elif source_type == "git":
        if source.startswith("github.com/"):
            parts = source.split("/")
            owner, repo = parts[1], parts[2]
            return "{}_{}_{}".format(
                owner.replace("-", "_"),
                repo.replace("-", "_").replace("terraform-", "").replace("terraform_", ""),
                _sanitize_ref(version),
            )
        elif source.startswith("git::"):
            url = source[5:].replace(".git", "")
            parts = url.split("/")
            owner, repo = parts[-2], parts[-1]
            return "{}_{}_{}".format(
                owner.replace("-", "_"),
                repo.replace("-", "_").replace("terraform-", "").replace("terraform_", ""),
                _sanitize_ref(version),
            )

    fail("Cannot generate alias for source: {} (type: {})".format(source, source_type))

# Unit tests

def _test_registry_alias_impl(ctx):
    """Test registry module alias generation."""
    env = unittest.begin(ctx)

    # Test: terraform-aws-modules/vpc/aws:5.0.0 -> vpc_aws_5
    alias = _generate_module_alias("terraform-aws-modules/vpc/aws", "registry", "5.0.0")
    asserts.equals(env, "vpc_aws_5", alias)

    # Test: hashicorp/consul/aws:0.11.0 -> consul_aws_0
    alias = _generate_module_alias("hashicorp/consul/aws", "registry", "0.11.0")
    asserts.equals(env, "consul_aws_0", alias)

    # Test: terraform-aws-modules/vpc/aws:5.1.0 -> vpc_aws_5 (same major)
    alias = _generate_module_alias("terraform-aws-modules/vpc/aws", "registry", "5.1.0")
    asserts.equals(env, "vpc_aws_5", alias)

    return unittest.end(env)

registry_alias_test = unittest.make(_test_registry_alias_impl)

def _test_git_alias_impl(ctx):
    """Test git module alias generation."""
    env = unittest.begin(ctx)

    # Test: github.com/terraform-aws-modules/terraform-aws-s3-bucket:v4.0.0
    alias = _generate_module_alias(
        "github.com/terraform-aws-modules/terraform-aws-s3-bucket",
        "git",
        "v4.0.0",
    )
    asserts.equals(env, "terraform_aws_modules_aws_s3_bucket_4_0_0", alias)

    # Test: github.com/cloudposse/terraform-null-label:0.25.0
    alias = _generate_module_alias(
        "github.com/cloudposse/terraform-null-label",
        "git",
        "0.25.0",
    )
    asserts.equals(env, "cloudposse_null_label_0_25_0", alias)

    # Test: github.com/cloudposse/terraform-null-label:abc1234 (commit hash)
    alias = _generate_module_alias(
        "github.com/cloudposse/terraform-null-label",
        "git",
        "abc1234",
    )
    asserts.equals(env, "cloudposse_null_label_abc1234", alias)

    return unittest.end(env)

git_alias_test = unittest.make(_test_git_alias_impl)

def _test_private_alias_impl(ctx):
    """Test private registry module alias generation."""
    env = unittest.begin(ctx)

    # Test: app.terraform.io/example-org/example-module/aws:1.0.0
    alias = _generate_module_alias(
        "app.terraform.io/example-org/example-module/aws",
        "private",
        "1.0.0",
    )
    asserts.equals(env, "example_module_aws_1", alias)

    return unittest.end(env)

private_alias_test = unittest.make(_test_private_alias_impl)

def _test_sanitize_ref_impl(ctx):
    """Test git ref sanitization."""
    env = unittest.begin(ctx)

    # Test: v1.0.0 -> 1_0_0
    asserts.equals(env, "1_0_0", _sanitize_ref("v1.0.0"))

    # Test: 5.0.0 -> 5_0_0
    asserts.equals(env, "5_0_0", _sanitize_ref("5.0.0"))

    # Test: abc1234 -> abc1234
    asserts.equals(env, "abc1234", _sanitize_ref("abc1234"))

    # Test: feature-branch -> feature_branch
    asserts.equals(env, "feature_branch", _sanitize_ref("feature-branch"))

    return unittest.end(env)

sanitize_ref_test = unittest.make(_test_sanitize_ref_impl)

def alias_test_suite(name):
    """Create the test suite for alias generation tests."""
    unittest.suite(
        name,
        registry_alias_test,
        git_alias_test,
        private_alias_test,
        sanitize_ref_test,
    )
