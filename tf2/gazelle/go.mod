module github.com/wayvz-io/rules_tf2/tf2/gazelle

go 1.23.0

// Pinned to v0.51.3 (last release with real source for the packages this plugin
// imports). Starting in v0.52.0, gazelle's org move turned config/label/language/
// repo/resolve/rule into thin shims that re-export github.com/bazel-contrib/
// bazel-gazelle/v2/*, but the only published /v2 tag (v2.0.0-2) does not contain
// those packages - so `go build ./...` (CodeQL Go extraction) cannot resolve them.
// This go.mod is tooling-only: the Bazel build uses @gazelle (BCR) from MODULE.bazel,
// so this pin does not affect the real build. Renovate holds it here (renovate.json).
// Revisit once upstream publishes a usable /v2 module.
require github.com/bazelbuild/bazel-gazelle v0.51.3
