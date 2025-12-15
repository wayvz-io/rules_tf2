"""HCL parsing utilities for Terraform lock files.

This module provides Starlark functions to parse .terraform.lock.hcl files
and extract provider hash information.
"""

def parse_lock_hcl(content):
    """Parse .terraform.lock.hcl content and extract hashes.

    This is a Starlark implementation of HCL hash parsing.
    We extract h1: and zh: hashes from the hashes = [...] block.

    Args:
        content: String content of .terraform.lock.hcl file

    Returns:
        Dict with "h1" and "zh" keys, each containing a list of hash strings
        (without the h1:/zh: prefixes)
    """
    h1_hashes = []
    zh_hashes = []

    in_hashes_block = False
    lines = content.split("\n")

    for line in lines:
        stripped = line.strip()

        # Detect start of hashes block
        if stripped.startswith("hashes = ["):
            in_hashes_block = True
            continue

        if in_hashes_block:
            # Detect end of hashes block
            if "]" in stripped:
                in_hashes_block = False
                continue

            # Extract hash value from line like: "h1:abc123...",
            if '"' in stripped:
                # Find the hash value between quotes
                parts = stripped.split('"')
                if len(parts) >= 2:
                    hash_val = parts[1]
                    if hash_val.startswith("h1:"):
                        h1_hashes.append(hash_val[3:])  # Remove "h1:" prefix
                    elif hash_val.startswith("zh:"):
                        zh_hashes.append(hash_val[3:])  # Remove "zh:" prefix

    return {
        "h1": h1_hashes,
        "zh": zh_hashes,
    }

def sanitize_provider_key(provider_key):
    """Convert provider:version key to a valid Bazel repository name.

    Args:
        provider_key: String like "hashicorp/aws:6.26.0"

    Returns:
        String like "hashicorp_aws_6_26_0"
    """
    return provider_key.replace("/", "_").replace(":", "_").replace(".", "_")

def compute_provider_delta(versions_data, cached_hashes):
    """Compute which providers need to be added, removed, or are unchanged.

    Args:
        versions_data: Dict from versions.json with "providers" key
        cached_hashes: Dict of provider_key -> hash_data from module_ctx.facts

    Returns:
        Dict with "missing", "obsolete", and "unchanged" keys, each containing
        a list of provider:version strings
    """
    required = {}
    providers = versions_data.get("providers", {})
    for provider, versions in providers.items():
        for version in versions:
            key = "{}:{}".format(provider, version)
            required[key] = True

    cached = {}
    for key in cached_hashes.keys():
        cached[key] = True

    missing = []
    for key in required.keys():
        if key not in cached:
            missing.append(key)

    obsolete = []
    for key in cached.keys():
        if key not in required:
            obsolete.append(key)

    unchanged = []
    for key in required.keys():
        if key in cached:
            unchanged.append(key)

    return {
        "missing": sorted(missing),
        "obsolete": sorted(obsolete),
        "unchanged": sorted(unchanged),
    }
