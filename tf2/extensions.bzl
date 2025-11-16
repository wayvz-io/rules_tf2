"""Module extensions for tf2"""

load("//tf2/providers/download:provider_download_repository.bzl", "provider_download_repository")
load("//tf2/providers/repository:terraform_providers.bzl", "terraform_providers")
load("//tf2/providers/repository:versions.bzl", "get_tflint_plugin_version", "get_tool_version", "parse_versions_json")
load("//tf2/tools/download:registry.bzl", "tflint_plugin_registry", "tool_registry")
load("//tf2/tools/download:terraform.bzl", "download_terraform")
load("//tf2/tools/download:terraform_docs.bzl", "download_terraform_docs")
load("//tf2/tools/download:tflint.bzl", "download_tflint", "download_tflint_plugin")
# CDKTF support is disabled - not yet functional
# load("//tf2/cdktf:cdktf_repository_gazelle.bzl", "cdktf_bindings_repository_gazelle")

def _parse_lock_file_to_json(content):
    """Parse terraform.lock.hcl content into JSON structure.

    Returns a dict mapping provider names to their lock data.
    """
    providers = {}
    current_provider = None
    current_data = {}
    in_hashes = False
    hashes = []

    for line in content.split("\n"):
        line = line.strip()

        # Start of provider block
        if line.startswith('provider "'):
            # Save previous provider if exists
            if current_provider and current_data:
                providers[current_provider] = current_data

            # Extract provider name
            parts = line.split('"')
            if len(parts) >= 2:
                # Remove registry prefix if present
                provider_name = parts[1].replace("registry.terraform.io/", "")
                current_provider = provider_name
                current_data = {}
                in_hashes = False
                hashes = []

        elif current_provider:
            # Parse version
            if line.startswith("version"):
                parts = line.split('"')
                if len(parts) >= 2:
                    current_data["version"] = parts[1]

                # Parse constraints
            elif line.startswith("constraints"):
                parts = line.split('"')
                if len(parts) >= 2:
                    current_data["constraints"] = parts[1]

                # Parse hashes
            elif line.startswith("hashes = ["):
                in_hashes = True
                hashes = []
            elif in_hashes:
                if "]" in line:
                    in_hashes = False
                    current_data["hashes"] = hashes
                elif '"' in line:
                    parts = line.split('"')
                    if len(parts) >= 2:
                        hashes.append(parts[1])

    # Save last provider
    if current_provider and current_data:
        providers[current_provider] = current_data

    return providers

def _tf_providers_impl(module_ctx):
    """Implementation of tf_providers module extension"""

    main_providers = {}
    main_aliases = {}
    main_hashes = {}

    test_providers = {}
    test_aliases = {}
    test_hashes = {}

    # Process provider downloads from modules
    for mod in module_ctx.modules:
        if mod.is_root:  # Root module only
            for download in mod.tags.download:
                # Require explicit versions_file path
                if not download.versions_file:
                    fail("versions_file must be specified in tf_providers.download()")

                versions_path = download.versions_file
                lock_path = download.lock_file

                # Read versions from the specified file
                versions_file = Label("@@//:" + versions_path)
                versions_content = module_ctx.read(versions_file)
                versions_data = json.decode(versions_content)

                # Read and parse lock file content for hashes (now mandatory)
                lock_file = Label("@@//:" + lock_path)
                lock_file_parsed = {}

                # Read lock file content, with fallback for missing files
                lock_content = module_ctx.read(lock_file)
                if not lock_content or len(lock_content.strip()) == 0:
                    # Lock file exists but is empty - allow tf-update to populate it
                    # Warn that provider downloads will fail without hashes
                    if "providers" in versions_data and versions_data["providers"]:
                        # Warning: Lock file is empty but providers exist
                        pass
                    lock_content = "{}"  # Treat as empty JSON
                else:
                    # Parse the lock file content
                    if lock_path.endswith(".json"):
                        # Parse as JSON directly - format is {"provider:version": {"h1": [...], "zh": [...]}}
                        lock_file_parsed = json.decode(lock_content)
                    else:
                        # Parse as HCL terraform.lock.hcl format
                        lock_file_parsed = _parse_lock_file_to_json(lock_content)

                # Validate that we have lock data if we have providers
                if "providers" in versions_data and versions_data["providers"]:
                    if not lock_file_parsed:
                        fail("Provider versions found in versions.json but no valid lock data found in '{}'.\nRun 'bazel run //:tf-update' to generate provider locks.".format(lock_path))

                # Process providers from versions.json and lock file if available
                if "providers" in versions_data:
                    main_providers = versions_data["providers"]
                    for provider, versions in main_providers.items():
                        provider_name = provider.split("/")[-1]
                        for version in versions:
                            major_version = version.split(".")[0]
                            alias_name = "{}_{}".format(provider_name, major_version)
                            main_aliases[alias_name] = [provider, version]

                            # Extract hashes from lock file if available
                            provider_key = "{}:{}".format(provider, version)
                            if lock_path and lock_path.endswith(".json"):
                                # New JSON format: {"provider:version": {"h1": [...], "zh": [...]}}
                                if provider_key in lock_file_parsed:
                                    hash_data = lock_file_parsed[provider_key]

                                    # Combine all hash formats into a single list with proper prefixes
                                    all_hashes = []
                                    for hash_type in ["h1", "zh"]:
                                        if hash_type in hash_data:
                                            for hash_val in hash_data[hash_type]:
                                                all_hashes.append("{}:{}".format(hash_type, hash_val))
                                    if all_hashes:
                                        main_hashes[provider_key] = all_hashes
                            else:
                                # Old HCL format: {"provider": {"version": "...", "hashes": [...]}}
                                if provider in lock_file_parsed:
                                    lock_data = lock_file_parsed[provider]
                                    if lock_data.get("version") == version and lock_data.get("hashes"):
                                        main_hashes[provider_key] = lock_data["hashes"]

        elif mod.name == "tf2":  # tf2 module
            for download in mod.tags.download:
                # Require explicit paths - no defaults
                if not download.versions_file:
                    fail("versions_file must be specified in tf_providers.download() for tf2 module")
                if not download.lock_file:
                    fail("lock_file must be specified in tf_providers.download() for tf2 module")

                versions_path = download.versions_file
                lock_path = download.lock_file

                # Read from tf2 module
                versions_file = Label("@rules_tf2//:" + versions_path)
                versions_content = module_ctx.read(versions_file)
                versions_data = json.decode(versions_content)

                # Read and parse lock file content for hashes (now mandatory)
                lock_file = Label("@rules_tf2//:" + lock_path)
                lock_file_parsed = {}

                # Read lock file content, with fallback for missing files
                lock_content = module_ctx.read(lock_file)
                if not lock_content or len(lock_content.strip()) == 0:
                    # Lock file exists but is empty - allow tf-update to populate it
                    # Warn that provider downloads will fail without hashes
                    if "providers" in versions_data and versions_data["providers"]:
                        # Warning: Lock file is empty but providers exist
                        pass
                    lock_content = "{}"  # Treat as empty JSON
                else:
                    # Parse the lock file content
                    if lock_path.endswith(".json"):
                        # Parse as JSON directly - format is {"provider:version": {"h1": [...], "zh": [...]}}
                        lock_file_parsed = json.decode(lock_content)
                    else:
                        # Parse as HCL terraform.lock.hcl format
                        lock_file_parsed = _parse_lock_file_to_json(lock_content)

                # Validate that we have lock data if we have providers
                if "providers" in versions_data and versions_data["providers"]:
                    if not lock_file_parsed:
                        fail("Provider versions found in versions.json but no valid lock data found in '{}'.\nRun 'bazel run //:tf-update' to generate provider locks.".format(lock_path))

                # Process providers from versions.json and lock file if available
                if "providers" in versions_data:
                    test_providers = versions_data["providers"]
                    for provider, versions in test_providers.items():
                        provider_name = provider.split("/")[-1]
                        for version in versions:
                            major_version = version.split(".")[0]
                            alias_name = "{}_{}".format(provider_name, major_version)
                            test_aliases[alias_name] = [provider, version]

                            # Extract hashes from lock file if available
                            provider_key = "{}:{}".format(provider, version)
                            if lock_path and lock_path.endswith(".json"):
                                # New JSON format: {"provider:version": {"h1": [...], "zh": [...]}}
                                if provider_key in lock_file_parsed:
                                    hash_data = lock_file_parsed[provider_key]

                                    # Combine all hash formats into a single list with proper prefixes
                                    all_hashes = []
                                    for hash_type in ["h1", "zh"]:
                                        if hash_type in hash_data:
                                            for hash_val in hash_data[hash_type]:
                                                all_hashes.append("{}:{}".format(hash_type, hash_val))
                                    if all_hashes:
                                        test_hashes[provider_key] = all_hashes
                            else:
                                # Old HCL format: {"provider": {"version": "...", "hashes": [...]}}
                                if provider in lock_file_parsed:
                                    lock_data = lock_file_parsed[provider]
                                    if lock_data.get("version") == version and lock_data.get("hashes"):
                                        test_hashes[provider_key] = lock_data["hashes"]

    # Consolidate both provider sets into a single registry
    combined_providers = {}
    combined_aliases = {}
    combined_hashes = {}

    # Start with main providers
    if main_providers:
        combined_providers.update(main_providers)
        combined_aliases.update(main_aliases)
        combined_hashes.update(main_hashes)

    # Add test providers (they won't conflict since they're different namespaces)
    if test_providers:
        for provider, versions in test_providers.items():
            if provider in combined_providers:
                # Merge version lists if provider exists in both
                for version in versions:
                    if version not in combined_providers[provider]:
                        combined_providers[provider].append(version)
            else:
                combined_providers[provider] = versions

        combined_aliases.update(test_aliases)
        combined_hashes.update(test_hashes)

    # Create individual provider download repositories for each provider/version/platform
    # These repositories download providers during the loading phase
    created_repositories = {}
    if combined_providers:
        platforms = [
            ("linux", "amd64"),
            ("linux", "arm64"),
            ("darwin", "amd64"),
            ("darwin", "arm64"),
        ]

        for provider_source, versions in combined_providers.items():
            _, provider_name = provider_source.split("/")

            for version in versions:
                provider_key = "{}:{}".format(provider_source, version)

                # Get hashes for this provider:version
                hashes = combined_hashes.get(provider_key, [])

                # Extract zh hashes (hex SHA256) for download verification
                zh_hashes = []
                for hash_val in hashes:
                    if hash_val.startswith("zh:"):
                        zh_hashes.append(hash_val[3:])  # Remove "zh:" prefix

                # Create a repository for each platform
                for os_name, arch in platforms:
                    platform_str = "{}_{}".format(os_name, arch)

                    # Repository name: tf_provider_{name}_{version}_{os}_{arch}
                    # Replace dots with underscores for valid repository names
                    repo_name = "tf_provider_{}_{}_{}".format(
                        provider_name,
                        version.replace(".", "_"),
                        platform_str,
                    )

                    # Create the provider download repository
                    provider_download_repository(
                        name = repo_name,
                        provider_source = provider_source,
                        version = version,
                        os_name = os_name,
                        arch = arch,
                        sha256 = ",".join(zh_hashes) if zh_hashes else "",
                    )

                    # Track created repositories for terraform_providers to reference
                    if provider_source not in created_repositories:
                        created_repositories[provider_source] = {}
                    if version not in created_repositories[provider_source]:
                        created_repositories[provider_source][version] = {}
                    created_repositories[provider_source][version][platform_str] = repo_name

    # Create registry based on what we have
    if combined_providers:
        # We have actual providers - create real registry
        terraform_providers(
            name = "tf_provider_registry",
            providers = combined_providers,
            aliases = combined_aliases,
            provider_hashes = combined_hashes,
            provider_repositories_json = json.encode(created_repositories),
        )
    else:
        # No providers found (likely because we're a dependency, not root)
        # Create empty stub repository so references don't fail
        terraform_providers(
            name = "tf_provider_registry",
            providers = {},
            aliases = {},
            provider_hashes = {},
            provider_repositories_json = "{}",
        )

# Tag class for the download configuration
_download = tag_class(
    attrs = {
        "providers": attr.string_list_dict(
            doc = "Provider configuration with multiple versions (e.g., {'hashicorp/aws': ['6.2.0', '5.0.0']})",
            mandatory = False,
        ),
        "mirror": attr.string_dict(
            doc = "Legacy provider mirror configuration (e.g., {'aws': 'hashicorp/aws:6.2.0'})",
            mandatory = False,
        ),
        "versions_file": attr.string(
            doc = "Path to versions.json file",
            mandatory = True,
        ),
        "lock_file": attr.string(
            doc = "Path to provider_locks.json file (required for deterministic builds)",
            mandatory = True,
        ),
    },
)

tf_providers = module_extension(
    implementation = _tf_providers_impl,
    tag_classes = {
        "download": _download,
    },
)

def _cdktf_providers_impl(module_ctx):
    """Implementation of cdktf_providers module extension"""

    # Collect all CDKTF generation requests from modules
    all_cdktf_providers = {}

    for mod in module_ctx.modules:
        for generate in mod.tags.generate:
            provider = generate.provider
            version = generate.version
            language = generate.language or "go"

            # Extract provider name and major version for repository naming
            provider_name = provider.split("/")[-1]  # e.g., "aws" from "hashicorp/aws"
            major_version = version.split(".")[0]  # e.g., "6" from "6.2.0"

            # Create repository name like "cdktf_aws_6"
            repo_name = "cdktf_{}_{}_go".format(provider_name, major_version)

            # CDKTF support is disabled - not yet functional
            # cdktf_bindings_repository_gazelle(
            #     name = repo_name,
            #     provider_name = provider_name,
            #     provider_source = provider,
            #     provider_version = version,
            # )
            pass  # Placeholder until CDKTF is fully implemented

            # Store for potential future use
            all_cdktf_providers[repo_name] = {
                "provider": provider,
                "version": version,
                "language": language,
            }

# Tag class for CDKTF generation configuration
_generate = tag_class(
    attrs = {
        "provider": attr.string(
            doc = "Provider source (e.g., 'hashicorp/aws')",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "Provider version (e.g., '6.2.0')",
            mandatory = True,
        ),
        "language": attr.string(
            doc = "Target language for generation",
            default = "go",
            values = ["typescript", "python", "java", "csharp", "go"],
        ),
    },
)

cdktf_providers = module_extension(
    implementation = _cdktf_providers_impl,
    tag_classes = {
        "generate": _generate,
    },
)

def _tfc_config_impl(module_ctx):
    """Implementation of tfc_config module extension"""

    # Collect TFC configuration from modules
    tfc_config = {}

    for mod in module_ctx.modules:
        for config in mod.tags.configure:
            if config.organization:
                tfc_config["organization"] = config.organization
            if config.tfe_host:
                tfc_config["tfe_host"] = config.tfe_host
            if hasattr(config, "default_auto_apply"):
                tfc_config["default_auto_apply"] = config.default_auto_apply

    # Note: In a real implementation, we would store this config somewhere
    # that the rules can access it. For now, rules will need to pass
    # organization explicitly or use environment variables.
    # This is a placeholder for future enhancement.
    pass

# Tag class for TFC configuration
_tfc_configure = tag_class(
    attrs = {
        "organization": attr.string(
            doc = "Default Terraform Cloud organization",
            mandatory = False,
        ),
        "tfe_host": attr.string(
            doc = "Terraform Enterprise hostname (defaults to app.terraform.io)",
            mandatory = False,
        ),
        "default_auto_apply": attr.bool(
            doc = "Default auto-apply setting for workspaces",
            default = False,
        ),
    },
)

tfc_config = module_extension(
    implementation = _tfc_config_impl,
    tag_classes = {
        "configure": _tfc_configure,
    },
)

def _tf_tools_impl(module_ctx):
    """Implementation of tf_tools module extension"""

    # Default versions
    terraform_version = None
    tflint_version = None
    terraform_docs_version = None

    # Collect plugin configurations
    tflint_plugins = {}

    # Collect tool configuration from modules
    for mod in module_ctx.modules:
        # Check for versions.json configuration first
        for versions_config in mod.tags.from_versions_json:
            versions_data = parse_versions_json(module_ctx, versions_config.versions_file)

            # Get tool versions from versions.json
            if not terraform_version:
                terraform_version = get_tool_version(versions_data, "terraform")
            if not tflint_version:
                tflint_version = get_tool_version(versions_data, "tflint")
            if not terraform_docs_version:
                terraform_docs_version = get_tool_version(versions_data, "terraform-docs")

            # Get plugin versions from versions.json
            for plugin_name in ["aws", "azurerm", "google", "opa", "terraform"]:
                plugin_version = get_tflint_plugin_version(versions_data, plugin_name)
                if plugin_version:
                    tflint_plugins[plugin_name] = plugin_version

        # Override with explicit configuration
        for config in mod.tags.configure:
            if config.terraform_version:
                terraform_version = config.terraform_version
            if config.tflint_version:
                tflint_version = config.tflint_version
            if config.terraform_docs_version:
                terraform_docs_version = config.terraform_docs_version

        # Override with explicit tflint plugin configurations
        for plugin in mod.tags.tflint_plugin:
            plugin_name = plugin.name
            plugin_version = plugin.version
            tflint_plugins[plugin_name] = plugin_version

    # Create individual tool repositories
    download_terraform(
        name = "terraform_tool",
        version = terraform_version,
    )

    download_tflint(
        name = "tflint_tool",
        version = tflint_version,
    )

    download_terraform_docs(
        name = "terraform_docs_tool",
        version = terraform_docs_version,
    )

    # Create individual tflint plugin repositories
    for plugin_name, plugin_version in tflint_plugins.items():
        download_tflint_plugin(
            name = "tflint_plugin_{}".format(plugin_name),
            plugin_name = plugin_name,
            version = plugin_version,
        )

    # Create tool registry repository (just for aliases)
    tool_registry(
        name = "tf_tool_registry",
    )

    # Create tflint plugin registry with both downloaded and local plugins
    # Always create the registry (even if no downloaded plugins) to include built-in tf2 plugin
    # Determine the correct label for the tf2 plugin (handles both root and non-root module cases)
    # Check if we're the root module by looking at the first module
    is_root = module_ctx.modules[0].is_root if module_ctx.modules else False
    tf2_plugin_label = "@//go/tflint_ruleset:tflint-ruleset-tf2" if is_root else "@rules_tf2//go/tflint_ruleset:tflint-ruleset-tf2"

    tflint_plugin_registry(
        name = "tflint_plugin_registry",
        plugins = tflint_plugins.keys() if tflint_plugins else [],
        local_plugins = {
            "tf2": tf2_plugin_label,
        },
    )

# Tag class for tool configuration
_tools_configure = tag_class(
    attrs = {
        "terraform_version": attr.string(
            doc = "Terraform version to download (defaults to latest)",
            mandatory = False,
        ),
        "tflint_version": attr.string(
            doc = "TFLint version to download (defaults to latest)",
            mandatory = False,
        ),
        "terraform_docs_version": attr.string(
            doc = "terraform-docs version to download (defaults to latest)",
            mandatory = False,
        ),
    },
)

# Tag class for tflint plugin configuration
_tflint_plugin = tag_class(
    attrs = {
        "name": attr.string(
            doc = "Name of the tflint plugin (aws, azurerm, google, opa)",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "Version of the plugin to download",
            mandatory = True,
        ),
    },
)

# Tag class for configuring from versions.json
_versions_json_configure = tag_class(
    attrs = {
        "versions_file": attr.label(
            doc = "Path to versions.json file",
            mandatory = True,
            allow_single_file = [".json"],
        ),
    },
)

tf_tools = module_extension(
    implementation = _tf_tools_impl,
    tag_classes = {
        "configure": _tools_configure,
        "tflint_plugin": _tflint_plugin,
        "from_versions_json": _versions_json_configure,
    },
)
