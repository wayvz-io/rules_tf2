"""Non-module dependencies configuration for rules_tf2.

Declares the downloaded `@mdbook` binary used by the default docs build. Like
every repo here it is only fetched when something actually depends on it.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

_MDBOOK_VERSION = "0.4.52"
_MDBOOK_SHA256 = "c0b903f01dd8f4edc644372ad2b80b1fdddd12552d37b6a098657cbd8eddd768"

def _non_module_deps_impl(_):
    # Hermetic mdbook for the docs build (linux x86_64). On NixOS use the flake
    # dev-shell's mdbook — this glibc binary won't run under Nix.
    http_archive(
        name = "mdbook",
        urls = ["https://github.com/rust-lang/mdBook/releases/download/v{v}/mdbook-v{v}-x86_64-unknown-linux-gnu.tar.gz".format(v = _MDBOOK_VERSION)],
        sha256 = _MDBOOK_SHA256,
        build_file_content = 'exports_files(["mdbook"])',
    )

non_module_deps = module_extension(
    implementation = _non_module_deps_impl,
)
