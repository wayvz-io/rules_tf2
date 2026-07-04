"""Non-module dependencies configuration for rules_tf2.

This declares two groups of repositories:

* `@mdbook` — a downloaded mdbook binary used by the default (no-Nix) docs
  build. It is declared unconditionally but, like every repo here, only fetched
  when something actually depends on it.
* The Nix CC/Java toolchain repos — declared lazily and only fetched when a
  build opts into Nix via `--config=nix` (which references them through
  `--extra_toolchains`). A default build never touches them, so Nix is not
  required to build rules_tf2.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@rules_nixpkgs_cc//:cc.bzl", "nixpkgs_cc_configure")
load("@rules_nixpkgs_java//:java.bzl", "nixpkgs_java_configure")

_MDBOOK_VERSION = "0.4.52"
_MDBOOK_SHA256 = "c0b903f01dd8f4edc644372ad2b80b1fdddd12552d37b6a098657cbd8eddd768"

def _non_module_deps_impl(_):
    # Hermetic mdbook binary for the default (no-Nix) docs build. Linux x86_64
    # only — that is what CI and the dev Dockerfile use. On NixOS, build the book
    # with the flake dev-shell's mdbook instead (this downloaded glibc binary
    # does not run under Nix without an FHS shim).
    http_archive(
        name = "mdbook",
        urls = ["https://github.com/rust-lang/mdBook/releases/download/v{v}/mdbook-v{v}-x86_64-unknown-linux-gnu.tar.gz".format(v = _MDBOOK_VERSION)],
        sha256 = _MDBOOK_SHA256,
        build_file_content = 'exports_files(["mdbook"])',
    )

    # Nix CC/Java toolchains — fetched only under `--config=nix`.
    nixpkgs_cc_configure(
        name = "nixpkgs_config_cc",
        repository = "@nixpkgs",
        register = False,
    )

    nixpkgs_java_configure(
        name = "nixpkgs_java_runtime",
        attribute_path = "jdk21.home",
        repository = "@nixpkgs",
        toolchain = True,
        register = False,
        toolchain_name = "nixpkgs_java",
        toolchain_version = "21",
    )

    nixpkgs_java_configure(
        name = "nixpkgs_java_jdk",
        attribute_path = "jdk21",
        repository = "@nixpkgs",
        toolchain = True,
        register = False,
        toolchain_name = "nixpkgs_java_jdk",
        toolchain_version = "21",
    )

non_module_deps = module_extension(
    implementation = _non_module_deps_impl,
)
