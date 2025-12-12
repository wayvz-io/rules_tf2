# Auto Updates

rules_tf2 includes scripts to automate version updates.

## tf_upgrade_providers.sh

Updates provider versions in `versions.json` and regenerates lock files.

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
3. Downloads new providers and generates hashes
4. Updates `provider_locks.json`

Works in both the rules_tf2 workspace and external workspaces that depend on it.

## tf_mod.sh

Module maintenance operations.

```bash
# Show help
./scripts/tf_mod.sh --help
```

## generate_provider_locks.sh

Regenerates `provider_locks.json` from current `versions.json`:

```bash
./scripts/generate_provider_locks.sh
```

Run this after manually editing provider versions.

## Update Workflow

Typical workflow for updating versions:

1. Run `tf_upgrade_providers.sh` to update versions and locks
2. Run Gazelle to update BUILD files if module structure changed
3. Run `bazel test //...` to verify everything still works
4. Commit changes to `versions.json` and `provider_locks.json`

## Gazelle for BUILD Files

After version updates, run Gazelle to update BUILD files if providers changed:

```bash
bazel run //tf2/gazelle:gazelle -- path/to/modules
```

See [Gazelle](gazelle.md) for BUILD file generation details.
