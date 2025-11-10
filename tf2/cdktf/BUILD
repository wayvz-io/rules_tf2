# CDKTF support
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

package(default_visibility = ["//visibility:public"])

exports_files([
    "cdktf_common.bzl",
    "cdktf_repository_gazelle.bzl",
])

bzl_library(
    name = "cdktf_repository_gazelle",
    srcs = ["cdktf_repository_gazelle.bzl"],
    deps = [
        ":cdktf_common",
    ],
)

bzl_library(
    name = "cdktf_common",
    srcs = ["cdktf_common.bzl"],
)