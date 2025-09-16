"""Individual HTTP file repositories for Terraform provider binaries"""

def parse_terraform_lock_file(lock_content):
    """Parse terraform.lock.hcl to extract provider information.
    
    Returns a dict of provider info:
    {
        "hashicorp/aws:6.12.0": {
            "source": "hashicorp/aws",
            "version": "6.12.0",
            "hashes": {
                "zh": ["hash1", "hash2", ...],  # Package hashes (zh:)
                "h1": ["hash1", "hash2", ...],  # Binary hashes (h1:)
                "platforms": {
                    "linux_amd64": "h1:hash_value",
                    "darwin_arm64": "h1:hash_value",
                    # etc
                }
            }
        }
    }
    """
    providers = {}
    current_provider = None
    current_version = None
    current_h1_hashes = []
    current_zh_hashes = []
    in_provider_block = False
    
    for line in lock_content.split("\n"):
        line = line.strip()
        
        # Start of provider block
        if line.startswith('provider "'):
            # Extract provider source from line like: provider "registry.terraform.io/hashicorp/aws" {
            parts = line.split('"')
            if len(parts) >= 2:
                provider_url = parts[1]
                # Remove registry prefix
                provider_source = provider_url.replace("registry.terraform.io/", "")
                in_provider_block = True
                current_provider = provider_source
                current_h1_hashes = []
                current_zh_hashes = []
        
        # Version line
        elif in_provider_block and line.startswith('version'):
            # Extract version from line like: version = "6.12.0"
            parts = line.split('"')
            if len(parts) >= 2:
                current_version = parts[1]
        
        # Hash line
        elif in_provider_block and line.startswith('"'):
            hash_line = line.strip('",').strip('"')
            if hash_line.startswith('h1:'):
                # Binary hash - platform specific
                current_h1_hashes.append(hash_line[3:])
            elif hash_line.startswith('zh:'):
                # Package hash - same across platforms
                current_zh_hashes.append(hash_line[3:])
        
        # End of provider block
        elif in_provider_block and line == "}":
            if current_provider and current_version:
                key = "{}:{}".format(current_provider, current_version)
                
                # Map h1 hashes to platforms (order is deterministic from terraform providers lock)
                # The order is: darwin_amd64, darwin_arm64, linux_amd64, linux_arm64, windows_amd64
                platforms = {}
                platform_order = [
                    "darwin_amd64", "darwin_arm64", 
                    "linux_amd64", "linux_arm64", 
                    "windows_amd64"
                ]
                
                # h1 hashes are in platform order
                for i, platform in enumerate(platform_order):
                    if i < len(current_h1_hashes):
                        platforms[platform] = current_h1_hashes[i]
                
                providers[key] = {
                    "source": current_provider,
                    "version": current_version,
                    "hashes": {
                        "h1": current_h1_hashes,
                        "zh": current_zh_hashes,
                        "platforms": platforms,
                    },
                }
            in_provider_block = False
            current_provider = None
            current_version = None
            current_h1_hashes = []
            current_zh_hashes = []
    
    return providers

def get_provider_download_info(provider_source, version, os_name, arch):
    """Get download URL and expected filename for a provider.
    
    Args:
        provider_source: e.g., "hashicorp/aws"
        version: e.g., "6.12.0"
        os_name: "linux", "darwin", "windows"
        arch: "amd64", "arm64"
    
    Returns:
        (url, filename) tuple
    """
    namespace, name = provider_source.split("/")
    
    # Terraform provider binary naming convention
    filename = "terraform-provider-{}_{}_{}_{}".format(name, version, os_name, arch)
    if os_name == "windows":
        filename += ".exe"
    
    # Most providers use releases.hashicorp.com or GitHub releases
    if namespace == "hashicorp":
        # HashiCorp providers use releases.hashicorp.com
        url = "https://releases.hashicorp.com/terraform-provider-{}/{}/terraform-provider-{}_{}_{}_{}.zip".format(
            name, version, name, version, os_name, arch
        )
    else:
        # For other providers, we'd need to query the registry API
        # For now, use the registry download URL format
        url = "https://registry.terraform.io/v1/providers/{}/{}/{}/download/{}/{}".format(
            namespace, name, version, os_name, arch
        )
    
    return url, filename

def create_provider_http_file_repositories(module_ctx, providers_info):
    """Create individual http_file repositories for each provider binary.
    
    Args:
        module_ctx: Module context
        providers_info: Dict from parse_terraform_lock_file
    
    Returns:
        Dict of repository names created
    """
    repositories_created = {}
    
    # Platforms to download for
    platforms = [
        ("linux", "amd64"),
        ("linux", "arm64"),
        ("darwin", "amd64"),
        ("darwin", "arm64"),
        ("windows", "amd64"),
    ]
    
    for provider_key, provider_data in providers_info.items():
        source = provider_data["source"]
        version = provider_data["version"]
        namespace, name = source.split("/")
        
        # Find the zh: hash (package hash) which should be consistent across platforms
        zh_hash = None
        for hash_val in provider_data["hashes"]:
            if hash_val.startswith("zh:"):
                zh_hash = hash_val[3:]  # Remove "zh:" prefix
                break
        
        # Create a repository for each platform
        for os_name, arch in platforms:
            url, filename = get_provider_download_info(source, version, os_name, arch)
            
            # Repository name format: tf_provider_{name}_{version}_{os}_{arch}
            repo_name = "tf_provider_{}_{}_{}_{}_{}".format(
                name,
                version.replace(".", "_"),
                os_name,
                arch
            )
            
            # Create http_file repository
            # Note: In actual implementation, this would be done via repository rules
            repositories_created[repo_name] = {
                "url": url,
                "sha256": zh_hash,  # Use package hash for now
                "filename": filename,
                "provider": source,
                "version": version,
                "os": os_name,
                "arch": arch,
            }
    
    return repositories_created