"""Non-module dependencies configuration for rules_tf2.

Declares the downloaded `@mdbook` and `@mdbook_linkcheck` binaries used by the
default docs build. Like every repo here they are only fetched when something
actually depends on them.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

_MDBOOK_VERSION = "0.4.52"
_MDBOOK_SHA256 = "c0b903f01dd8f4edc644372ad2b80b1fdddd12552d37b6a098657cbd8eddd768"

_MDBOOK_LINKCHECK_VERSION = "0.7.7"
_MDBOOK_LINKCHECK_SHA256 = "18cebca9493804b307b39a44af2664cdfa881e84b8d92a94205d6c51572318ef"

def _non_module_deps_impl(_):
    # Hermetic mdbook for the docs build (linux x86_64, glibc). The docs build
    # runs in the rules_tf2-dev container (bare ubuntu), so this binary runs as-is.
    http_archive(
        name = "mdbook",
        urls = ["https://github.com/rust-lang/mdBook/releases/download/v{v}/mdbook-v{v}-x86_64-unknown-linux-gnu.tar.gz".format(v = _MDBOOK_VERSION)],
        sha256 = _MDBOOK_SHA256,
        build_file_content = 'exports_files(["mdbook"])',
    )

    # mdbook-linkcheck runs standalone against the assembled book to catch dead
    # internal links. Note it validates *source* link targets, so it flags
    # genuinely-missing pages but not mdbook's own README.md -> README.html
    # render bug (guarded separately in //docs:link_check by a source lint).
    http_archive(
        name = "mdbook_linkcheck",
        urls = ["https://github.com/Michael-F-Bryan/mdbook-linkcheck/releases/download/v{v}/mdbook-linkcheck.x86_64-unknown-linux-gnu.zip".format(v = _MDBOOK_LINKCHECK_VERSION)],
        sha256 = _MDBOOK_LINKCHECK_SHA256,
        # The .zip (unlike mdbook's .tar.gz) drops the executable bit on extract.
        patch_cmds = ["chmod +x mdbook-linkcheck"],
        build_file_content = 'exports_files(["mdbook-linkcheck"])',
    )

non_module_deps = module_extension(
    implementation = _non_module_deps_impl,
)
