# Auto Updates

rules_tf2 includes scripts to automate version updates.

## tf_upgrade_providers.sh

Updates provider versions in `versions.json`. Provider hashes are automatically generated on the next build.

```bash
# Update all providers to latest
./scripts/tf_upgrade_providers.sh

# Dry run (show what would change)
./scripts/tf_upgrade_providers.sh --dry-run

# Update tools only
./scripts/tf_upgrade_providers.sh --tools-only

# Skip tool updates
./scripts/tf_upgrade_providers.sh --skip-tools
```

The script:
1. Queries the Terraform registry for latest provider versions
2. Updates `versions.json`

Provider hashes are **automatically generated** on the next `bazel build` command and cached in `MODULE.bazel.lock`.

Works in both the rules_tf2 workspace and external workspaces that depend on it.

## Automatic Hash Generation

Unlike previous versions that required manual lock file generation, rules_tf2 now automatically generates provider hashes when needed:

1. Edit `versions.json` to add/update providers
2. Run `bazel build //...`
3. The extension detects missing hashes and generates them automatically
4. Hashes are cached in `MODULE.bazel.lock` (via Bazel's `module_ctx.facts`)
5. Subsequent builds use cached hashes (instant)

```bash
# Add a new provider
vim versions.json

# Build triggers automatic hash generation
bazel build //...
# INFO: Generating hashes for hashicorp/newprovider:1.0.0 (this may take a while)

# Commit both files
git add versions.json MODULE.bazel.lock
git commit -m "Add newprovider"
```

## Update Workflow

Typical workflow for updating versions:

1. Run `tf_upgrade_providers.sh` to update versions
2. Run `bazel build //...` to generate hashes for new versions
3. Run `bazel test //...` to verify everything still works
4. Commit changes to `versions.json` and `MODULE.bazel.lock`

## Gazelle for BUILD Files

After version updates, run Gazelle to update BUILD files if providers changed:

```bash
bazel run //tf2/gazelle:gazelle -- path/to/modules
```

See [Gazelle](gazelle.md) for BUILD file generation details.

## Requirements

- **Bazel 8.5+**: Required for automatic hash generation (`module_ctx.facts` support)
- **Network access**: Required only when generating hashes for new providers
