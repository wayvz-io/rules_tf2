"""Alias and repository-name generation for external Terraform modules.

Extracted into its own loadable module so that both `extensions.bzl` and the
unit tests import the *same* implementation — previously the tests carried a
duplicate copy of this logic, which meant caller/integration bugs went
undetected.
"""

def sanitize_ref(ref):
    """Sanitize a git ref (tag or commit) for use in repository names.

    Args:
        ref: Git ref (tag or commit hash)

    Returns:
        Sanitized string suitable for repository names
    """
    sanitized = ref.replace(".", "_").replace("-", "_").replace("/", "_")
    if sanitized.startswith("v"):
        sanitized = sanitized[1:]
    return sanitized

def generate_module_alias(source, source_type, version):
    """Generate an alias name for a module.

    The `source` passed here is the hostname-stripped module path as it appears
    in versions.json, i.e. `namespace/name/provider` for both public and
    private registry modules (the registry hostname is tracked separately).

    Args:
        source: Module source string (hostname-stripped for registry/private)
        source_type: One of 'registry', 'git', or 'private'
        version: Module version or git ref

    Returns:
        Alias string (e.g., 'vpc_aws_5', 'my_module_aws_1', 'owner_repo_1_0_0')
    """
    major_version = version.split(".")[0] if "." in version else sanitize_ref(version)

    if source_type == "registry":
        # terraform-aws-modules/vpc/aws -> vpc_aws_5
        parts = source.split("/")
        if len(parts) == 3:
            name, provider = parts[1], parts[2]
            return "{}_{}_{}".format(name, provider, major_version)
        return "{}_{}".format(parts[-1], major_version)

    elif source_type == "private":
        # Private registry modules arrive hostname-stripped as
        # `namespace/name/provider` (same shape as public registry modules);
        # the hostname is tracked separately by the caller. Take the name and
        # provider so the alias stays unique per module + provider + version.
        parts = source.split("/")
        if len(parts) == 3:
            name, provider = parts[1], parts[2]
            return "{}_{}_{}".format(name.replace("-", "_"), provider, major_version)

        # Defensive: a hostname-qualified 4-part source (host/ns/name/provider).
        if len(parts) == 4:
            name, provider = parts[2], parts[3]
            return "{}_{}_{}".format(name.replace("-", "_"), provider, major_version)
        return "{}_{}".format(parts[-1].replace("-", "_"), major_version)

    elif source_type == "git":
        # github.com/owner/repo -> owner_repo_v1_0_0
        if source.startswith("github.com/"):
            parts = source.split("/")
            owner, repo = parts[1], parts[2]
            return "{}_{}_{}".format(
                owner.replace("-", "_"),
                repo.replace("-", "_").replace("terraform-", "").replace("terraform_", ""),
                sanitize_ref(version),
            )
        elif source.startswith("git::"):
            # git::https://github.com/owner/repo.git -> owner_repo_ref
            url = source[5:].replace(".git", "")
            parts = url.split("/")
            owner, repo = parts[-2], parts[-1]
            return "{}_{}_{}".format(
                owner.replace("-", "_"),
                repo.replace("-", "_").replace("terraform-", "").replace("terraform_", ""),
                sanitize_ref(version),
            )

    fail("Cannot generate alias for source: {} (type: {})".format(source, source_type))

def generate_repo_name(source, source_type, version):
    """Generate a repository name for a module download.

    Args:
        source: Module source string
        source_type: One of 'registry', 'git', or 'private'
        version: Module version or git ref

    Returns:
        Repository name string
    """
    alias = generate_module_alias(source, source_type, version)
    return "tf_module_{}".format(alias)
