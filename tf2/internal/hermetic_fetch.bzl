"""Hermetic fetch helpers: resolve and lock content hashes for downloads.

Extends the provider hash-and-lock pattern (see `_tf_providers_impl` in
`tf2/extensions.bzl`) to tools and external modules. Given an artifact to fetch,
a sha256 is resolved in this order:

  1. `module_ctx.facts` - already locked in MODULE.bazel.lock, reuse it.
  2. the publisher's checksums file (`SHA256SUMS` / `checksums.txt`) - verify
     against the publisher and lock every platform it lists.
  3. trust-on-first-use - hash whatever we download and lock that.

All resolution runs inside a module extension, because only extensions can read
and write `module_ctx.facts`. Repo rules receive the resolved sha256 as an
attribute and verify it at download time via `download_and_extract(sha256=...)`.

The returned dicts are stored verbatim in `extension_metadata(facts=...)`, so
they must be JSON-serialisable (plain strings/dicts/lists only).
"""

# Value stored in facts under each key: {"sha256": {...}|"...", "source": "<provenance>"}.
_SOURCE_UPSTREAM = "upstream"  # verified against the publisher's checksums file
_SOURCE_TOFU = "tofu"  # trust-on-first-use: hash of the first download

def parse_sums_file(content, filename):
    """Return the hex sha256 for `filename` from a checksums file, or None.

    Handles the GNU coreutils `sha256sum` output formats used by HashiCorp
    `*_SHA256SUMS` files and GitHub-release `checksums.txt` assets:

        <sha256>  <name>      # text mode (two spaces)
        <sha256> *<name>      # binary mode (leading asterisk)

    Blank lines, comment lines (`#`), and rows for other files are ignored.

    Args:
        content: full text of the checksums file.
        filename: the exact asset filename to look up (no path).

    Returns:
        The lowercase hex digest string, or None if `filename` is absent.
    """
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        # Starlark split() needs an explicit separator and does not collapse
        # runs, so normalise tabs to spaces and drop the empty tokens that the
        # two-space `<sha>  <name>` separator would otherwise produce.
        parts = [tok for tok in line.replace("\t", " ").split(" ") if tok]
        if len(parts) < 2:
            continue
        name = parts[-1]
        if name.startswith("*"):
            name = name[1:]
        if name == filename:
            return parts[0]
    return None

def facts_key(*parts):
    """Build a stable facts key from parts.

    e.g. facts_key("tool", "terraform", "1.14.2") -> "tool:terraform:1.14.2".
    The key is the MODULE.bazel.lock fact identifier, so it must be stable
    across runs and unique per lockable artifact.
    """
    return ":".join([str(p) for p in parts])

def _slug(s):
    """Filesystem-safe slug for scratch paths."""
    return s.replace(":", "_").replace("/", "_").replace(".", "_")

def resolve_platform_hashes(module_ctx, facts, key, sums_url, platform_files):
    """Resolve `{platform: sha256}` for a per-platform artifact (e.g. a tool).

    Prefers the publisher's checksums file, which lists every platform at once,
    so a single fetch locks a lockfile that is portable across the platforms
    developers and CI build on.

    Args:
        module_ctx: the module extension context.
        facts: existing `module_ctx.facts` (or None on older Bazel).
        key: facts key identifying this artifact+version.
        sums_url: URL of the publisher's checksums file, or None if it has none.
        platform_files: `{platform_id: asset_filename}` mapping each platform to
            the exact filename listed in the checksums file.

    Returns:
        (record, cached): `record` is the facts value
        `{"sha256": {platform: hex}, "source": ...}`; `cached` is True when it
        came from facts (no network performed). An empty `sha256` map means the
        checksums file was unavailable or listed none of our platforms - callers
        fall back to trust-on-first-use per platform.
    """
    cached = facts.get(key, None) if facts else None
    if cached and type(cached) == "dict" and cached.get("sha256", None):
        return cached, True

    hashes = {}
    if sums_url:
        out = module_ctx.path("_sums_" + _slug(key))
        res = module_ctx.download(url = sums_url, output = out, allow_fail = True)
        if res.success:
            content = module_ctx.read(out)
            for platform, fname in platform_files.items():
                digest = parse_sums_file(content, fname)
                if digest:
                    hashes[platform] = digest

    return {"sha256": hashes, "source": _SOURCE_UPSTREAM}, False

def resolve_per_file_hashes(module_ctx, facts, key, platform_sums):
    """Resolve `{platform: sha256}` from per-asset checksum files.

    Some publishers (e.g. OPA) ship one `<asset>.sha256` file per artifact
    rather than a single combined SHA256SUMS. Each is fetched and parsed.

    Args:
        module_ctx: the module extension context.
        facts: existing `module_ctx.facts` (or None).
        key: facts key identifying this artifact+version.
        platform_sums: `{platform: struct(url = <sums url>, filename = <asset>)}`.

    Returns:
        (record, cached): same shape as `resolve_platform_hashes`.
    """
    cached = facts.get(key, None) if facts else None
    if cached and type(cached) == "dict" and cached.get("sha256", None):
        return cached, True

    hashes = {}
    for platform in platform_sums:
        entry = platform_sums[platform]
        out = module_ctx.path("_sums_" + _slug(key + "_" + platform))
        res = module_ctx.download(url = entry.url, output = out, allow_fail = True)
        if res.success:
            digest = parse_sums_file(module_ctx.read(out), entry.filename)
            if digest:
                hashes[platform] = digest

    return {"sha256": hashes, "source": _SOURCE_UPSTREAM}, False

def tofu_hash(module_ctx, key, url, headers = {}):
    """Trust-on-first-use: download `url` and return its sha256.

    Used when a publisher ships no checksums file. The first build records the
    hash; every later build verifies against it. Returns the lowercase hex
    digest.
    """
    out = module_ctx.path("_tofu_" + _slug(key))
    res = module_ctx.download(url = url, output = out, headers = headers)
    return res.sha256

def resolve_single_hash(
        module_ctx,
        facts,
        key,
        artifact_url,
        headers = {},
        sums_url = None,
        sums_filename = None):
    """Resolve one sha256 for a single (non-per-platform) artifact.

    Used for external modules, where the download is one archive rather than a
    per-platform binary. Prefers a publisher checksums file when one is given,
    otherwise trust-on-first-use on `artifact_url`.

    Args:
        module_ctx: the module extension context.
        facts: existing `module_ctx.facts` (or None).
        key: facts key for this artifact.
        artifact_url: URL of the archive to hash on the TOFU path.
        headers: optional request headers (e.g. registry auth).
        sums_url: optional publisher checksums URL.
        sums_filename: filename to look up within the checksums file.

    Returns:
        (record, cached): `record` is `{"sha256": hex, "source": ...}`.
    """
    cached = facts.get(key, None) if facts else None
    if cached and type(cached) == "dict" and cached.get("sha256", None):
        return cached, True

    if sums_url and sums_filename:
        out = module_ctx.path("_sums_" + _slug(key))
        res = module_ctx.download(url = sums_url, output = out, allow_fail = True)
        if res.success:
            digest = parse_sums_file(module_ctx.read(out), sums_filename)
            if digest:
                return {"sha256": digest, "source": _SOURCE_UPSTREAM}, False

    return {"sha256": tofu_hash(module_ctx, key, artifact_url, headers), "source": _SOURCE_TOFU}, False
