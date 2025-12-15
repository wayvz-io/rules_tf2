"""Repository rule for downloading Terraform modules from Git repositories."""

def _parse_git_source(source):
    """Parse a git source URL into components.

    Supports:
    - GitHub shorthand: github.com/owner/repo
    - Full git URL: git::https://github.com/owner/repo.git

    Args:
        source: Git source string

    Returns:
        Tuple of (git_url, owner, repo)
    """
    # Handle git:: prefix (Terraform-style)
    if source.startswith("git::"):
        url = source[5:]  # Remove git:: prefix
        # Parse owner/repo from URL
        # https://github.com/owner/repo.git -> owner, repo
        parts = url.replace(".git", "").split("/")
        if len(parts) >= 2:
            repo = parts[-1]
            owner = parts[-2]
            return url, owner, repo
        fail("Cannot parse git URL: {}".format(source))

    # Handle GitHub shorthand: github.com/owner/repo
    if source.startswith("github.com/"):
        parts = source.split("/")
        if len(parts) >= 3:
            owner = parts[1]
            repo = parts[2]
            git_url = "https://{}.git".format(source)
            return git_url, owner, repo
        fail("Cannot parse GitHub shorthand: {}".format(source))

    fail("Unsupported git source format: {}. Use 'github.com/owner/repo' or 'git::https://...'".format(source))

def _is_commit_hash(ref):
    """Check if a ref is a commit hash (7-40 hex chars)."""
    if len(ref) < 7 or len(ref) > 40:
        return False
    for char in ref.elems():
        if char not in "0123456789abcdef":
            return False
    return True

def _module_git_repository_impl(repository_ctx):
    """Download a Terraform module from a Git repository.

    Supports cloning at a specific tag or commit hash.
    """
    source = repository_ctx.attr.source
    ref = repository_ctx.attr.ref
    subdirectory = repository_ctx.attr.subdirectory

    # Parse the source URL
    git_url, owner, repo = _parse_git_source(source)

    is_commit = _is_commit_hash(ref)

    if is_commit:
        # For commit hashes, we need to clone and checkout
        # First, do a shallow clone
        result = repository_ctx.execute(
            ["git", "clone", "--depth", "1", git_url, "."],
            quiet = False,
        )
        if result.return_code != 0:
            fail("Failed to clone {}: {}".format(git_url, result.stderr))

        # Fetch the specific commit
        result = repository_ctx.execute(
            ["git", "fetch", "--depth", "1", "origin", ref],
            quiet = False,
        )
        if result.return_code != 0:
            fail("Failed to fetch commit {}: {}".format(ref, result.stderr))

        # Checkout the commit
        result = repository_ctx.execute(
            ["git", "checkout", ref],
            quiet = False,
        )
        if result.return_code != 0:
            fail("Failed to checkout commit {}: {}".format(ref, result.stderr))
    else:
        # For tags, use --branch which works for both tags and branches
        result = repository_ctx.execute(
            ["git", "clone", "--depth", "1", "--branch", ref, git_url, "."],
            quiet = False,
        )
        if result.return_code != 0:
            fail("Failed to clone {} at {}: {}".format(git_url, ref, result.stderr))

    # If subdirectory is specified, we need to move those files to root
    if subdirectory:
        # List files in subdirectory
        result = repository_ctx.execute(["ls", "-la", subdirectory])
        if result.return_code != 0:
            fail("Subdirectory {} not found in {}".format(subdirectory, source))

        # Move subdirectory contents to a temp location, clean up, then move back
        result = repository_ctx.execute(["sh", "-c", """
            mv {subdir} _temp_subdir
            rm -rf .git .github .gitignore examples tests docs README.md || true
            mv _temp_subdir/* .
            rm -rf _temp_subdir
        """.format(subdir = subdirectory)])
        if result.return_code != 0:
            fail("Failed to extract subdirectory {}: {}".format(subdirectory, result.stderr))
    else:
        # Clean up git metadata and unnecessary files
        # - exports/ contains template files for copying (e.g., cloudposse context.tf)
        # - docs/ contains documentation assets
        repository_ctx.execute(["rm", "-rf", ".git", ".github", ".gitignore", "examples", "tests", "test", "exports", "docs"])

    # Find all .tf files for the module
    result = repository_ctx.execute(["find", ".", "-name", "*.tf", "-type", "f"])
    tf_files = []
    if result.return_code == 0 and result.stdout.strip():
        for f in result.stdout.strip().split("\n"):
            if f.startswith("./"):
                f = f[2:]
            # Exclude example and test directories
            if not f.startswith("examples/") and not f.startswith("tests/") and not f.startswith("test/"):
                tf_files.append(f)

    # Find README if present
    readme_files = []
    for readme in ["README.md", "readme.md", "README.MD"]:
        result = repository_ctx.execute(["test", "-f", readme])
        if result.return_code == 0:
            readme_files.append(readme)
            break

    all_files = tf_files + readme_files

    if not tf_files:
        fail("No .tf files found in module {} at ref {}".format(source, ref))

    # Create BUILD.bazel
    build_content = '''package(default_visibility = ["//visibility:public"])

filegroup(
    name = "module",
    srcs = glob(["**/*.tf"]) + glob(["**/*.tf.json"], allow_empty = True),
)

filegroup(
    name = "all_files",
    srcs = glob(["**/*"]),
)
'''

    repository_ctx.file("BUILD.bazel", build_content)

    # Create metadata file
    metadata = """{{
  "source": "{source}",
  "source_type": "git",
  "ref": "{ref}",
  "git_url": "{git_url}",
  "owner": "{owner}",
  "repo": "{repo}",
  "subdirectory": "{subdirectory}"
}}""".format(
        source = source,
        ref = ref,
        git_url = git_url,
        owner = owner,
        repo = repo,
        subdirectory = subdirectory or "",
    )
    repository_ctx.file("metadata.json", metadata)

module_git_repository = repository_rule(
    implementation = _module_git_repository_impl,
    attrs = {
        "source": attr.string(
            mandatory = True,
            doc = "Git source: 'github.com/owner/repo' or 'git::https://...'",
        ),
        "ref": attr.string(
            mandatory = True,
            doc = "Git ref: tag (e.g., 'v1.0.0') or short commit hash (e.g., 'abc1234')",
        ),
        "subdirectory": attr.string(
            doc = "Optional subdirectory within the repo containing the module",
            default = "",
        ),
    },
    doc = """Downloads a Terraform module from a Git repository.

    Supports both GitHub shorthand and full git URLs, with tags or commit hashes.

    Examples:
        # GitHub shorthand with tag
        module_git_repository(
            name = "tf_module_vpc_v5_0_0",
            source = "github.com/terraform-aws-modules/terraform-aws-vpc",
            ref = "v5.0.0",
        )

        # Full git URL with commit hash
        module_git_repository(
            name = "tf_module_example_abc1234",
            source = "git::https://github.com/example/terraform-module.git",
            ref = "abc1234",
        )

        # Module in subdirectory
        module_git_repository(
            name = "tf_module_submod_v1_0_0",
            source = "github.com/example/monorepo",
            ref = "v1.0.0",
            subdirectory = "modules/my-module",
        )
    """,
)
