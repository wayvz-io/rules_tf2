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

def git_module_archive_url(source, ref):
    """Return (archive_url, archive_type) for a GitHub-hosted git module.

    GitHub serves a tarball at `https://github.com/<owner>/<repo>/archive/<ref>.tar.gz`,
    which lets us fetch the module with checksum verification instead of an
    unverifiable `git clone`. Non-GitHub sources return (None, None), and the
    repo rule falls back to cloning.
    """
    git_url, owner, repo = _parse_git_source(source)
    if "github.com" not in git_url:
        return None, None
    return "https://github.com/{}/{}/archive/{}.tar.gz".format(owner, repo, ref), "tar.gz"

def _flatten_single_dir(repository_ctx):
    """Flatten a lone top-level directory to the repo root.

    Archive tarballs (e.g. GitHub's) wrap everything in a `<repo>-<ref>/`
    directory; moving its contents up makes the layout match a `git clone .`.
    """
    result = repository_ctx.execute(["sh", "-c", "ls -d */ 2>/dev/null || true"])
    dirs = []
    for line in result.stdout.split("\n"):
        line = line.strip()
        if line.endswith("/") and line[:-1] not in [".", ".."]:
            dirs.append(line[:-1])

    result = repository_ctx.execute(["find", ".", "-maxdepth", "1", "-name", "*.tf"])
    has_tf_at_root = result.return_code == 0 and result.stdout.strip()

    if len(dirs) == 1 and not has_tf_at_root:
        repository_ctx.execute(["sh", "-c", """
            mv {subdir} _temp_module
            mv _temp_module/* . 2>/dev/null || true
            mv _temp_module/.* . 2>/dev/null || true
            rm -rf _temp_module
        """.format(subdir = dirs[0])])

def _git_clone(repository_ctx, git_url, ref):
    """Clone a module at a tag or commit into the repo root (non-hermetic fallback)."""
    git_timeout = 300
    if _is_commit_hash(ref):
        # For commit hashes, shallow clone then fetch + checkout the commit.
        result = repository_ctx.execute(
            ["git", "clone", "--depth", "1", git_url, "."],
            quiet = False,
            timeout = git_timeout,
        )
        if result.return_code != 0:
            fail(
                "Failed to clone {}\n".format(git_url) +
                "Exit code: {}\n".format(result.return_code) +
                "stderr: {}\n".format(result.stderr) +
                "Check that the repository exists and is accessible.",
            )
        result = repository_ctx.execute(
            ["git", "fetch", "--depth", "1", "origin", ref],
            quiet = False,
            timeout = git_timeout,
        )
        if result.return_code != 0:
            fail(
                "Failed to fetch commit {} from {}\n".format(ref, git_url) +
                "Exit code: {}\n".format(result.return_code) +
                "stderr: {}\n".format(result.stderr) +
                "Check that the commit hash exists in the repository.",
            )
        result = repository_ctx.execute(
            ["git", "checkout", ref],
            quiet = False,
            timeout = 60,
        )
        if result.return_code != 0:
            fail(
                "Failed to checkout commit {}\n".format(ref) +
                "Exit code: {}\n".format(result.return_code) +
                "stderr: {}".format(result.stderr),
            )
    else:
        # For tags, --branch works for both tags and branches.
        result = repository_ctx.execute(
            ["git", "clone", "--depth", "1", "--branch", ref, git_url, "."],
            quiet = False,
            timeout = git_timeout,
        )
        if result.return_code != 0:
            fail(
                "Failed to clone {} at ref '{}'\n".format(git_url, ref) +
                "Exit code: {}\n".format(result.return_code) +
                "stderr: {}\n".format(result.stderr) +
                "Check that the tag/branch '{}' exists in the repository.".format(ref),
            )

def _module_git_repository_impl(repository_ctx):
    """Download a Terraform module from a Git repository.

    Prefers a checksum-verified tarball (GitHub sources, when the extension
    resolved a sha256); otherwise falls back to a shallow git clone.
    """
    source = repository_ctx.attr.source
    ref = repository_ctx.attr.ref
    subdirectory = repository_ctx.attr.subdirectory
    archive_url = repository_ctx.attr.archive_url

    # Parse the source URL (also validates the format).
    git_url, owner, repo = _parse_git_source(source)

    if archive_url:
        # Hermetic path: fetch the checksum-verified tarball and flatten the
        # single top-level directory GitHub wraps archive contents in.
        repository_ctx.download_and_extract(
            url = archive_url,
            type = repository_ctx.attr.archive_type or "tar.gz",
            sha256 = repository_ctx.attr.sha256,
        )
        _flatten_single_dir(repository_ctx)
    else:
        _git_clone(repository_ctx, git_url, ref)

    # If subdirectory is specified, move those files to root.
    if subdirectory:
        result = repository_ctx.execute(["ls", "-la", subdirectory])
        if result.return_code != 0:
            fail("Subdirectory {} not found in {}".format(subdirectory, source))

        result = repository_ctx.execute(["sh", "-c", """
            mv {subdir} _temp_subdir
            rm -rf .git .github .gitignore examples tests docs README.md || true
            mv _temp_subdir/* .
            rm -rf _temp_subdir
        """.format(subdir = subdirectory)])
        if result.return_code != 0:
            fail("Failed to extract subdirectory {}: {}".format(subdirectory, result.stderr))
    else:
        # Clean up git metadata and unnecessary files.
        # - exports/ contains template files for copying (e.g. cloudposse context.tf)
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
        "archive_url": attr.string(
            doc = "GitHub archive tarball URL; when set (with sha256) the module is fetched " +
                  "and checksum-verified instead of cloned",
            default = "",
        ),
        "archive_type": attr.string(
            doc = "Archive type for archive_url (default tar.gz)",
            default = "",
        ),
        "sha256": attr.string(
            doc = "Expected sha256 of the archive; verified on download when set",
            default = "",
        ),
    },
    doc = """Downloads a Terraform module from a Git repository.

    Prefers a checksum-verified GitHub tarball (when the tf_modules extension
    resolves archive_url + sha256); falls back to a shallow git clone for
    non-GitHub sources.

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
