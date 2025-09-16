"""Public API for tf2 module"""

load(
    "//tf/core/providers:provider_mirror.bzl",
    _provider_mirror = "provider_mirror",
)

load(
    "//tf/core/providers:provider_cache.bzl",
    _provider_cache = "provider_cache",
)

load(
    "//tf/core/providers:provider_alias.bzl",
    _provider_alias = "provider_alias",
)

load(
    "//tf/core/providers:provider_registry_alias.bzl",
    _provider_registry_alias = "provider_registry_alias",
)

load(
    "//tf/execution/macros:macros.bzl",
    _tf_module = "tf_module",
)

load(
    "//tf/publish/oci:oci_push.bzl",
    _tf_module_push_oci = "tf_module_push_oci",
)

load(
    "//tf/execution:tf_cloud_runner.bzl",
    _tf_cloud_configuration = "tf_cloud_configuration",
    _tf_cloud_workspace = "tf_cloud_workspace",
)

load(
    "//tf/execution:tf_runner.bzl",
    _tf_runner = "tf_runner",
)

load(
    "//tf/core/rules:variables.bzl",
    _tf_variables = "tf_variables",
)

# CDKTF generation moved to repository rules - use @rules_tf2//tf:cdktf_extensions.bzl
# load(
#     "//tf/core/rules:cdktf_generate.bzl",
#     _cdktf_generate = "cdktf_generate",
#     _cdktf_go_library = "cdktf_go_library",
# )

# Provider management
provider_mirror = _provider_mirror
provider_cache = _provider_cache
provider_alias = _provider_alias
provider_registry_alias = _provider_registry_alias

# Core rules
tf_module = _tf_module
tf_module_push_oci = _tf_module_push_oci
tf_cloud_configuration = _tf_cloud_configuration
tf_cloud_workspace = _tf_cloud_workspace
tf_runner = _tf_runner
tf_variables = _tf_variables

# CDKTF generation - moved to repository rules
# Use module extension @rules_tf2//tf:cdktf_extensions.bzl instead
# cdktf_generate = _cdktf_generate
# cdktf_go_library = _cdktf_go_library