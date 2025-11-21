"""Public API for tf2 module (updated structure)"""

load(
    "//tf2/macros:tf_module.bzl",
    _tf_module = "tf_module",
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
    "//tf2/tfcore:export.bzl",
    _tf_file_export = "tf_file_export",
)
load(
    "//tf2/tfcloud:runner.bzl",
    _tf_cloud_configuration = "tf_cloud_configuration",
    _tf_cloud_workspace = "tf_cloud_workspace",
)
load(
    "//tf2/tfcore:runner.bzl",
    _tf_runner = "tf_runner",
)
load(
    "//tf2/tfcore:variables.bzl",
    _tf_variables = "tf_variables",
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
tf_module_push_oci = _tf_module_push_oci
tf_module_publish = _tf_module_publish
tf_file_export = _tf_file_export
tf_cloud_configuration = _tf_cloud_configuration
tf_cloud_workspace = _tf_cloud_workspace
tf_runner = _tf_runner
tf_variables = _tf_variables

# CDKTF generation - moved to repository rules
# Use module extension @rules_tf2//tf2:cdktf_extensions.bzl instead
# cdktf_generate = _cdktf_generate
# cdktf_go_library = _cdktf_go_library
