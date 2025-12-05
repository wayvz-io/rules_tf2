package test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/terraform"
)

func TestParseLockFile(t *testing.T) {
	// Use embedded test data instead of file
	content := []byte(`# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {
  version     = "6.12.0"
  constraints = "6.12.0"
  hashes = [
    "h1:7wEpPPlA0wbAVsOEYCNIDMuNWL0MAD4nEvFtF/2iJXU=",
    "zh:0425f842e476fcc754e1018de9c13b7b8c9ec2e10c0c231344e1e0e6b44797c8",
    "zh:0b07a6a6f87e60e5caaca88c1c7a0872bb2bf9f7e488df3c24bc7cb90fa5bba6",
    "zh:0de94e965bb88e432f5f06afa1cf996e87e88c8f88bc5a4c8e6b5e02a1c89f26",
  ]
}

provider "registry.terraform.io/hashicorp/random" {
  version     = "3.7.2"
  constraints = "3.7.2"
  hashes = [
    "h1:rn9RwV5NESM/nq/V9lzuKJI6hsLZBo8xAC+x9TkRGkE=",
    "zh:078767b1a1b5a78a7c1c9dc1feb839c67298bca1e973f0707e9bfb34559f2b83",
  ]
}`)

	// Parse the lock file
	lockFile, err := terraform.ParseLockFile(content)
	require.NoError(t, err)
	require.NotNil(t, lockFile)

	// Check AWS provider
	awsProvider, exists := lockFile.Providers["registry.terraform.io/hashicorp/aws"]
	assert.True(t, exists, "AWS provider should exist")
	assert.Equal(t, "6.12.0", awsProvider.Version)
	assert.Equal(t, "6.12.0", awsProvider.Constraints)
	assert.Len(t, awsProvider.Hashes, 4)

	// Check Random provider
	randomProvider, exists := lockFile.Providers["registry.terraform.io/hashicorp/random"]
	assert.True(t, exists, "Random provider should exist")
	assert.Equal(t, "3.7.2", randomProvider.Version)
	assert.Len(t, randomProvider.Hashes, 2)
}

func TestParseLockFileSimple(t *testing.T) {
	// Test with a simple lock file format
	content := []byte(`
provider "registry.terraform.io/hashicorp/null" {
  version = "3.2.4"
  hashes = [
    "h1:test123",
  ]
}
`)

	lockFile, err := terraform.ParseLockFile(content)
	require.NoError(t, err)
	require.NotNil(t, lockFile)

	nullProvider, exists := lockFile.Providers["registry.terraform.io/hashicorp/null"]
	assert.True(t, exists)
	assert.Equal(t, "3.2.4", nullProvider.Version)
	assert.Len(t, nullProvider.Hashes, 1)
	assert.Equal(t, "h1:test123", nullProvider.Hashes[0])
}