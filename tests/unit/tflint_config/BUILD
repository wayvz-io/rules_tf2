# Unit tests for TFLint configuration system

load(":config_generation_test.bzl", "config_generation_test_suite")
load(":defaults_test.bzl", "defaults_test_suite")
load(":provider_detection_test.bzl", "provider_detection_test_suite")
load(":rule_merging_test.bzl", "rule_merging_test_suite")
load(":versions_parser_test.bzl", "versions_parser_test_suite")

# Individual test suites
versions_parser_test_suite(name = "versions_parser_tests")

defaults_test_suite(name = "defaults_tests")

config_generation_test_suite(name = "config_generation_tests")

provider_detection_test_suite(name = "provider_detection_tests")

rule_merging_test_suite(name = "rule_merging_tests")

# Combined test suite for all TFLint configuration tests
test_suite(
    name = "tflint_config_tests",
    tests = [
        ":config_generation_tests",
        ":defaults_tests",
        ":provider_detection_tests",
        ":rule_merging_tests",
        ":versions_parser_tests",
    ],
)
