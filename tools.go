//go:build tools

// Package tools tracks dependencies for tools used by this project.
// These imports ensure `go mod tidy` doesn't remove dependencies
// needed by Bazel build targets.
package tools

import (
	_ "github.com/hashicorp/go-version"
	_ "github.com/hashicorp/hcl/v2"
	_ "github.com/hashicorp/terraform-registry-address"
	_ "github.com/spf13/cobra"
	_ "github.com/stretchr/testify/assert"
	_ "github.com/terraform-linters/tflint-plugin-sdk/plugin"
	_ "github.com/terraform-linters/tflint-plugin-sdk/tflint"
	_ "github.com/zclconf/go-cty/cty"
)
