package test

import (
	"io/ioutil"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	tfhcl "github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/hcl"
	"github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/terraform"
)

func TestReadVersionsFromHCL(t *testing.T) {
	// Test parsing a simple terraform block from HCL
	content := []byte(`
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}`)

	// Create a temp directory for this test
	tmpDir, err := ioutil.TempDir("", "test_read_versions_hcl")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Write content to a file in the temp dir
	testFile := filepath.Join(tmpDir, "terraform.tf")
	err = ioutil.WriteFile(testFile, content, 0644)
	require.NoError(t, err)

	// Read versions from the temp directory
	block, err := terraform.ReadVersionsFromDir(tmpDir)
	require.NoError(t, err)
	require.NotNil(t, block)

	// Check terraform version
	assert.Equal(t, ">= 1.0", block.RequiredVersion)

	// Check providers
	require.NotNil(t, block.RequiredProviders)
	assert.Len(t, block.RequiredProviders, 2)

	// Check AWS provider
	awsProvider, exists := block.RequiredProviders["aws"]
	assert.True(t, exists)
	assert.Equal(t, "hashicorp/aws", awsProvider.Source)
	assert.Equal(t, "~> 6.0", awsProvider.Version)

	// Check Random provider
	randomProvider, exists := block.RequiredProviders["random"]
	assert.True(t, exists)
	assert.Equal(t, "hashicorp/random", randomProvider.Source)
	assert.Equal(t, "3.7.2", randomProvider.Version)
}

func TestReadVersionsFromMixedContentFile(t *testing.T) {
	// Test parsing terraform block from a file with other resources
	content := []byte(`
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  bucket_name = "my-test-bucket"
}

resource "aws_s3_bucket" "example" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id
  versioning_configuration {
    status = "Enabled"
  }
}`)

	// Create a temp directory
	tmpDir, err := ioutil.TempDir("", "hcl_tool_mixed_test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Write the content to main.tf
	mainFile := filepath.Join(tmpDir, "main.tf")
	err = ioutil.WriteFile(mainFile, content, 0644)
	require.NoError(t, err)

	// Read versions from the directory
	block, err := terraform.ReadVersionsFromDir(tmpDir)
	require.NoError(t, err)
	require.NotNil(t, block)

	// Check terraform version
	assert.Equal(t, ">= 1.5.0", block.RequiredVersion)

	// Check providers
	require.NotNil(t, block.RequiredProviders)
	assert.Len(t, block.RequiredProviders, 1)

	// Check AWS provider
	awsProvider, exists := block.RequiredProviders["aws"]
	assert.True(t, exists)
	assert.Equal(t, "hashicorp/aws", awsProvider.Source)
	assert.Equal(t, "~> 6.0", awsProvider.Version)
}

func TestReadVersionsFromMultipleFiles(t *testing.T) {
	// Test merging terraform blocks from multiple files
	// Some files have terraform blocks, others have resources
	
	mainContent := []byte(`
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_instance" "example" {
  ami           = "ami-123456"
  instance_type = "t2.micro"
}`)

	providersContent := []byte(`
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
  }
}`)

	resourcesContent := []byte(`
resource "random_string" "example" {
  length = 16
}

locals {
  instance_name = "example-${random_string.example.result}"
}`)

	// Create a temp directory
	tmpDir, err := ioutil.TempDir("", "hcl_tool_multi_test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Write the files
	err = ioutil.WriteFile(filepath.Join(tmpDir, "main.tf"), mainContent, 0644)
	require.NoError(t, err)
	err = ioutil.WriteFile(filepath.Join(tmpDir, "providers.tf"), providersContent, 0644)
	require.NoError(t, err)
	err = ioutil.WriteFile(filepath.Join(tmpDir, "resources.tf"), resourcesContent, 0644)
	require.NoError(t, err)

	// Read versions from the directory
	block, err := terraform.ReadVersionsFromDir(tmpDir)
	require.NoError(t, err)
	require.NotNil(t, block)

	// Check terraform version (should come from main.tf)
	assert.Equal(t, ">= 1.5.0", block.RequiredVersion)

	// Check providers (should be merged from main.tf and providers.tf)
	require.NotNil(t, block.RequiredProviders)
	assert.Len(t, block.RequiredProviders, 2)

	// Check AWS provider
	awsProvider, exists := block.RequiredProviders["aws"]
	assert.True(t, exists)
	assert.Equal(t, "hashicorp/aws", awsProvider.Source)
	assert.Equal(t, "~> 6.0", awsProvider.Version)

	// Check Random provider
	randomProvider, exists := block.RequiredProviders["random"]
	assert.True(t, exists)
	assert.Equal(t, "hashicorp/random", randomProvider.Source)
	assert.Equal(t, "3.5.1", randomProvider.Version)
}

func TestWriteVersionsToFile(t *testing.T) {
	// Create a temporary directory
	tmpDir, err := ioutil.TempDir("", "hcl_tool_test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create test block
	block := &tfhcl.TerraformBlock{
		RequiredVersion: ">= 1.5",
		RequiredProviders: map[string]tfhcl.Provider{
			"aws": {
				Source:  "hashicorp/aws",
				Version: "~> 5.0",
			},
			"azurerm": {
				Source:  "hashicorp/azurerm",
				Version: "~> 3.0",
			},
		},
	}

	// Test writing HCL file
	hclFile := filepath.Join(tmpDir, "versions.tf")
	err = terraform.WriteVersionsToFile(hclFile, block)
	require.NoError(t, err)

	// Read it back
	readBlock, err := terraform.ReadVersionsFromDir(tmpDir)
	require.NoError(t, err)
	assert.Equal(t, block.RequiredVersion, readBlock.RequiredVersion)
	assert.Len(t, readBlock.RequiredProviders, 2)

	// Test writing terraform.tf file (HCL format)
	terraformFile := filepath.Join(tmpDir, "terraform.tf")
	err = terraform.WriteVersionsToFile(terraformFile, block)
	require.NoError(t, err)

	// Verify HCL file exists and contains expected content
	content, err := ioutil.ReadFile(terraformFile)
	require.NoError(t, err)
	assert.Contains(t, string(content), `required_version`)
	assert.Contains(t, string(content), `required_providers`)
}

func TestUpdateVersionsInDir(t *testing.T) {
	// Create a temporary directory
	tmpDir, err := ioutil.TempDir("", "hcl_tool_update_test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create initial versions.tf
	initialContent := `terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "versions.tf"), []byte(initialContent), 0644)
	require.NoError(t, err)

	// Update with new providers
	newProviders := map[string]tfhcl.Provider{
		"aws": {
			Source:  "hashicorp/aws",
			Version: "~> 5.0",
		},
		"random": {
			Source:  "hashicorp/random",
			Version: "3.5.1",
		},
	}

	err = terraform.UpdateVersionsInDir(tmpDir, newProviders, "")
	require.NoError(t, err)

	// Check what files exist after update
	files, _ := ioutil.ReadDir(tmpDir)
	for _, f := range files {
		t.Logf("File after update: %s", f.Name())
	}

	// Read back and verify
	block, err := terraform.ReadVersionsFromDir(tmpDir)
	require.NoError(t, err)
	assert.Equal(t, ">= 1.0", block.RequiredVersion) // Should preserve existing version
	assert.Len(t, block.RequiredProviders, 2)
	assert.Equal(t, "~> 5.0", block.RequiredProviders["aws"].Version)
	assert.Equal(t, "3.5.1", block.RequiredProviders["random"].Version)
}

func TestReadVersionsFromMultipleTerraformBlocks(t *testing.T) {
	tmpDir, err := ioutil.TempDir("", "test-multiple-blocks")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create main.tf with a terraform block
	mainContent := `terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_instance" "example" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "main.tf"), []byte(mainContent), 0644)
	require.NoError(t, err)

	// Create providers.tf with another terraform block (should be ignored - first one wins)
	providersContent := `terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
  }
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "providers.tf"), []byte(providersContent), 0644)
	require.NoError(t, err)

	// Read and verify - should use first encountered values
	block, err := terraform.ReadVersionsFromDir(tmpDir)
	require.NoError(t, err)
	assert.Equal(t, ">= 1.5.0", block.RequiredVersion) // From main.tf (alphabetically first)
	assert.Len(t, block.RequiredProviders, 2)
	assert.Equal(t, "~> 5.0", block.RequiredProviders["aws"].Version) // From main.tf
	assert.Equal(t, "hashicorp/aws", block.RequiredProviders["aws"].Source)
	assert.Equal(t, "3.5.1", block.RequiredProviders["random"].Version) // From providers.tf (not in main.tf)
	assert.Equal(t, "hashicorp/random", block.RequiredProviders["random"].Source)
}

func TestReadVersionsFromSplitProviders(t *testing.T) {
	tmpDir, err := ioutil.TempDir("", "test-split-providers")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create versions.tf with version constraint only
	versionsContent := `terraform {
  required_version = ">= 1.12.2"
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "versions.tf"), []byte(versionsContent), 0644)
	require.NoError(t, err)

	// Create providers.tf with providers only
	providersContent := `terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.12.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.13.1"
    }
  }
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "providers.tf"), []byte(providersContent), 0644)
	require.NoError(t, err)

	// Read and verify - should merge both files
	block, err := terraform.ReadVersionsFromDir(tmpDir)
	require.NoError(t, err)
	assert.Equal(t, ">= 1.12.2", block.RequiredVersion) // From versions.tf
	assert.Len(t, block.RequiredProviders, 2)
	assert.Equal(t, "6.12.0", block.RequiredProviders["aws"].Version) // From providers.tf
	assert.Equal(t, "0.13.1", block.RequiredProviders["time"].Version) // From providers.tf
}

func TestConfigurationAliasesPreservation(t *testing.T) {
	// Create a temporary directory
	tmpDir, err := ioutil.TempDir("", "hcl_tool_aliases_test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create initial terraform.tf with configuration_aliases
	initialContent := `terraform {
  required_version = ">= 1.12.2"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "6.10.0"
      configuration_aliases = [aws.prod, aws.non_prod]
    }
  }
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "terraform.tf"), []byte(initialContent), 0644)
	require.NoError(t, err)

	// Update versions using UpdateVersionsInDir (simulating version update tool)
	newProviders := map[string]tfhcl.Provider{
		"aws": {
			Source:  "hashicorp/aws",
			Version: "6.13.0", // Updated version
		},
	}
	
	err = terraform.UpdateVersionsInDir(tmpDir, newProviders, ">= 1.12.2")
	require.NoError(t, err)

	// Read the updated file
	updatedBlock, err := terraform.ReadVersionsFromDir(tmpDir)
	require.NoError(t, err)
	require.NotNil(t, updatedBlock)

	// Verify the version was updated
	awsProvider, exists := updatedBlock.RequiredProviders["aws"]
	assert.True(t, exists)
	assert.Equal(t, "hashicorp/aws", awsProvider.Source)
	assert.Equal(t, "6.13.0", awsProvider.Version) // Should be updated

	// Verify configuration_aliases were preserved
	assert.Len(t, awsProvider.ConfigurationAliases, 2)
	assert.Contains(t, awsProvider.ConfigurationAliases, "aws.prod")
	assert.Contains(t, awsProvider.ConfigurationAliases, "aws.non_prod")

	// Verify the written file still contains proper configuration_aliases
	content, err := ioutil.ReadFile(filepath.Join(tmpDir, "terraform.tf"))
	require.NoError(t, err)
	fileContent := string(content)
	
	// Should contain both aliases as traversals (not strings)
	assert.Contains(t, fileContent, "aws.prod")
	assert.Contains(t, fileContent, "aws.non_prod")
	assert.Contains(t, fileContent, "configuration_aliases")
	
	// Should contain updated version
	assert.Contains(t, fileContent, "6.13.0")
}