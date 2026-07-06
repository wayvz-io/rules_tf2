"""Module extensions for tf2"""

load("@rules_oci//oci:pull.bzl", "oci_pull")
load("//tf2/modules/download:module_git_repository.bzl", "git_module_archive_url", "module_git_repository")
load("//tf2/modules/download:module_registry_repository.bzl", "module_registry_repository", "resolve_registry_download")
load("//tf2/modules/registry:alias.bzl", "generate_module_alias", "generate_repo_name")
load("//tf2/modules/repository:terraform_modules.bzl", "terraform_modules")
load("//tf2/providers/download:provider_download_repository.bzl", "provider_download_repository")
load("//tf2/providers/repository:hcl_parser.bzl", "parse_lock_hcl", "sanitize_provider_key")
load("//tf2/providers/repository:terraform_providers.bzl", "terraform_providers")
load("//tf2/providers/repository:versions.bzl", "get_tflint_plugin_version", "get_tool_version", "parse_versions_json")
load("//tf2/internal:hermetic_fetch.bzl", "facts_key", "resolve_per_file_hashes", "resolve_platform_hashes", "resolve_single_hash", "tofu_hash")
load("//tf2/tools/download:opa.bzl", "download_opa", "opa_fetch_spec")
load("//tf2/tools/download:registry.bzl", "tflint_plugin_registry", "tool_registry")
load("//tf2/tools/download:sentinel.bzl", "download_sentinel", "sentinel_fetch_spec")
load("//tf2/tools/download:terraform.bzl", "download_terraform", "terraform_fetch_spec")
load("//tf2/tools/download:terraform_docs.bzl", "download_terraform_docs", "terraform_docs_fetch_spec")
load("//tf2/tools/download:tflint.bzl", "download_tflint", "download_tflint_plugin", "tflint_fetch_spec", "tflint_plugin_fetch_spec")

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

# Terraform download configuration
_TERRAFORM_BASE_URL = "https://releases.hashicorp.com/terraform"
_DEFAULT_TERRAFORM_VERSION = "1.14.2"

# Platforms to generate hashes for
_TARGET_PLATFORMS = [
    "linux_amd64",
    "linux_arm64",
    "darwin_amd64",
    "darwin_arm64",
    "windows_amd64",
]

def _get_module_ctx_platform(module_ctx):
    """Determine the current platform from module_ctx.os.

    Args:
        module_ctx: Module extension context

    Returns:
        String platform identifier (e.g., "linux_amd64")
    """
    os_name = module_ctx.os.name.lower()
    arch = module_ctx.os.arch.lower()

    # Normalize OS name
    if os_name.startswith("mac") or os_name == "darwin":
        os_key = "darwin"
    elif os_name.startswith("linux"):
        os_key = "linux"
    elif os_name.startswith("windows"):
        os_key = "windows"
    else:
        fail("Unsupported OS: {}".format(os_name))

    # Normalize architecture
    if arch in ["x86_64", "amd64"]:
        arch_key = "amd64"
    elif arch in ["aarch64", "arm64"]:
        arch_key = "arm64"
    else:
        fail("Unsupported architecture: {}".format(arch))

    return "{}_{}".format(os_key, arch_key)

def _generate_provider_hashes_inline(module_ctx, provider_source, version, terraform_version):
    """Generate provider hashes using terraform providers lock inline.

    This function runs terraform directly within the module extension context,
    avoiding the need for a separate repository rule (which can't be read from
    within the same extension evaluation).

    Args:
        module_ctx: Module extension context
        provider_source: Provider source (e.g., "hashicorp/aws")
        version: Provider version (e.g., "6.26.0")
        terraform_version: Terraform version to use

    Returns:
        Dict with "h1" and "zh" keys containing hash lists
    """

    # Create a unique work directory for this provider
    sanitized_key = sanitize_provider_key("{}:{}".format(provider_source, version))
    work_dir = module_ctx.path("_tf_hash_gen_{}".format(sanitized_key))

    # Get platform info
    platform = _get_module_ctx_platform(module_ctx)

    # Download terraform
    terraform_url = "{base}/{version}/terraform_{version}_{platform}.zip".format(
        base = _TERRAFORM_BASE_URL,
        version = terraform_version,
        platform = platform,
    )

    terraform_dir = module_ctx.path("_terraform_bin_{}".format(terraform_version.replace(".", "_")))

    module_ctx.report_progress("Downloading terraform {} for hash generation".format(terraform_version))
    module_ctx.download_and_extract(
        url = terraform_url,
        output = terraform_dir,
        type = "zip",
    )

    terraform_path = terraform_dir.get_child("terraform")

    # Make terraform executable
    module_ctx.execute(["chmod", "+x", str(terraform_path)])

    # Create terraform configuration files
    provider_name = provider_source.split("/")[-1]

    main_tf = """terraform {
  required_version = ">= 1.0"
}
"""

    versions_tf = """terraform {{
  required_providers {{
    {name} = {{
      source  = "{source}"
      version = "= {version}"
    }}
  }}
}}
""".format(name = provider_name, source = provider_source, version = version)

    # Create work directory and files
    module_ctx.file(work_dir.get_child("main.tf"), main_tf)
    module_ctx.file(work_dir.get_child("versions.tf"), versions_tf)

    # Run terraform init
    module_ctx.report_progress("Running terraform init for {}:{}".format(provider_source, version))
    init_result = module_ctx.execute(
        [str(terraform_path), "init", "-backend=false"],
        working_directory = str(work_dir),
        timeout = 600,
        environment = {
            "TF_LOG": "",
            "TF_PLUGIN_CACHE_DIR": "",
        },
    )

    if init_result.return_code != 0:
        fail("terraform init failed for {}:{}\nstdout: {}\nstderr: {}".format(
            provider_source,
            version,
            init_result.stdout,
            init_result.stderr,
        ))

    # Build platform arguments for terraform providers lock
    platform_args = []
    for p in _TARGET_PLATFORMS:
        platform_args.append("-platform=" + p)

    # Run terraform providers lock
    module_ctx.report_progress("Generating hashes for {}:{} (this may take a while)".format(provider_source, version))
    lock_cmd = [str(terraform_path), "providers", "lock"] + platform_args
    lock_result = module_ctx.execute(
        lock_cmd,
        working_directory = str(work_dir),
        timeout = 1800,  # 30 minutes for large providers
        environment = {
            "TF_LOG": "",
        },
    )

    if lock_result.return_code != 0:
        fail("terraform providers lock failed for {}:{}\nstdout: {}\nstderr: {}".format(
            provider_source,
            version,
            lock_result.stdout,
            lock_result.stderr,
        ))

    # Read and parse the lock file
    lock_file_path = work_dir.get_child(".terraform.lock.hcl")
    lock_content = module_ctx.read(lock_file_path)

    return parse_lock_hcl(lock_content)

def _tf_providers_impl(module_ctx):
    """Implementation of tf_providers module extension.

    This extension:
    1. Reads versions.json to get required providers
    2. Uses module_ctx.facts as the source of cached hashes
    3. Computes delta to find missing providers
    4. Auto-generates hashes for missing providers using terraform providers lock
    5. Creates provider download repositories
    6. Returns extension_metadata with updated facts
    """

    # Note: module_ctx.facts requires Bazel 8.5+ and only supports key lookups, not iteration.
    # We'll look up facts for specific provider keys after we know which providers we need.
    has_facts = hasattr(module_ctx, "facts")

    main_providers = {}
    main_aliases = {}
    test_providers = {}
    test_aliases = {}
    terraform_version = None

    # Process provider downloads from modules
    for mod in module_ctx.modules:
        if mod.is_root:  # Root module only
            for download in mod.tags.download:
                # Require explicit versions_file path
                if not download.versions_file:
                    fail("versions_file must be specified in tf_providers.download()")

                versions_path = download.versions_file

                # Read versions from the specified file
                versions_file = Label("@@//:" + versions_path)
                versions_content = module_ctx.read(versions_file)
                versions_data = json.decode(versions_content)

                # Get terraform version for hash generation
                if not terraform_version and "tools" in versions_data:
                    terraform_version = versions_data["tools"].get("terraform")

                # Process providers from versions.json
                if "providers" in versions_data:
                    main_providers = versions_data["providers"]
                    for provider, versions in main_providers.items():
                        provider_name = provider.split("/")[-1]
                        for version in versions:
                            major_version = version.split(".")[0]
                            alias_name = "{}_{}".format(provider_name, major_version)
                            main_aliases[alias_name] = [provider, version]

        elif mod.name == "tf2":  # tf2 module (when rules_tf2 is a dependency)
            for download in mod.tags.download:
                if not download.versions_file:
                    fail("versions_file must be specified in tf_providers.download() for tf2 module")

                versions_path = download.versions_file

                # Read from tf2 module
                versions_file = Label("@rules_tf2//:" + versions_path)
                versions_content = module_ctx.read(versions_file)
                versions_data = json.decode(versions_content)

                # Get terraform version for hash generation
                if not terraform_version and "tools" in versions_data:
                    terraform_version = versions_data["tools"].get("terraform")

                # Process providers from versions.json
                if "providers" in versions_data:
                    test_providers = versions_data["providers"]
                    for provider, versions in test_providers.items():
                        provider_name = provider.split("/")[-1]
                        for version in versions:
                            major_version = version.split(".")[0]
                            alias_name = "{}_{}".format(provider_name, major_version)
                            test_aliases[alias_name] = [provider, version]

    # Consolidate both provider sets into a single registry
    combined_providers = {}
    combined_aliases = {}

    # Start with main providers
    if main_providers:
        combined_providers.update(main_providers)
        combined_aliases.update(main_aliases)

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

    # Build list of all required provider keys
    required_keys = []
    for provider_source, versions in combined_providers.items():
        for version in versions:
            required_keys.append("{}:{}".format(provider_source, version))

    # Look up cached hashes from facts and generate missing ones
    # module_ctx.facts only supports key lookups, not iteration
    new_hashes = {}
    combined_hashes = {}

    for provider_key in required_keys:
        # Try to get cached hashes from facts
        cached_hash_data = None
        if has_facts:
            # Facts lookup returns None if key doesn't exist
            cached_hash_data = module_ctx.facts.get(provider_key, None)

        if cached_hash_data:
            # Use cached hashes
            new_hashes[provider_key] = cached_hash_data
        else:
            # Generate hashes for this provider
            parts = provider_key.split(":")
            provider_source, version = parts[0], parts[1]

            hashes = _generate_provider_hashes_inline(
                module_ctx,
                provider_source,
                version,
                terraform_version or "1.14.2",
            )
            new_hashes[provider_key] = hashes

        # Convert to format expected by provider_download_repository
        hash_data = new_hashes[provider_key]
        all_hashes = []
        if type(hash_data) == "dict":
            for hash_type in ["h1", "zh"]:
                if hash_type in hash_data:
                    for hash_val in hash_data[hash_type]:
                        all_hashes.append("{}:{}".format(hash_type, hash_val))
        combined_hashes[provider_key] = all_hashes

    # Create individual provider download repositories for each provider/version/platform
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
        terraform_providers(
            name = "tf_provider_registry",
            providers = combined_providers,
            aliases = combined_aliases,
            provider_hashes = combined_hashes,
            provider_repositories_json = json.encode(created_repositories),
        )
    else:
        # No providers found (likely because we're a dependency, not root)
        terraform_providers(
            name = "tf_provider_registry",
            providers = {},
            aliases = {},
            provider_hashes = {},
            provider_repositories_json = "{}",
        )

    # Return extension metadata with updated facts
    # Facts are persisted in MODULE.bazel.lock and used on subsequent builds
    return module_ctx.extension_metadata(
        reproducible = True,
        facts = new_hashes,
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
            doc = "DEPRECATED: No longer used. Hashes are stored in MODULE.bazel.lock facts.",
            mandatory = False,
            default = "",
        ),
    },
)

tf_providers = module_extension(
    implementation = _tf_providers_impl,
    tag_classes = {
        "download": _download,
    },
)

def _lock_tool_hashes(module_ctx, facts, new_facts, name, spec, current):
    """Resolve and lock a tool's checksums, returning the current platform's sha256.

    Prefers the publisher's checksums file (locking every platform for a
    portable lockfile); trust-on-first-use fills any platform the file omits.
    The merged record is written back into `new_facts` under a stable key.
    """
    key = facts_key("tool", name, spec.version)
    per_file_sums = getattr(spec, "per_file_sums", None)
    if per_file_sums:
        record, _cached = resolve_per_file_hashes(module_ctx, facts, key, per_file_sums)
    else:
        record, _cached = resolve_platform_hashes(module_ctx, facts, key, spec.sums_url, spec.platform_files)

    hashes = dict(record["sha256"])
    source = record["source"] if current in hashes else "tofu"
    if current not in hashes:
        # Publisher checksum unavailable for this platform; trust-on-first-use.
        hashes[current] = tofu_hash(module_ctx, key + ":" + current, spec.artifact_url)
    new_facts[key] = {"sha256": hashes, "source": source}
    return hashes.get(current, "")

def _tf_tools_impl(module_ctx):
    """Implementation of tf_tools module extension"""

    # Default versions
    terraform_version = None
    tflint_version = None
    terraform_docs_version = None
    sentinel_version = None
    opa_version = None

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
            if not sentinel_version:
                sentinel_version = get_tool_version(versions_data, "sentinel")
            if not opa_version:
                opa_version = get_tool_version(versions_data, "opa")

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

    # Resolve and lock each tool's checksum (publisher SHA256SUMS -> trust-on-
    # first-use), caching the results in MODULE.bazel.lock via facts, then pass
    # the current platform's sha256 to each download repo for verification.
    has_facts = hasattr(module_ctx, "facts")
    facts = module_ctx.facts if has_facts else None
    new_facts = {}
    current = _get_module_ctx_platform(module_ctx)

    # Create individual tool repositories
    terraform_spec = terraform_fetch_spec(terraform_version, current)
    download_terraform(
        name = "terraform_tool",
        version = terraform_spec.version,
        sha256 = _lock_tool_hashes(module_ctx, facts, new_facts, "terraform", terraform_spec, current),
    )

    tflint_spec = tflint_fetch_spec(tflint_version, current)
    download_tflint(
        name = "tflint_tool",
        version = tflint_spec.version,
        sha256 = _lock_tool_hashes(module_ctx, facts, new_facts, "tflint", tflint_spec, current),
    )

    terraform_docs_spec = terraform_docs_fetch_spec(terraform_docs_version, current)
    download_terraform_docs(
        name = "terraform_docs_tool",
        version = terraform_docs_spec.version,
        sha256 = _lock_tool_hashes(module_ctx, facts, new_facts, "terraform-docs", terraform_docs_spec, current),
    )

    sentinel_spec = sentinel_fetch_spec(sentinel_version, current)
    download_sentinel(
        name = "sentinel_tool",
        version = sentinel_spec.version,
        sha256 = _lock_tool_hashes(module_ctx, facts, new_facts, "sentinel", sentinel_spec, current),
    )

    opa_spec = opa_fetch_spec(opa_version, current)
    download_opa(
        name = "opa_tool",
        version = opa_spec.version,
        sha256 = _lock_tool_hashes(module_ctx, facts, new_facts, "opa", opa_spec, current),
    )

    # Create individual tflint plugin repositories
    for plugin_name, plugin_version in tflint_plugins.items():
        plugin_spec = tflint_plugin_fetch_spec(plugin_name, plugin_version, current)
        download_tflint_plugin(
            name = "tflint_plugin_{}".format(plugin_name),
            plugin_name = plugin_name,
            version = plugin_version,
            sha256 = _lock_tool_hashes(module_ctx, facts, new_facts, "tflint-plugin-" + plugin_name, plugin_spec, current),
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

    # Tool checksums are pinned in facts (MODULE.bazel.lock); the extension is
    # reproducible given those inputs.
    return module_ctx.extension_metadata(
        reproducible = True,
        facts = new_facts,
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

# =============================================================================
# tf_modules extension - External Terraform module management
# =============================================================================

def _tf_modules_impl(module_ctx):
    """Implementation of tf_modules module extension.

    This extension:
    1. Reads versions.json to get required external modules
    2. Creates module download repositories (git or registry)
    3. Creates the tf_module_registry with aliases to downloaded modules
    """
    modules_config = {}  # source -> [versions]
    aliases = {}  # alias -> [source, source_type, version]
    module_repositories = {}  # alias -> {source, source_type, version, repo_name}

    # Checksums are resolved (trust-on-first-use) and cached in facts, so each
    # module archive is verified on download.
    has_facts = hasattr(module_ctx, "facts")
    facts = module_ctx.facts if has_facts else None
    new_facts = {}

    # Process module downloads from modules
    for mod in module_ctx.modules:
        if mod.is_root:  # Root module only
            for download in mod.tags.download:
                # Require explicit versions_file path
                if not download.versions_file:
                    fail("versions_file must be specified in tf_modules.download()")

                versions_path = download.versions_file

                # Read versions from the specified file
                versions_file = Label("@@//:" + versions_path)
                versions_content = module_ctx.read(versions_file)
                versions_data = json.decode(versions_content)

                # Process modules from versions.json
                if "modules" in versions_data:
                    modules_data = versions_data["modules"]

                    # Process registry modules - namespaced by hostname
                    # Schema: registry: { "hostname": { "ns/name/provider": ["versions"] } }
                    for hostname, host_modules in modules_data.get("registry", {}).items():
                        is_private = hostname != "registry.terraform.io"

                        for source, versions in host_modules.items():
                            # For private registries, prepend hostname to source
                            full_source = "{}/{}".format(hostname, source) if is_private else source
                            source_type = "private" if is_private else "registry"

                            if full_source not in modules_config:
                                modules_config[full_source] = []

                            for version in versions:
                                if version not in modules_config[full_source]:
                                    modules_config[full_source].append(version)

                                alias = generate_module_alias(source, source_type, version)
                                repo_name = generate_repo_name(source, source_type, version)

                                aliases[alias] = [full_source, source_type, version]
                                module_repositories[alias] = {
                                    "source": full_source,
                                    "source_type": source_type,
                                    "version": version,
                                    "repo_name": repo_name,
                                    "registry_host": hostname,
                                }

                                # Pre-resolve the archive URL so we can hash it,
                                # then verify on download in the repo rule.
                                reg_url, reg_type = resolve_registry_download(module_ctx, full_source, version, source_type, hostname)
                                reg_headers = {}
                                if source_type == "private":
                                    reg_token = module_ctx.os.environ.get("TFE_TOKEN", "")
                                    if reg_token:
                                        reg_headers = {"Authorization": "Bearer " + reg_token}
                                reg_key = facts_key("module", "registry", full_source, version)
                                reg_record, _reg_cached = resolve_single_hash(module_ctx, facts, reg_key, reg_url, headers = reg_headers)
                                new_facts[reg_key] = reg_record

                                # Create registry download repository
                                module_registry_repository(
                                    name = repo_name,
                                    source = full_source,
                                    version = version,
                                    source_type = source_type,
                                    registry_host = hostname,
                                    resolved_url = reg_url,
                                    archive_type = reg_type,
                                    sha256 = reg_record["sha256"],
                                )

                    # Process git modules
                    for source, refs in modules_data.get("git", {}).items():
                        if source not in modules_config:
                            modules_config[source] = []
                        for ref in refs:
                            if ref not in modules_config[source]:
                                modules_config[source].append(ref)

                            alias = generate_module_alias(source, "git", ref)
                            repo_name = generate_repo_name(source, "git", ref)

                            aliases[alias] = [source, "git", ref]
                            module_repositories[alias] = {
                                "source": source,
                                "source_type": "git",
                                "version": ref,
                                "repo_name": repo_name,
                            }

                            # GitHub sources fetch a checksum-verified tarball;
                            # other git hosts fall back to cloning (no sha).
                            archive_url, archive_type = git_module_archive_url(source, ref)
                            git_sha = ""
                            if archive_url:
                                git_key = facts_key("module", "git", source, ref)
                                git_record, _git_cached = resolve_single_hash(module_ctx, facts, git_key, archive_url)
                                new_facts[git_key] = git_record
                                git_sha = git_record["sha256"]

                            # Create git download repository
                            module_git_repository(
                                name = repo_name,
                                source = source,
                                ref = ref,
                                archive_url = archive_url or "",
                                archive_type = archive_type or "",
                                sha256 = git_sha,
                            )

    # Create the module registry
    terraform_modules(
        name = "tf_module_registry",
        modules = modules_config,
        aliases = aliases,
        module_repositories_json = json.encode(module_repositories),
    )

    # Module checksums are pinned in facts (MODULE.bazel.lock); the extension is
    # reproducible given those inputs.
    return module_ctx.extension_metadata(
        reproducible = True,
        facts = new_facts,
    )

# Tag class for module download configuration
_module_download = tag_class(
    attrs = {
        "versions_file": attr.string(
            doc = "Path to versions.json file containing modules configuration",
            mandatory = True,
        ),
    },
)

tf_modules = module_extension(
    implementation = _tf_modules_impl,
    tag_classes = {
        "download": _module_download,
    },
)

# =============================================================================
# tf_agent_base extension - TFC agent base image management
# =============================================================================

def _tf_agent_base_impl(module_ctx):
    """Implementation of tf_agent_base module extension.

    Reads the tfc-agent version from versions.json and pulls the base image
    using rules_oci with dynamic versioning.

    This extension:
    1. Reads versions.json to get the tfc-agent version
    2. Calls oci_pull with that version to create the base image repositories
    3. Creates repos: tfc_agent_base, tfc_agent_base_linux_amd64, tfc_agent_base_linux_arm64
    """
    for mod in module_ctx.modules:
        for config in mod.tags.from_versions_json:
            # Read versions.json to get tfc-agent version
            versions_path = module_ctx.path(config.versions_file)
            versions_content = module_ctx.read(versions_path)
            versions = json.decode(versions_content)

            agent_version = versions.get("tools", {}).get("tfc-agent", "1.17.0")

            # Call oci_pull with the dynamic version
            # This creates:
            #   - tfc_agent_base (alias that selects platform)
            #   - tfc_agent_base_linux_amd64
            #   - tfc_agent_base_linux_arm64
            oci_pull(
                name = "tfc_agent_base",
                image = "index.docker.io/hashicorp/tfc-agent",
                platforms = [
                    "linux/amd64",
                    "linux/arm64",
                ],
                tag = agent_version,
                reproducible = False,  # Tag-based pulls aren't reproducible
                is_bzlmod = True,
            )

            # Only process the first config
            return

    # Return extension metadata
    return module_ctx.extension_metadata(
        reproducible = False,
    )

# Tag class for agent base image configuration
_agent_versions_json = tag_class(
    attrs = {
        "versions_file": attr.label(
            doc = "Path to versions.json file",
            mandatory = True,
            allow_single_file = [".json"],
        ),
    },
)

tf_agent_base = module_extension(
    implementation = _tf_agent_base_impl,
    tag_classes = {
        "from_versions_json": _agent_versions_json,
    },
)
