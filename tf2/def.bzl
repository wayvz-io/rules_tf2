"""Public API for tf2 module (updated structure)"""

load(
    "//tf2/macros:tf_module.bzl",
    _tf_module = "tf_module",
)
load(
    "//tf2/macros:tf_stack.bzl",
    _tf_stack = "tf_stack",
)
load(
    "//tf2/providers/registry:provider_mirror.bzl",
    _provider_mirror = "provider_mirror",
)
load(
    "//tf2/publish/oci:oci_push.bzl",
    _tf_module_push_oci = "tf_module_push_oci",
)
load(
    "//tf2/publish/registry:registry_publish.bzl",
    _tf_module_publish = "tf_module_publish",
)
load(
    "//tf2/tfcloud:runner.bzl",
    _tf_cloud_configuration = "tf_cloud_configuration",
)
load(
    "//tf2/tfcore:export.bzl",
    _tf_file_export = "tf_file_export",
)
load(
    "//tf2/tfcore:runner.bzl",
    _tf_runner = "tf_runner",
)
load(
    "//tf2/tfcore:test.bzl",
    _tf_test = "tf_test",
)
load(
    "//tf2/tfcore:variables.bzl",
    _tf_variables = "tf_variables",
)
load(
    "//tf2/sentinel:test.bzl",
    _tf_sentinel_fmt = "tf_sentinel_fmt",
    _tf_sentinel_fmt_test = "tf_sentinel_fmt_test",
    _tf_sentinel_test = "tf_sentinel_test",
)

# CDKTF generation moved to repository rules - use @rules_tf2//tf2:cdktf_extensions.bzl
# load(
#     "//tf2/core/rules:cdktf_generate.bzl",
#     _cdktf_generate = "cdktf_generate",
#     _cdktf_go_library = "cdktf_go_library",
# )

# Provider management
provider_mirror = _provider_mirror

# Core rules
tf_module = _tf_module
tf_stack = _tf_stack
tf_module_push_oci = _tf_module_push_oci
tf_module_publish = _tf_module_publish
tf_file_export = _tf_file_export
tf_cloud_configuration = _tf_cloud_configuration
tf_runner = _tf_runner
tf_test = _tf_test
tf_variables = _tf_variables

# Sentinel rules
tf_sentinel_test = _tf_sentinel_test
tf_sentinel_fmt_test = _tf_sentinel_fmt_test
tf_sentinel_fmt = _tf_sentinel_fmt

# CDKTF generation - moved to repository rules
# Use module extension @rules_tf2//tf2:cdktf_extensions.bzl instead
# cdktf_generate = _cdktf_generate
# cdktf_go_library = _cdktf_go_library
