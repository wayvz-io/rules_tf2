"""Provider management rules for Terraform"""

load(":provider_cache.bzl", _provider_cache = "provider_cache")
load(":provider_mirror.bzl", _provider_mirror = "provider_mirror")
load(":provider_alias.bzl", _provider_alias = "provider_alias")
load(":provider_registry_alias.bzl", _provider_registry_alias = "provider_registry_alias")
load(":lock_file_generator.bzl", _tf_lock_file_generator = "tf_lock_file_generator")

# Re-export rules
provider_cache = _provider_cache
provider_mirror = _provider_mirror
provider_alias = _provider_alias
provider_registry_alias = _provider_registry_alias
tf_lock_file_generator = _tf_lock_file_generator
