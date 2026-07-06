"""Unit tests for the hermetic fetch checksum parsing helpers."""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//tf2/internal:hermetic_fetch.bzl", "facts_key", "parse_sums_file")

# A realistic HashiCorp *_SHA256SUMS body (text mode, two spaces).
_HASHICORP_SUMS = """728251e59d5be0e26f2c68e0e5e2c37b56c31da95f57e4d9ac1d24d70fb30f70  terraform_1.14.2_darwin_amd64.zip
9d9e0e6d1f7b8f5a3b0d2c1e4a6f8b7c5d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8  terraform_1.14.2_darwin_arm64.zip
aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888  terraform_1.14.2_linux_amd64.zip
cccc9999dddd0000eeee1111ffff2222aaaa3333bbbb4444cccc5555dddd6666  terraform_1.14.2_linux_arm64.zip
"""

# GitHub-release checksums.txt sometimes uses binary mode (leading asterisk).
_GITHUB_CHECKSUMS = """# checksums
1111aaaa2222bbbb3333cccc4444dddd5555eeee6666ffff7777aaaa8888bbbb *tflint_linux_amd64.zip
2222bbbb3333cccc4444dddd5555eeee6666ffff7777aaaa8888bbbb9999cccc *tflint_darwin_arm64.zip

"""

def _test_parse_text_mode(ctx):
    env = unittest.begin(ctx)
    asserts.equals(
        env,
        "aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888",
        parse_sums_file(_HASHICORP_SUMS, "terraform_1.14.2_linux_amd64.zip"),
    )
    asserts.equals(
        env,
        "728251e59d5be0e26f2c68e0e5e2c37b56c31da95f57e4d9ac1d24d70fb30f70",
        parse_sums_file(_HASHICORP_SUMS, "terraform_1.14.2_darwin_amd64.zip"),
    )
    return unittest.end(env)

def _test_parse_binary_mode_and_comments(ctx):
    env = unittest.begin(ctx)

    # Leading-asterisk (binary mode) filenames are matched without the asterisk.
    asserts.equals(
        env,
        "1111aaaa2222bbbb3333cccc4444dddd5555eeee6666ffff7777aaaa8888bbbb",
        parse_sums_file(_GITHUB_CHECKSUMS, "tflint_linux_amd64.zip"),
    )

    # Comment and blank lines never match.
    asserts.equals(env, None, parse_sums_file(_GITHUB_CHECKSUMS, "checksums"))
    return unittest.end(env)

def _test_parse_missing_returns_none(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, None, parse_sums_file(_HASHICORP_SUMS, "terraform_1.14.2_windows_amd64.zip"))
    asserts.equals(env, None, parse_sums_file("", "anything"))

    # A partial filename must not match a longer entry.
    asserts.equals(env, None, parse_sums_file(_HASHICORP_SUMS, "terraform_1.14.2_linux_amd64"))
    return unittest.end(env)

def _test_facts_key(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, "tool:terraform:1.14.2", facts_key("tool", "terraform", "1.14.2"))
    asserts.equals(env, "module:git:github.com/o/r:v1.0.0", facts_key("module", "git", "github.com/o/r", "v1.0.0"))
    return unittest.end(env)

parse_text_mode_test = unittest.make(_test_parse_text_mode)
parse_binary_mode_test = unittest.make(_test_parse_binary_mode_and_comments)
parse_missing_test = unittest.make(_test_parse_missing_returns_none)
facts_key_test = unittest.make(_test_facts_key)

def hermetic_fetch_test_suite():
    """Create the hermetic fetch unit test suite."""
    unittest.suite(
        "hermetic_fetch_tests",
        partial.make(parse_text_mode_test, size = "small"),
        partial.make(parse_binary_mode_test, size = "small"),
        partial.make(parse_missing_test, size = "small"),
        partial.make(facts_key_test, size = "small"),
    )
