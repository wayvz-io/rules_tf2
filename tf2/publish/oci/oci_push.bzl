"""Rules for pushing Terraform stacks to OCI registries."""

load(":config.bzl", "OCI_CONFIG")
load("//tf2/internal/providers:info.bzl", "TfModuleInfo")

def _oci_push_impl(ctx):
    """Implementation of oci_push rule."""
    tarball = ctx.actions.declare_file("{}.tar.gz".format(ctx.attr.name))
    config = ctx.actions.declare_file("{}.config.json".format(ctx.attr.name))
    push_script = ctx.actions.declare_file("{}_push.sh".format(ctx.attr.name))
    
    # Create a staging directory and copy files with proper structure
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.attr.name))
    
    # Build a command to create the staging directory and copy files
    copy_commands = []
    mkdir_commands = {}  # Track directories we need to create (use dict as set)
    
    for src_file in ctx.files.srcs:
        # Extract just the filename, removing all directory paths
        # This will put all files in the root of the tarball
        dest_name = src_file.basename
        
        # For files that might be in a modules/ subdirectory (from stack processing),
        # preserve that structure
        src_path = src_file.path
        if "/modules/" in src_path:
            # Find the modules/ part and preserve everything after it
            modules_idx = src_path.rfind("/modules/")
            if modules_idx != -1:
                # Get everything from modules/ onward
                dest_name = src_path[modules_idx + 1:]  # +1 to skip the leading /
                
                # Extract directory path and add mkdir command if needed
                dest_dir = dest_name.rsplit("/", 1)[0] if "/" in dest_name else ""
                if dest_dir:
                    mkdir_commands["mkdir -p '{}/{}'".format(staging_dir.path, dest_dir)] = True
        
        copy_commands.append("cp -L '{}' '{}/{}'".format(
            src_file.path,
            staging_dir.path,
            dest_name
        ))
    
    # Create the staging directory structure and copy files
    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
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
    
    # Create tarball from the staging directory
    ctx.actions.run_shell(
        inputs = [staging_dir],
        outputs = [tarball],
        command = "(cd '{}' && tar -czf - .) > '{}'".format(
            staging_dir.path,
            tarball.path,
        ),
        mnemonic = "CreateOCITarball",
        progress_message = "Creating OCI tarball for %s" % ctx.label,
    )
    
    # Create Flux-compatible config
    config_content = """{{
  "mediaType": "application/vnd.cncf.flux.config.v1+json",
  "source": "{source}",
  "revision": "{revision}",
  "path": "{path}"
}}""".format(
        source = ctx.attr.source_url,
        revision = ctx.attr.revision,
        path = ctx.attr.path,
    )
    
    ctx.actions.write(
        output = config,
        content = config_content,
    )
    
    # Create push script
    push_script_content = """#!/usr/bin/env bash
set -euo pipefail

# Resolve revision if it contains shell commands
REVISION="{}"
if [[ "$REVISION" == *'$$('* ]]; then
    REVISION=$(eval "echo $REVISION")
fi

# Resolve image tag if it contains shell commands
IMAGE="{}"
if [[ "$IMAGE" == *'$$('* ]]; then
    IMAGE=$(eval "echo $IMAGE")
fi

# Check if we can use gh auth token
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    echo "Using GitHub CLI authentication"
    export GH_USERNAME=$(gh api user --jq .login)
    export GH_TOKEN=$(gh auth token)
fi

# Check if authenticated
if ! oras login {} --username "${}" --password "${}" >/dev/null 2>&1; then
    echo "Failed to authenticate with registry"
    exit 1
fi

# Find the actual paths of the files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/{}"
TARBALL_PATH="$SCRIPT_DIR/{}"

# Push using oras with Flux media types
oras push "$IMAGE" \\
    --disable-path-validation \\
    --config "$CONFIG_PATH:application/vnd.cncf.flux.config.v1+json" \\
    "$TARBALL_PATH:application/vnd.cncf.flux.content.v1.tar+gzip" \\
    --annotation "org.opencontainers.image.source={}" \\
    --annotation "org.opencontainers.image.revision=$REVISION"

echo "Successfully pushed Terraform stack to $IMAGE"
""".format(
        ctx.attr.revision,
        ctx.attr.image,
        ctx.attr.registry,
        ctx.attr.username_env or "GH_USERNAME",
        ctx.attr.password_env or "GH_TOKEN",
        config.basename,  # Use basename instead of short_path
        tarball.basename,  # Use basename instead of short_path
        ctx.attr.source_url,
    )
    
    ctx.actions.write(
        output = push_script,
        content = push_script_content,
        is_executable = True,
    )
    
    return [
        DefaultInfo(
            files = depset([tarball, config, push_script, staging_dir]),
            executable = push_script,
        ),
    ]

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
            default = "GH_USERNAME",
            doc = "Environment variable containing registry username",
        ),
        "password_env": attr.string(
            default = "GH_TOKEN",
            doc = "Environment variable containing registry password",
        ),
    },
    executable = True,
    doc = """Push Terraform stacks to OCI registry.
    
    This rule creates a tarball from the provided source files and pushes it to an OCI
    registry using the media types expected by Flux's tf-controller.
    
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
    """Implementation of tf_module_push_oci rule."""
    # Get the module's files
    module_info = ctx.attr.module[TfModuleInfo]
    srcs = module_info.srcs.to_list()
    
    # Use the oci_push implementation logic
    tarball = ctx.actions.declare_file("{}.tar.gz".format(ctx.attr.name))
    config = ctx.actions.declare_file("{}.config.json".format(ctx.attr.name))
    push_script = ctx.actions.declare_file("{}_push.sh".format(ctx.attr.name))
    
    # Create a staging directory and copy files with proper structure
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.attr.name))
    
    # Build a command to create the staging directory and copy files
    copy_commands = []
    mkdir_commands = {}  # Track directories we need to create (use dict as set)
    
    for src_file in srcs:
        # Extract just the filename, removing all directory paths
        # This will put all files in the root of the tarball
        dest_name = src_file.basename
        
        # For files that might be in a modules/ subdirectory (from stack processing),
        # preserve that structure
        src_path = src_file.path
        if "/modules/" in src_path:
            # Find the modules/ part and preserve everything after it
            modules_idx = src_path.rfind("/modules/")
            if modules_idx != -1:
                # Get everything from modules/ onward
                dest_name = src_path[modules_idx + 1:]  # +1 to skip the leading /
                
                # Extract directory path and add mkdir command if needed
                dest_dir = dest_name.rsplit("/", 1)[0] if "/" in dest_name else ""
                if dest_dir:
                    mkdir_commands["mkdir -p '{}/{}'".format(staging_dir.path, dest_dir)] = True
        
        copy_commands.append("cp -L '{}' '{}/{}'".format(
            src_file.path,
            staging_dir.path,
            dest_name
        ))
    
    # Create the staging directory structure and copy files
    ctx.actions.run_shell(
        inputs = srcs,
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
    
    # Create tarball from the staging directory
    ctx.actions.run_shell(
        inputs = [staging_dir],
        outputs = [tarball],
        command = "(cd '{}' && tar -czf - .) > '{}'".format(
            staging_dir.path,
            tarball.path,
        ),
        mnemonic = "CreateOCITarball",
        progress_message = "Creating OCI tarball for %s" % ctx.label,
    )
    
    # Get package path for the source path in metadata
    package_path = ctx.label.package
    
    # Build the image URL with explicit stack name
    registry = ctx.attr.registry or OCI_CONFIG["registry"]
    repository = ctx.attr.repository or OCI_CONFIG["repository"]
    tag = ctx.attr.tag or OCI_CONFIG["default_tag"]
    image = "{}/{}/tf/{}:{}".format(registry, repository, ctx.attr.stack_name, tag)
    
    # Create Flux-compatible config
    config_content = """{{
  "mediaType": "application/vnd.cncf.flux.config.v1+json",
  "source": "{source}",
  "revision": "{revision}",
  "path": "{path}"
}}""".format(
        source = ctx.attr.source_url or "git@github.com:{}.git".format(repository),
        revision = ctx.attr.revision or "$$(git rev-parse HEAD)",
        path = ctx.attr.path or package_path,
    )
    
    ctx.actions.write(
        output = config,
        content = config_content,
    )
    
    # Create push script
    push_script_content = """#!/usr/bin/env bash
set -euo pipefail

# Resolve revision if it contains shell commands
REVISION="{}"
if [[ "$REVISION" == *'$$('* ]]; then
    REVISION=$(eval "echo $REVISION")
fi

# Resolve image tag if it contains shell commands
IMAGE="{}"
if [[ "$IMAGE" == *'$$('* ]]; then
    IMAGE=$(eval "echo $IMAGE")
fi

# Check if we can use gh auth token
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    echo "Using GitHub CLI authentication"
    export GH_USERNAME=$(gh api user --jq .login)
    export GH_TOKEN=$(gh auth token)
fi

# Check if authenticated
if ! oras login {} --username "${}" --password "${}" >/dev/null 2>&1; then
    echo "Failed to authenticate with registry"
    exit 1
fi

# Find the actual paths of the files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/{}"
TARBALL_PATH="$SCRIPT_DIR/{}"

# Push using oras with Flux media types
oras push "$IMAGE" \\
    --disable-path-validation \\
    --config "$CONFIG_PATH:application/vnd.cncf.flux.config.v1+json" \\
    "$TARBALL_PATH:application/vnd.cncf.flux.content.v1.tar+gzip" \\
    --annotation "org.opencontainers.image.source={}" \\
    --annotation "org.opencontainers.image.revision=$REVISION"

echo "Successfully pushed Terraform stack to $IMAGE"
""".format(
        ctx.attr.revision or "$$(git rev-parse HEAD)",
        image,
        registry,
        ctx.attr.username_env or "GH_USERNAME",
        ctx.attr.password_env or "GH_TOKEN",
        config.basename,
        tarball.basename,
        ctx.attr.source_url or "git@github.com:{}.git".format(repository),
    )
    
    ctx.actions.write(
        output = push_script,
        content = push_script_content,
        is_executable = True,
    )
    
    return [
        DefaultInfo(
            files = depset([tarball, config, push_script, staging_dir]),
            executable = push_script,
        ),
    ]

tf_module_push_oci = rule(
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
            doc = "OCI repository (defaults to wayvz-io/network_intent_manager)",
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
            default = "GH_USERNAME",
            doc = "Environment variable containing registry username",
        ),
        "password_env": attr.string(
            default = "GH_TOKEN",
            doc = "Environment variable containing registry password",
        ),
    },
    executable = True,
    doc = """Push Terraform stacks to OCI registry.
    
    This rule takes a tf_stack target and pushes it to an OCI registry using the 
    media types expected by Flux's tf-controller.
    
    Example:
        tf_stack(
            name = "hub",
            ...
        )
        
        tf_module_push_oci(
            name = "hub_push",
            stack = ":hub",
            stack_name = "aws/hub",
        )
    """,
)