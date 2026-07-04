# Bazel development image for rules_tf2.
#
# This image exists purely for reproducible local-dev parity: it bundles the
# same stock/hermetic Bazel toolchains that CI uses (bare ubuntu + bazelisk),
# so a build here matches a build on the runner. bazelisk reads the repo's
# .bazelversion to select the exact Bazel version, matching CI.
#
# It is NOT required for normal use. bazelisk on your host works just as well;
# reach for this image only when you want a clean, deterministic environment.
#
# Usage — mount the repo and run any bazel command against it:
#
#   docker run --rm -it -v "$PWD":/workspace <img> bazel test //...
#
# nix is optional in this ruleset; the default build path needs none of it,
# which is why this image ships no nix at all.

FROM ubuntu:24.04

# Toolchain prerequisites:
#   build-essential      - gcc/g++/make for the C/C++ hermetic toolchain
#   default-jdk-headless - Bazel itself runs on a JVM
#   git, curl, ca-certs  - fetching sources and bazelisk-managed downloads
#   python3              - required by various Bazel rules at runtime
#   unzip, zip           - archive handling used throughout the build
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        default-jdk-headless \
        git \
        curl \
        ca-certificates \
        python3 \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/*

# Install bazelisk as `bazel`. On first invocation bazelisk reads the mounted
# repo's .bazelversion and downloads that exact Bazel version, so the image
# tracks whatever version the repo pins (no hardcoded version here).
ARG BAZELISK_VERSION=v1.25.0
RUN curl -fsSL \
        "https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-amd64" \
        -o /usr/local/bin/bazel \
    && chmod +x /usr/local/bin/bazel

# Devs mount their checkout here.
WORKDIR /workspace
