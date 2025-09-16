# Main test orchestration for tf2 rules

# Aggregate all tests
test_suite(
    name = "all",
    tests = [
        "//tf/tests/unit:all_unit_tests",
        "//tf/tests/integration:all_integration_tests",
    ],
    visibility = ["//visibility:public"],
)

# Unit tests only (fast, no Terraform required)
alias(
    name = "unit",
    actual = "//tf/tests/unit:all_unit_tests",
    visibility = ["//visibility:public"],
)

# Integration tests only (slower, tests full lifecycle)
alias(
    name = "integration",
    actual = "//tf/tests/integration:all_integration_tests",
    visibility = ["//visibility:public"],
)