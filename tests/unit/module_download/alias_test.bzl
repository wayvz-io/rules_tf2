"""Unit tests for module alias generation.

These tests import the *real* implementation from
`//tf2/modules/registry:alias.bzl` — the same code the `tf_modules` extension
calls — rather than a duplicated copy. Feeding a copy (and unrealistic inputs)
is what previously let a private-registry aliasing bug ship undetected.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/modules/registry:alias.bzl", "generate_module_alias", "sanitize_ref")

def _test_registry_alias_impl(ctx):
    """Test registry module alias generation."""
    env = unittest.begin(ctx)

    # terraform-aws-modules/vpc/aws:5.0.0 -> vpc_aws_5
    asserts.equals(env, "vpc_aws_5", generate_module_alias("terraform-aws-modules/vpc/aws", "registry", "5.0.0"))

    # hashicorp/consul/aws:0.11.0 -> consul_aws_0
    asserts.equals(env, "consul_aws_0", generate_module_alias("hashicorp/consul/aws", "registry", "0.11.0"))

    # Same major version collapses to the same alias.
    asserts.equals(env, "vpc_aws_5", generate_module_alias("terraform-aws-modules/vpc/aws", "registry", "5.1.0"))

    return unittest.end(env)

registry_alias_test = unittest.make(_test_registry_alias_impl)

def _test_git_alias_impl(ctx):
    """Test git module alias generation."""
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        "terraform_aws_modules_aws_s3_bucket_4_0_0",
        generate_module_alias("github.com/terraform-aws-modules/terraform-aws-s3-bucket", "git", "v4.0.0"),
    )
    asserts.equals(
        env,
        "cloudposse_null_label_0_25_0",
        generate_module_alias("github.com/cloudposse/terraform-null-label", "git", "0.25.0"),
    )
    asserts.equals(
        env,
        "cloudposse_null_label_abc1234",
        generate_module_alias("github.com/cloudposse/terraform-null-label", "git", "abc1234"),
    )

    return unittest.end(env)

git_alias_test = unittest.make(_test_git_alias_impl)

def _test_private_alias_impl(ctx):
    """Private-registry alias generation.

    The extension strips the registry hostname and passes the module path as
    `namespace/name/provider` (see extensions.bzl: it splits registry config by
    hostname, then calls generate_module_alias(source, ...) with the stripped
    key). So THIS is the input the real caller produces — not a
    hostname-qualified 4-part string.
    """
    env = unittest.begin(ctx)

    # my-org/example-module/aws:1.0.0 -> example_module_aws_1
    asserts.equals(
        env,
        "example_module_aws_1",
        generate_module_alias("example-org/example-module/aws", "private", "1.0.0"),
    )

    return unittest.end(env)

private_alias_test = unittest.make(_test_private_alias_impl)

def _test_private_alias_no_collision_impl(ctx):
    """Regression: distinct private modules must not collide to one alias.

    The bug collapsed every private module to just its provider name (dropping
    the module name and version), so different modules silently overwrote each
    other in the registry's alias map.
    """
    env = unittest.begin(ctx)

    vpc = generate_module_alias("my-org/vpc/aws", "private", "1.0.0")
    eks = generate_module_alias("my-org/eks/aws", "private", "2.0.0")

    # Different modules -> different aliases.
    asserts.false(env, vpc == eks, "distinct private modules collided to alias %r" % vpc)

    # The alias must carry the module name and major version, not just provider.
    asserts.equals(env, "vpc_aws_1", vpc)
    asserts.equals(env, "eks_aws_2", eks)

    return unittest.end(env)

private_alias_no_collision_test = unittest.make(_test_private_alias_no_collision_impl)

def _test_sanitize_ref_impl(ctx):
    """Test git ref sanitization."""
    env = unittest.begin(ctx)

    asserts.equals(env, "1_0_0", sanitize_ref("v1.0.0"))
    asserts.equals(env, "5_0_0", sanitize_ref("5.0.0"))
    asserts.equals(env, "abc1234", sanitize_ref("abc1234"))
    asserts.equals(env, "feature_branch", sanitize_ref("feature-branch"))

    return unittest.end(env)

sanitize_ref_test = unittest.make(_test_sanitize_ref_impl)

def alias_test_suite(name):
    """Create the test suite for alias generation tests."""
    unittest.suite(
        name,
        registry_alias_test,
        git_alias_test,
        private_alias_test,
        private_alias_no_collision_test,
        sanitize_ref_test,
    )
