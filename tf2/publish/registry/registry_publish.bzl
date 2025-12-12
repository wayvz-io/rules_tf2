"""Rules for publishing Terraform modules to Terraform Registry (HCP Terraform/TFE)."""

load("//tf2/internal:docs_collection.bzl", "collect_module_docs")
load("//tf2/providers/core:info.bzl", "TfModuleInfo")
load(":config.bzl", "REGISTRY_CONFIG")

def _tf_module_publish_impl(ctx):
    """Implementation of tf_module_publish rule."""

    # Get the module's files
    module_info = ctx.attr.module[TfModuleInfo]
    srcs = module_info.srcs.to_list()

    # Collect documentation files from module tree
    docs_map = collect_module_docs(module_info)
    doc_files = list(docs_map.values())

    # Declare output files
    tarball = ctx.actions.declare_file("{}.tar.gz".format(ctx.attr.name))
    publish_script = ctx.actions.declare_file("{}_publish.sh".format(ctx.attr.name))

    # Create a staging directory for module files
    staging_dir = ctx.actions.declare_directory("{}_staging".format(ctx.attr.name))

    # Build commands to copy files to staging directory
    copy_commands = []
    mkdir_commands = {}

    for src_file in srcs:
        # Preserve directory structure within the module
        # Get the relative path from the module's package
        src_path = src_file.path
        package_path = ctx.label.package

        # Determine the destination path
        if src_file.is_source:
            # For source files, try to preserve relative structure
            if package_path and src_path.startswith(package_path):
                # Remove package path prefix
                dest_name = src_path[len(package_path) + 1:] if len(package_path) > 0 else src_path
            else:
                # Fallback to basename
                dest_name = src_file.basename
        else:
            # For generated files, use basename
            dest_name = src_file.basename

        # Handle nested directories
        if "/" in dest_name:
            dest_dir = dest_name.rsplit("/", 1)[0]
            mkdir_commands["mkdir -p '{}/{}'".format(staging_dir.path, dest_dir)] = True

        copy_commands.append("cp -L '{}' '{}/{}'".format(
            src_file.path,
            staging_dir.path,
            dest_name,
        ))

    # Add documentation files with correct destination paths
    for dest_path, doc_file in docs_map.items():
        if "/" in dest_path:
            dest_dir = dest_path.rsplit("/", 1)[0]
            mkdir_commands["mkdir -p '{}/{}'".format(staging_dir.path, dest_dir)] = True
        copy_commands.append("cp -L '{}' '{}/{}'".format(
            doc_file.path,
            staging_dir.path,
            dest_path,
        ))

    # Create staging directory and copy files
    ctx.actions.run_shell(
        inputs = srcs + doc_files,
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
        mnemonic = "PrepareModuleContent",
        progress_message = "Preparing module content for %s" % ctx.label,
    )

    # Create tarball from staging directory
    ctx.actions.run_shell(
        inputs = [staging_dir],
        outputs = [tarball],
        command = "(cd '{}' && tar -czf - .) > '{}'".format(
            staging_dir.path,
            tarball.path,
        ),
        mnemonic = "CreateModuleTarball",
        progress_message = "Creating module tarball for %s" % ctx.label,
    )

    # Determine registry configuration
    registry = ctx.attr.registry or REGISTRY_CONFIG["registry"]
    registry_name = REGISTRY_CONFIG["registry_name"]
    api_base = REGISTRY_CONFIG["api_base_path"]

    # Create publish script
    publish_script_content = '''#!/usr/bin/env bash
set -euo pipefail

# Configuration
ORGANIZATION="{organization}"
MODULE_NAME="{module_name}"
PROVIDER="{provider}"
REGISTRY="{registry}"
REGISTRY_NAME="{registry_name}"
API_BASE="{api_base}"
NAMESPACE="{namespace}"
VERSION_INCREMENT="{version_increment}"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version-type)
            VERSION_INCREMENT="$2"
            shift 2
            ;;
        --version)
            EXPLICIT_VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--version-type major|minor|patch] [--version X.Y.Z]"
            exit 1
            ;;
    esac
done

# Check for TFE_TOKEN
if [[ -z "${{TFE_TOKEN:-}}" ]]; then
    echo "Error: TFE_TOKEN environment variable is required"
    echo "Please set TFE_TOKEN with your Terraform Cloud/Enterprise API token"
    exit 1
fi

# Resolve the actual path to the tarball
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARBALL_PATH="$SCRIPT_DIR/{tarball_basename}"

if [[ ! -f "$TARBALL_PATH" ]]; then
    echo "Error: Tarball not found at $TARBALL_PATH"
    exit 1
fi

# Function to make API calls
api_call() {{
    local method="$1"
    local endpoint="$2"
    local data="${{3:-}}"

    local url="https://${{REGISTRY}}${{API_BASE}}${{endpoint}}"

    if [[ -n "$data" ]]; then
        curl -s -X "$method" "$url" \\
            -H "Authorization: Bearer $TFE_TOKEN" \\
            -H "Content-Type: application/vnd.api+json" \\
            -d "$data"
    else
        curl -s -X "$method" "$url" \\
            -H "Authorization: Bearer $TFE_TOKEN" \\
            -H "Content-Type: application/vnd.api+json"
    fi
}}

# Function to calculate next version
calculate_next_version() {{
    local current="$1"
    local increment_type="${{2:-minor}}"

    # Parse version components
    IFS='.' read -r major minor patch <<< "$current"

    # Set defaults if components are missing
    major="${{major:-0}}"
    minor="${{minor:-0}}"
    patch="${{patch:-0}}"

    case "$increment_type" in
        major)
            ((major++))
            minor=0
            patch=0
            ;;
        minor)
            ((minor++))
            patch=0
            ;;
        patch)
            ((patch++))
            ;;
        *)
            echo "Error: Unknown version increment type: $increment_type"
            exit 1
            ;;
    esac

    echo "${{major}}.${{minor}}.${{patch}}"
}}

echo "Publishing module: $ORGANIZATION/$MODULE_NAME/$PROVIDER"
echo "Registry: $REGISTRY"

# Check if module exists
MODULE_ENDPOINT="/organizations/${{ORGANIZATION}}/registry-modules/${{REGISTRY_NAME}}/${{NAMESPACE}}/${{MODULE_NAME}}/${{PROVIDER}}"
MODULE_RESPONSE=$(api_call GET "$MODULE_ENDPOINT" 2>/dev/null || true)

if [[ -z "$MODULE_RESPONSE" ]] || echo "$MODULE_RESPONSE" | grep -q '"errors"'; then
    echo "Module does not exist. Creating new module..."

    # Create module
    CREATE_DATA='{{
        "data": {{
            "type": "registry-modules",
            "attributes": {{
                "name": "'$MODULE_NAME'",
                "provider": "'$PROVIDER'",
                "registry-name": "'$REGISTRY_NAME'"
            }}
        }}
    }}'

    CREATE_RESPONSE=$(api_call POST "/organizations/${{ORGANIZATION}}/registry-modules" "$CREATE_DATA")

    if echo "$CREATE_RESPONSE" | grep -q '"errors"'; then
        echo "Error creating module:"
        echo "$CREATE_RESPONSE" | jq .
        exit 1
    fi

    echo "Module created successfully"
    CURRENT_VERSION="0.0.0"
else
    echo "Module exists. Fetching latest version..."

    # Get the module details using the correct endpoint
    MODULE_ENDPOINT="/organizations/${{ORGANIZATION}}/registry-modules/${{REGISTRY_NAME}}/${{NAMESPACE}}/${{MODULE_NAME}}/${{PROVIDER}}"
    MODULE_RESPONSE=$(api_call GET "$MODULE_ENDPOINT" 2>/dev/null || true)

    if [[ -n "$MODULE_RESPONSE" ]] && ! echo "$MODULE_RESPONSE" | grep -q '"errors"'; then
        # Extract versions from version-statuses array
        CURRENT_VERSION=$(echo "$MODULE_RESPONSE" | jq -r '.data.attributes["version-statuses"][].version' 2>/dev/null | sort -rV | head -1)

        if [[ -z "$CURRENT_VERSION" ]] || [[ "$CURRENT_VERSION" == "null" ]]; then
            CURRENT_VERSION="0.0.0"
        fi
    else
        # Fallback: List all modules and filter
        echo "Direct module endpoint failed, trying module list..."
        MODULES_ENDPOINT="/organizations/${{ORGANIZATION}}/registry-modules"
        MODULES_RESPONSE=$(api_call GET "$MODULES_ENDPOINT" 2>/dev/null || true)

        if [[ -n "$MODULES_RESPONSE" ]] && ! echo "$MODULES_RESPONSE" | grep -q '"errors"'; then
            CURRENT_VERSION=$(echo "$MODULES_RESPONSE" | jq -r ".data[] | select(.attributes.name == \"$MODULE_NAME\" and .attributes.provider == \"$PROVIDER\") | .attributes[\"version-statuses\"][].version" 2>/dev/null | sort -rV | head -1)

            if [[ -z "$CURRENT_VERSION" ]] || [[ "$CURRENT_VERSION" == "null" ]]; then
                CURRENT_VERSION="0.0.0"
            fi
        else
            CURRENT_VERSION="0.0.0"
            echo "Warning: Could not fetch current version via API, defaulting to 0.0.0"
            echo "You may need to specify an explicit version with --version"
        fi
    fi

    echo "Current version: $CURRENT_VERSION"
fi

# Determine new version
if [[ -n "${{EXPLICIT_VERSION:-}}" ]]; then
    NEW_VERSION="$EXPLICIT_VERSION"
    echo "Using explicit version: $NEW_VERSION"
else
    NEW_VERSION=$(calculate_next_version "$CURRENT_VERSION" "$VERSION_INCREMENT")
    echo "Calculated new version: $NEW_VERSION (increment: $VERSION_INCREMENT)"
fi

# Create new version
echo "Creating version $NEW_VERSION..."

VERSION_DATA='{{
    "data": {{
        "type": "registry-module-versions",
        "attributes": {{
            "version": "'$NEW_VERSION'"
        }}
    }}
}}'

VERSION_ENDPOINT="/organizations/${{ORGANIZATION}}/registry-modules/${{REGISTRY_NAME}}/${{NAMESPACE}}/${{MODULE_NAME}}/${{PROVIDER}}/versions"
VERSION_RESPONSE=$(api_call POST "$VERSION_ENDPOINT" "$VERSION_DATA")

if echo "$VERSION_RESPONSE" | grep -q '"errors"'; then
    echo "Error creating version:"
    echo "$VERSION_RESPONSE" | jq .
    exit 1
fi

# Extract upload URL
UPLOAD_URL=$(echo "$VERSION_RESPONSE" | jq -r '.data.links.upload')

if [[ -z "$UPLOAD_URL" ]] || [[ "$UPLOAD_URL" == "null" ]]; then
    echo "Error: No upload URL in response"
    echo "$VERSION_RESPONSE" | jq .
    exit 1
fi

echo "Uploading module archive..."

# Upload the tarball
UPLOAD_RESPONSE=$(curl -s -X PUT "$UPLOAD_URL" \\
    -H "Content-Type: application/octet-stream" \\
    --data-binary "@$TARBALL_PATH")

# Check if upload was successful (PUT typically returns empty response on success)
if [[ -n "$UPLOAD_RESPONSE" ]]; then
    if echo "$UPLOAD_RESPONSE" | grep -q '"errors"'; then
        echo "Error uploading module:"
        echo "$UPLOAD_RESPONSE" | jq . 2>/dev/null || echo "$UPLOAD_RESPONSE"
        exit 1
    fi
fi

echo "Successfully published $ORGANIZATION/$MODULE_NAME/$PROVIDER version $NEW_VERSION"
echo ""
echo "Module URL: https://$REGISTRY/app/$ORGANIZATION/modules/view/$MODULE_NAME/$PROVIDER/$NEW_VERSION"
echo ""
echo "To use this module in Terraform:"
echo "  module \\"example\\" {{"
echo "    source  = \\"$REGISTRY/$ORGANIZATION/$MODULE_NAME/$PROVIDER\\""
echo "    version = \\"$NEW_VERSION\\""
echo "  }}"
'''.format(
        organization = ctx.attr.organization,
        module_name = ctx.attr.module_name,
        provider = ctx.attr.provider,
        registry = registry,
        registry_name = registry_name,
        api_base = api_base,
        namespace = ctx.attr.namespace or ctx.attr.organization,
        version_increment = ctx.attr.version_increment or REGISTRY_CONFIG["default_version_increment"],
        tarball_basename = tarball.basename,
    )

    ctx.actions.write(
        output = publish_script,
        content = publish_script_content,
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([tarball, publish_script, staging_dir]),
            executable = publish_script,
        ),
    ]

tf_publish_registry = rule(
    implementation = _tf_module_publish_impl,
    attrs = {
        "module": attr.label(
            mandatory = True,
            providers = [TfModuleInfo],
            doc = "The tf_module target to publish to Terraform Registry",
        ),
        "organization": attr.string(
            mandatory = True,
            doc = "Terraform Cloud/Enterprise organization name",
        ),
        "module_name": attr.string(
            mandatory = True,
            doc = "Name of the module in the registry",
        ),
        "provider": attr.string(
            mandatory = True,
            doc = "Terraform provider for this module (e.g., 'aws', 'google', 'azurerm')",
        ),
        "registry": attr.string(
            doc = "Registry hostname (defaults to app.terraform.io)",
        ),
        "namespace": attr.string(
            doc = "Module namespace (defaults to organization name)",
        ),
        "version_increment": attr.string(
            default = "patch",
            doc = "Default version increment type: major, minor, or patch",
        ),
    },
    executable = True,
    doc = """Publish Terraform modules to Terraform Registry (HCP Terraform/TFE).

    This rule packages a tf_module and publishes it to a Terraform Registry using
    the direct upload API. It automatically manages versioning by fetching the
    current version and incrementing it.

    Authentication requires TFE_TOKEN environment variable to be set.

    Example:
        tf_module(
            name = "my_module",
            ...
        )

        tf_publish_registry(
            name = "my_module_publish",
            module = ":my_module",
            organization = "my-org",
            module_name = "my-terraform-module",
            provider = "aws",
        )

    Usage:
        # Publish with default patch version increment
        TFE_TOKEN=xxx bazel run //path:my_module_publish

        # Publish with minor version increment
        TFE_TOKEN=xxx bazel run //path:my_module_publish -- --version-type minor

        # Publish with major version increment
        TFE_TOKEN=xxx bazel run //path:my_module_publish -- --version-type major

        # Publish with explicit version
        TFE_TOKEN=xxx bazel run //path:my_module_publish -- --version 2.0.0
    """,
)
