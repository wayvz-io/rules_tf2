"""Rules for pushing Terraform stacks to OCI registries."""

load("//tf2/internal:docs_collection.bzl", "collect_module_docs")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")
load("//tf2/tools/runners:sh_toolchain.bzl", "SH_TOOLCHAIN_TYPE", "run_shell")
load(":config.bzl", "OCI_CONFIG")

# Flux (tf-controller) OCI artifact media types.
_FLUX_CONFIG_MEDIA_TYPE = "application/vnd.cncf.flux.config.v1+json"
_FLUX_CONTENT_MEDIA_TYPE = "application/vnd.cncf.flux.content.v1.tar+gzip"

_CONFIG_TEMPLATE = """{{
  "mediaType": "%s",
  "source": "{source}",
  "revision": "{revision}",
  "path": "{path}"
}}""" % _FLUX_CONFIG_MEDIA_TYPE

# Registry auth is deliberately env-driven, mirroring how rules_oci works: by
# default we do NOT log in at all and let `oras` resolve credentials from the
# ambient Docker config chain ($DOCKER_CONFIG/config.json + credential helpers).
# The __USERNAME_ENV__/__PASSWORD_ENV__ tokens are substituted with the rule's
# configured env var names; when both are set at runtime we perform an explicit
# login (useful for self-contained CI targets).
_AUTH_TEMPLATE = """# Authenticate to the registry.
#
# By default we rely on ambient OCI credentials, exactly like rules_oci: oras
# reads $DOCKER_CONFIG/config.json (default ~/.docker/config.json), including any
# configured credential helpers. Populate it once with `docker login $REGISTRY`
# or `oras login $REGISTRY` (or docker/login-action in CI).
#
# If both credential env vars are set, we run an explicit login for you (handy
# for self-contained CI targets); otherwise we skip login and let oras resolve
# credentials from the Docker config.
_OCI_USER="${__USERNAME_ENV__:-}"
_OCI_PASS="${__PASSWORD_ENV__:-}"
if [[ -n "$_OCI_USER" && -n "$_OCI_PASS" ]]; then
    echo "Logging in to $REGISTRY as $_OCI_USER"
    printf '%s' "$_OCI_PASS" | oras login "$REGISTRY" --username "$_OCI_USER" --password-stdin
fi"""

_PUSH_TEMPLATE = """#!/usr/bin/env bash
set -euo pipefail

# Resolve revision if it contains shell commands
REVISION="{revision}"
if [[ "$REVISION" == *'$$('* ]]; then
    REVISION=$(eval "echo $REVISION")
fi

# Resolve image tag if it contains shell commands
IMAGE="{image}"
if [[ "$IMAGE" == *'$$('* ]]; then
    IMAGE=$(eval "echo $IMAGE")
fi

REGISTRY="{registry}"
SOURCE_URL="{source_url}"

{auth}

# Find the actual paths of the files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/{config}"
TARBALL_PATH="$SCRIPT_DIR/{tarball}"

# Push using oras with Flux media types
oras push "$IMAGE" \\
    --disable-path-validation \\
    --config "$CONFIG_PATH:{config_media_type}" \\
    "$TARBALL_PATH:{content_media_type}" \\
    --annotation "org.opencontainers.image.source=$SOURCE_URL" \\
    --annotation "org.opencontainers.image.revision=$REVISION"

echo "Successfully pushed Terraform stack to $IMAGE"
"""

def _dest_name(src_file):
    """Compute the tarball-relative destination for a source file.

    Files land at the root of the tarball by basename, except those under a
    `modules/` subtree, whose structure from `modules/` onward is preserved.
    """
    dest_name = src_file.basename
    src_path = src_file.path
    if "/modules/" in src_path:
        modules_idx = src_path.rfind("/modules/")
        if modules_idx != -1:
            # Keep everything from `modules/` onward (+1 skips the leading slash).
            dest_name = src_path[modules_idx + 1:]
    return dest_name

def _stage_and_pack(ctx, entries):
    """Stage (File, dest_name) entries into a directory and tar+gzip it.

    Returns (tarball, staging_dir).
    """
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.attr.name))
    tarball = ctx.actions.declare_file("{}.tar.gz".format(ctx.attr.name))

    copy_commands = []
    mkdir_commands = {}  # Track directories we need to create (dict as a set).
    for src_file, dest_name in entries:
        if "/" in dest_name:
            dest_dir = dest_name.rsplit("/", 1)[0]
            mkdir_commands["mkdir -p '{}/{}'".format(staging_dir.path, dest_dir)] = True
        copy_commands.append("cp -L '{}' '{}/{}'".format(
            src_file.path,
            staging_dir.path,
            dest_name,
        ))

    run_shell(
        ctx,
        inputs = [src_file for src_file, _ in entries],
        outputs = [staging_dir],
        command = """
set -euo pipefail
mkdir -p '{staging_dir}'
{mkdir_commands}
{copy_commands}
""".format(
            staging_dir = staging_dir.path,
            mkdir_commands = "\n".join(sorted(mkdir_commands.keys())),
            copy_commands = "\n".join(copy_commands),
        ),
        mnemonic = "PrepareOCIContent",
        progress_message = "Preparing OCI content for %s" % ctx.label,
    )

    run_shell(
        ctx,
        inputs = [staging_dir],
        outputs = [tarball],
        command = "(cd '{}' && tar -czf - .) > '{}'".format(
            staging_dir.path,
            tarball.path,
        ),
        mnemonic = "CreateOCITarball",
        progress_message = "Creating OCI tarball for %s" % ctx.label,
    )

    return tarball, staging_dir

def _write_config(ctx, source, revision, path):
    """Write the Flux-compatible OCI config JSON."""
    config = ctx.actions.declare_file("{}.config.json".format(ctx.attr.name))
    ctx.actions.write(
        output = config,
        content = _CONFIG_TEMPLATE.format(
            source = source,
            revision = revision,
            path = path,
        ),
    )
    return config

def _write_push_script(ctx, image, registry, revision, source_url, config, tarball):
    """Write the executable oras push script."""
    push_script = ctx.actions.declare_file("{}_push.sh".format(ctx.attr.name))

    username_env = ctx.attr.username_env or "OCI_USERNAME"
    password_env = ctx.attr.password_env or "OCI_PASSWORD"
    auth = _AUTH_TEMPLATE.replace("__USERNAME_ENV__", username_env).replace("__PASSWORD_ENV__", password_env)

    ctx.actions.write(
        output = push_script,
        content = _PUSH_TEMPLATE.format(
            revision = revision,
            image = image,
            registry = registry,
            source_url = source_url,
            auth = auth,
            config = config.basename,
            tarball = tarball.basename,
            config_media_type = _FLUX_CONFIG_MEDIA_TYPE,
            content_media_type = _FLUX_CONTENT_MEDIA_TYPE,
        ),
        is_executable = True,
    )
    return push_script

def _build_flux_push(ctx, entries, image, registry, revision, source_url, path):
    """Shared build logic: stage sources, write config + push script.

    Returns the providers list for a push rule.
    """
    tarball, staging_dir = _stage_and_pack(ctx, entries)
    config = _write_config(ctx, source_url, revision, path)
    push_script = _write_push_script(ctx, image, registry, revision, source_url, config, tarball)

    return [
        DefaultInfo(
            files = depset([tarball, config, push_script, staging_dir]),
            executable = push_script,
        ),
    ]

def _oci_push_impl(ctx):
    """Implementation of oci_push rule."""
    entries = [(src_file, _dest_name(src_file)) for src_file in ctx.files.srcs]
    return _build_flux_push(
        ctx,
        entries = entries,
        image = ctx.attr.image,
        registry = ctx.attr.registry,
        revision = ctx.attr.revision,
        source_url = ctx.attr.source_url,
        path = ctx.attr.path,
    )

oci_push = rule(
    implementation = _oci_push_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            mandatory = True,
            doc = "Source files to package",
        ),
        "image": attr.string(
            mandatory = True,
            doc = "Full OCI image reference (e.g., ghcr.io/org/repo/module:tag)",
        ),
        "registry": attr.string(
            default = "ghcr.io",
            doc = "OCI registry hostname",
        ),
        "source_url": attr.string(
            mandatory = True,
            doc = "Source repository URL",
        ),
        "revision": attr.string(
            mandatory = True,
            doc = "Git revision/commit SHA",
        ),
        "path": attr.string(
            default = ".",
            doc = "Path within the source repository",
        ),
        "username_env": attr.string(
            default = "OCI_USERNAME",
            doc = "Environment variable holding the registry username. When set " +
                  "together with password_env, the push script logs in explicitly; " +
                  "otherwise it relies on ambient Docker credentials.",
        ),
        "password_env": attr.string(
            default = "OCI_PASSWORD",
            doc = "Environment variable holding the registry password/token. See username_env.",
        ),
    },
    executable = True,
    toolchains = [SH_TOOLCHAIN_TYPE],
    doc = """Push Terraform stacks to OCI registry.

    This rule creates a tarball from the provided source files and pushes it to an OCI
    registry using the media types expected by Flux's tf-controller.

    Authentication follows the ambient OCI credential chain by default (the same
    model as rules_oci): oras reads ~/.docker/config.json and any configured
    credential helpers. Run `docker login <registry>` / `oras login <registry>`
    (or docker/login-action in CI) beforehand, or set OCI_USERNAME/OCI_PASSWORD
    (see username_env/password_env) to have the push script log in for you.

    Example:
        oci_push(
            name = "push_stack",
            srcs = [":stack"],
            image = "ghcr.io/org/repo/tf/stack:latest",
            source_url = "git@github.com:org/repo.git",
            revision = "$(COMMIT_SHA)",
        )
    """,
)

def _tf_module_push_oci_impl(ctx):
    """Implementation of tf_publish_oci_flux rule."""
    module_info = ctx.attr.module[TfModuleInfo]
    srcs = module_info.srcs.to_list()

    # Collect documentation files from the module tree.
    docs_map = collect_module_docs(module_info)

    entries = [(src_file, _dest_name(src_file)) for src_file in srcs]
    entries += [(doc_file, dest_path) for dest_path, doc_file in docs_map.items()]

    registry = ctx.attr.registry or OCI_CONFIG["registry"]
    repository = ctx.attr.repository or OCI_CONFIG["repository"]
    tag = ctx.attr.tag or OCI_CONFIG["default_tag"]
    image = "{}/{}/tf/{}:{}".format(registry, repository, ctx.attr.stack_name, tag)

    source_url = ctx.attr.source_url or "git@github.com:{}.git".format(repository)
    revision = ctx.attr.revision or "$$(git rev-parse HEAD)"
    path = ctx.attr.path or ctx.label.package

    return _build_flux_push(
        ctx,
        entries = entries,
        image = image,
        registry = registry,
        revision = revision,
        source_url = source_url,
        path = path,
    )

tf_publish_oci_flux = rule(
    implementation = _tf_module_push_oci_impl,
    attrs = {
        "module": attr.label(
            mandatory = True,
            providers = [TfModuleInfo],
            doc = "The tf_module target to push to OCI",
        ),
        "stack_name": attr.string(
            mandatory = True,
            doc = "OCI stack name (e.g., 'aws/hub', 'bootstrap/cluster/flux')",
        ),
        "registry": attr.string(
            doc = "OCI registry hostname (defaults to ghcr.io)",
        ),
        "repository": attr.string(
            doc = "OCI repository (e.g. my-org/my-repo)",
        ),
        "tag": attr.string(
            doc = "Image tag (defaults to 'unstable')",
        ),
        "source_url": attr.string(
            doc = "Source repository URL (defaults to git@github.com:{repository}.git)",
        ),
        "revision": attr.string(
            doc = "Git revision/commit SHA (defaults to current HEAD)",
        ),
        "path": attr.string(
            doc = "Path within the source repository (defaults to package path)",
        ),
        "username_env": attr.string(
            default = "OCI_USERNAME",
            doc = "Environment variable holding the registry username. When set " +
                  "together with password_env, the push script logs in explicitly; " +
                  "otherwise it relies on ambient Docker credentials.",
        ),
        "password_env": attr.string(
            default = "OCI_PASSWORD",
            doc = "Environment variable holding the registry password/token. See username_env.",
        ),
    },
    executable = True,
    toolchains = [SH_TOOLCHAIN_TYPE],
    doc = """Push a Terraform module to an OCI registry.

    This rule takes a tf_module target and pushes it to an OCI registry using the
    media types expected by Flux's tf-controller.

    Authentication follows the ambient OCI credential chain by default (the same
    model as rules_oci): oras reads ~/.docker/config.json and any configured
    credential helpers. Run `docker login <registry>` / `oras login <registry>`
    (or docker/login-action in CI) beforehand, or set OCI_USERNAME/OCI_PASSWORD
    (see username_env/password_env) to have the push script log in for you.

    Example:
        tf_module(
            name = "hub",
            ...
        )

        tf_publish_oci_flux(
            name = "hub_push",
            module = ":hub",
            stack_name = "aws/hub",
        )
    """,
)
