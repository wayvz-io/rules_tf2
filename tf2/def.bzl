"""Public API for tf2 module (updated structure)"""

load(
    "//tf2/macros:tf_module.bzl",
    _tf_module = "tf_module",
)
load(
    "//tf2/opa:test.bzl",
    _tf_opa_fmt = "tf_opa_fmt",
    _tf_opa_fmt_test = "tf_opa_fmt_test",
    _tf_opa_test = "tf_opa_test",
)
load(
    "//tf2/providers/registry:provider_mirror.bzl",
    _provider_mirror = "provider_mirror",
)
load(
    "//tf2/publish/oci:oci_push.bzl",
    _tf_publish_oci = "tf_publish_oci",
)
load(
    "//tf2/publish/registry:registry_publish.bzl",
    _tf_publish_registry = "tf_publish_registry",
)
load(
    "//tf2/sentinel:test.bzl",
    _tf_sentinel_fmt = "tf_sentinel_fmt",
    _tf_sentinel_fmt_test = "tf_sentinel_fmt_test",
    _tf_sentinel_test = "tf_sentinel_test",
)
load(
    "//tf2/tfcloud:runner.bzl",
    _tf_cloud_workspace = "tf_cloud_workspace",
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
    "//tf2/agent:agent_image.bzl",
    _tfc_agent_image = "tfc_agent_image",
)

# Provider management
provider_mirror = _provider_mirror

# Core rules
tf_module = _tf_module
tf_publish_oci = _tf_publish_oci
tf_publish_registry = _tf_publish_registry
tf_file_export = _tf_file_export
tf_cloud_workspace = _tf_cloud_workspace
tf_runner = _tf_runner
tf_test = _tf_test
tf_variables = _tf_variables

# Sentinel rules
tf_sentinel_test = _tf_sentinel_test
tf_sentinel_fmt_test = _tf_sentinel_fmt_test
tf_sentinel_fmt = _tf_sentinel_fmt

# OPA rules
tf_opa_test = _tf_opa_test
tf_opa_fmt_test = _tf_opa_fmt_test
tf_opa_fmt = _tf_opa_fmt

# Agent image building
tfc_agent_image = _tfc_agent_image
