# Add or update a provider

Add a Terraform provider (or bump its version), sync the hashes into the Bazel
lockfile, and keep it up to date.

## Prerequisites

- A `versions.json` referenced by the `tf_providers` extension in `MODULE.bazel`.

## Add or bump a provider

1. Edit `versions.json` — providers map a source to a list of versions (multiple
   majors can coexist):

   ```json
   {
     "providers": {
       "hashicorp/aws": ["5.100.0", "6.26.0"],
       "hashicorp/random": ["3.7.2"]
     }
   }
   ```

2. Build. Hashes are generated and cached automatically:

   ```bash
   bazel build //...
   ```

   On first sight of a `source:version`, the `tf_providers` extension runs
   `terraform providers lock` across all platforms and writes the `h1`/`zh`
   hashes into **`MODULE.bazel.lock`** (via the Bazel 8.5+ facts mechanism). No
   network on later builds. There is **no** committed `.terraform.lock.hcl`.

3. Reference the provider in a module by its **major-version alias**
   (`{name}_{major}`):

   ```starlark
   providers = ["@tf_provider_registry//:aws_6"]   # hashicorp/aws 6.x
   ```

   `hashicorp/aws` `6.26.0` → `aws_6`; a `0.x` provider → e.g. `time_0`.

4. Commit `versions.json` **and** `MODULE.bazel.lock` together.

## Automating updates

`scripts/tf_upgrade_providers.sh` queries the Terraform registry (and GitHub /
HashiCorp releases for tools) for the latest versions and rewrites
`versions.json`:

```bash
scripts/tf_upgrade_providers.sh --dry-run     # preview changes
scripts/tf_upgrade_providers.sh               # apply to versions.json
scripts/tf_upgrade_providers.sh --skip-tools  # providers only
```

The script **only edits `versions.json`** — it does not generate hashes. The
next `bazel build` produces and caches them (step 2 above). Then refresh each
module's `providers`/`srcs` with [Gazelle](generate-build-files.md):

```bash
bazel run //tf2/gazelle:gazelle -- path/to/modules
bazel build //... && bazel test //...
```

> The script is **run manually** — there is no Renovate/Dependabot/CI wiring for
> it today. See the [Roadmap](https://github.com/wayvz-io/rules_tf2#roadmap).

## See also

- [Provider versioning](../explanation/versioning/providers.md) · [Auto updates](../explanation/versioning/auto-updates.md)
- [Tools versioning](../explanation/versioning/tools.md) — same `versions.json`, `tools` block
