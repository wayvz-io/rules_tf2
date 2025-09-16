"""Module extensions for tf2"""

load("//tf/core/repositories:terraform_providers.bzl", "terraform_providers", "terraform_providers_from_mirror_declarations")
load("//tf/core/cdktf:cdktf_repository_gazelle.bzl", "cdktf_bindings_repository_gazelle")

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
        if mod.name == "":  # Root module
            for download in mod.tags.download:
                # Require explicit paths - no defaults
                if not download.versions_file:
                    fail("versions_file must be specified in tf_providers.download()")
                if not download.lock_file:
                    fail("lock_file must be specified in tf_providers.download()")
                
                versions_path = download.versions_file
                lock_path = download.lock_file
                
                # Read versions from the specified file
                versions_file = Label("@@//:" + versions_path)
                versions_content = module_ctx.read(versions_file)
                versions_data = json.decode(versions_content)
                
                # Read and parse the lock file
                lock_file = Label("@@//:" + lock_path)
                lock_file_content = module_ctx.read(lock_file)
                
                # Parse lock file to get hashes
                lock_file_parsed = _parse_lock_file_to_json(lock_file_content)
                
                # Process for main providers
                if lock_file_parsed:
                    for provider_name, lock_data in lock_file_parsed.items():
                        version = lock_data.get("version", "")
                        if version:
                            key = "{}:{}".format(provider_name, version)
                            main_hashes[key] = lock_data.get("hashes", [])
                            
                            if provider_name not in main_providers:
                                main_providers[provider_name] = []
                            if version not in main_providers[provider_name]:
                                main_providers[provider_name].append(version)
                            
                            short_name = provider_name.split("/")[-1]
                            major_version = version.split(".")[0]
                            alias_name = "{}_{}".format(short_name, major_version)
                            main_aliases[alias_name] = [provider_name, version]
                
                elif "providers" in versions_data:
                    main_providers = versions_data["providers"]
                    for provider, versions in main_providers.items():
                        provider_name = provider.split("/")[-1]
                        for version in versions:
                            major_version = version.split(".")[0]
                            alias_name = "{}_{}".format(provider_name, major_version)
                            main_aliases[alias_name] = [provider, version]
        
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
                
                lock_file = Label("@rules_tf2//:" + lock_path)
                lock_file_content = module_ctx.read(lock_file)
                
                lock_file_parsed = _parse_lock_file_to_json(lock_file_content)
                
                # Process for test providers
                if lock_file_parsed:
                    for provider_name, lock_data in lock_file_parsed.items():
                        version = lock_data.get("version", "")
                        if version:
                            key = "{}:{}".format(provider_name, version)
                            test_hashes[key] = lock_data.get("hashes", [])
                            
                            if provider_name not in test_providers:
                                test_providers[provider_name] = []
                            if version not in test_providers[provider_name]:
                                test_providers[provider_name].append(version)
                            
                            short_name = provider_name.split("/")[-1]
                            major_version = version.split(".")[0]
                            alias_name = "{}_{}".format(short_name, major_version)
                            test_aliases[alias_name] = [provider_name, version]
                
                elif "providers" in versions_data:
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
    
    # Create single consolidated registry
    if combined_providers:
        terraform_providers(
            name = "tf_provider_registry",
            providers = combined_providers,
            aliases = combined_aliases,
            provider_hashes = combined_hashes,
        )
        
        # Create alias for backward compatibility
        terraform_providers(
            name = "tf_providers_test",
            providers = combined_providers,
            aliases = combined_aliases,
            provider_hashes = combined_hashes,
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
            doc = "Path to terraform.lock.hcl file",
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
            major_version = version.split(".")[0]    # e.g., "6" from "6.2.0"
            
            # Create repository name like "cdktf_aws_6"
            repo_name = "cdktf_{}_{}_go".format(provider_name, major_version)
            
            # Create the CDKTF bindings repository with proper gazelle integration
            cdktf_bindings_repository_gazelle(
                name = repo_name,
                provider_name = provider_name,
                provider_source = provider,
                provider_version = version,
            )
            
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