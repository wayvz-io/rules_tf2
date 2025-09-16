"""Defines the go_sdk module extension with nixpkgs support."""

load("@rules_nixpkgs_go//:go.bzl", "nixpkgs_go_configure")
load("@rules_go//go/private:platforms.bzl", "PLATFORMS")

def _nixpkgs_go_toolchain(nixpkgs_go):
    nixpkgs_go_configure(
        repository = nixpkgs_go.nixpkgs_repository,
        sdk_name = nixpkgs_go.name,
        register = False,  # Don't register in extension,
        attribute_path = "go_1_24",  # Use Go 1.24 from nixpkgs
    )

def _go_sdk_impl(module_ctx):
    for mod in module_ctx.modules:
        for nixpkgs_go in mod.tags.nixpkgs:
            _nixpkgs_go_toolchain(nixpkgs_go)

    return module_ctx.extension_metadata(
        root_module_direct_deps = [tag.name for mod in module_ctx.modules for tag in mod.tags.nixpkgs] +
                                [tag.name + "_toolchains" for mod in module_ctx.modules for tag in mod.tags.nixpkgs],
        root_module_direct_dev_deps = [],
    )

_nixpkgs_tag = tag_class(
    attrs = {
        "name": attr.string(
            doc = "Name of the Go SDK repository",
            mandatory = True,
        ),
        "nixpkgs_repository": attr.string(
            doc = "The nixpkgs repository to use",
            mandatory = True,
        ),
    },
    doc = "Configure Go SDK from nixpkgs",
)

go_sdk = module_extension(
    implementation = _go_sdk_impl,
    tag_classes = {
        "nixpkgs": _nixpkgs_tag,
    },
)