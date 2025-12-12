"""Non-module dependencies configuration for rules_tf2."""

load("@rules_nixpkgs_cc//:cc.bzl", "nixpkgs_cc_configure")
load("@rules_nixpkgs_core//:nixpkgs.bzl", "nixpkgs_package")
load("@rules_nixpkgs_java//:java.bzl", "nixpkgs_java_configure")

def _non_module_deps_impl(_):
    nixpkgs_cc_configure(
        name = "nixpkgs_config_cc",
        repository = "@nixpkgs",
        register = False,
    )

    nixpkgs_java_configure(
        name = "nixpkgs_java_runtime",
        attribute_path = "jdk23.home",
        repository = "@nixpkgs",
        toolchain = True,
        register = False,
        toolchain_name = "nixpkgs_java",
        toolchain_version = "23",
    )

    nixpkgs_java_configure(
        name = "nixpkgs_java_jdk",
        attribute_path = "jdk23",
        repository = "@nixpkgs",
        toolchain = True,
        register = False,
        toolchain_name = "nixpkgs_java_jdk",
        toolchain_version = "23",
    )

    # mdbook for documentation generation
    nixpkgs_package(
        name = "nixpkgs_mdbook",
        attribute_path = "mdbook",
        repository = "@nixpkgs",
    )

non_module_deps = module_extension(
    implementation = _non_module_deps_impl,
)
