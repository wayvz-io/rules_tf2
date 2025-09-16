package test

import (
	"bytes"
	"encoding/json"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	tfhcl "github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/hcl"
)

// Helper to build the hcl_tool binary for testing
func buildHCLTool(t *testing.T) string {
	// Skip the build for now - this would be done by bazel
	t.Skip("Skipping integration test - requires hcl_tool binary to be built")
	return ""
}

func TestReadVersionsCommand(t *testing.T) {
	binary := buildHCLTool(t)
	
	// Create test directory with terraform files
	tmpDir, err := ioutil.TempDir("", "test_read_versions")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Write a terraform.tf file
	terraformContent := `terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.prod, aws.non_prod]
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "terraform.tf"), []byte(terraformContent), 0644)
	require.NoError(t, err)

	// Run read-versions command
	cmd := exec.Command(binary, "read-versions", tmpDir)
	output, err := cmd.Output()
	require.NoError(t, err)

	// Parse JSON output
	var result tfhcl.TerraformBlock
	err = json.Unmarshal(output, &result)
	require.NoError(t, err)

	// Verify results
	assert.Equal(t, ">= 1.5.0", result.RequiredVersion)
	assert.Len(t, result.RequiredProviders, 2)
	
	awsProvider := result.RequiredProviders["aws"]
	assert.Equal(t, "hashicorp/aws", awsProvider.Source)
	assert.Equal(t, "~> 6.0", awsProvider.Version)
	assert.Equal(t, []string{"aws.prod", "aws.non_prod"}, awsProvider.ConfigurationAliases)
	
	randomProvider := result.RequiredProviders["random"]
	assert.Equal(t, "hashicorp/random", randomProvider.Source)
	assert.Equal(t, "3.7.2", randomProvider.Version)
	assert.Empty(t, randomProvider.ConfigurationAliases)
}

func TestValidateVersionsCommand(t *testing.T) {
	binary := buildHCLTool(t)
	
	// Create test directory
	tmpDir, err := ioutil.TempDir("", "test_validate_versions")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Write terraform.tf file
	terraformContent := `terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.13.0"
      configuration_aliases = [aws.prod, aws.non_prod]
    }
  }
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "terraform.tf"), []byte(terraformContent), 0644)
	require.NoError(t, err)

	t.Run("ValidVersions", func(t *testing.T) {
		// Create expected versions
		expected := tfhcl.TerraformBlock{
			RequiredVersion: ">= 1.5.0",
			RequiredProviders: map[string]tfhcl.Provider{
				"aws": {
					Source:  "hashicorp/aws",
					Version: "6.13.0",
				},
			},
		}
		expectedJSON, _ := json.Marshal(expected)

		// Run validate-versions command
		cmd := exec.Command(binary, "validate-versions", tmpDir)
		cmd.Stdin = bytes.NewReader(expectedJSON)
		output, err := cmd.CombinedOutput()
		require.NoError(t, err, "Output: %s", output)
		assert.Contains(t, string(output), "successful")
	})

	t.Run("InvalidVersions", func(t *testing.T) {
		// Create mismatched expected versions
		expected := tfhcl.TerraformBlock{
			RequiredVersion: ">= 1.6.0", // Different version
			RequiredProviders: map[string]tfhcl.Provider{
				"aws": {
					Source:  "hashicorp/aws",
					Version: "6.14.0", // Different version
				},
			},
		}
		expectedJSON, _ := json.Marshal(expected)

		// Run validate-versions command
		cmd := exec.Command(binary, "validate-versions", tmpDir)
		cmd.Stdin = bytes.NewReader(expectedJSON)
		output, err := cmd.CombinedOutput()
		assert.Error(t, err)
		assert.Contains(t, string(output), "validation failed")
		assert.Contains(t, string(output), "Incorrect required_version")
		assert.Contains(t, string(output), "Incorrect version for provider 'aws'")
	})

	t.Run("ConfigurationAliasesPreserved", func(t *testing.T) {
		// Validate that configuration_aliases are preserved but not validated
		expected := tfhcl.TerraformBlock{
			RequiredVersion: ">= 1.5.0",
			RequiredProviders: map[string]tfhcl.Provider{
				"aws": {
					Source:  "hashicorp/aws",
					Version: "6.13.0",
					// No configuration_aliases in expected - should still pass
				},
			},
		}
		expectedJSON, _ := json.Marshal(expected)

		cmd := exec.Command(binary, "validate-versions", tmpDir)
		cmd.Stdin = bytes.NewReader(expectedJSON)
		output, err := cmd.CombinedOutput()
		require.NoError(t, err, "Output: %s", output)
		assert.Contains(t, string(output), "successful")
	})
}

func TestWriteVersionsCommand(t *testing.T) {
	binary := buildHCLTool(t)
	
	// Create test directory
	tmpDir, err := ioutil.TempDir("", "test_write_versions")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create expected versions
	expected := tfhcl.TerraformBlock{
		RequiredVersion: ">= 1.5.0",
		RequiredProviders: map[string]tfhcl.Provider{
			"aws": {
				Source:  "hashicorp/aws",
				Version: "6.13.0",
			},
			"random": {
				Source:  "hashicorp/random",
				Version: "3.7.2",
			},
		},
	}
	expectedJSON, _ := json.Marshal(expected)

	// Create output file path
	outputFile := filepath.Join(tmpDir, "terraform.tf")

	// Run write-versions command
	cmd := exec.Command(binary, "write-versions", outputFile)
	cmd.Stdin = bytes.NewReader(expectedJSON)
	output, err := cmd.CombinedOutput()
	require.NoError(t, err, "Output: %s", output)

	// Verify file was created
	assert.FileExists(t, outputFile)

	// Read and verify content
	content, err := ioutil.ReadFile(outputFile)
	require.NoError(t, err)
	
	// Check that all expected elements are present
	contentStr := string(content)
	assert.Contains(t, contentStr, "terraform {")
	assert.Contains(t, contentStr, `required_version = ">= 1.5.0"`)
	assert.Contains(t, contentStr, "required_providers {")
	assert.Contains(t, contentStr, "aws = {")
	assert.Contains(t, contentStr, `source  = "hashicorp/aws"`)
	assert.Contains(t, contentStr, `version = "6.13.0"`)
	assert.Contains(t, contentStr, "random = {")
	assert.Contains(t, contentStr, `source  = "hashicorp/random"`)
	assert.Contains(t, contentStr, `version = "3.7.2"`)
}

func TestUpdateVersionsCommand(t *testing.T) {
	binary := buildHCLTool(t)
	
	// Create test directory
	tmpDir, err := ioutil.TempDir("", "test_update_versions")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Write initial terraform.tf with configuration_aliases
	initialContent := `terraform {
  required_version = ">= 1.4.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.12.0"
      configuration_aliases = [aws.prod, aws.non_prod]
    }
  }
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "terraform.tf"), []byte(initialContent), 0644)
	require.NoError(t, err)

	// Create new versions to update to
	newVersions := tfhcl.TerraformBlock{
		RequiredVersion: ">= 1.5.0",
		RequiredProviders: map[string]tfhcl.Provider{
			"aws": {
				Source:  "hashicorp/aws",
				Version: "6.13.0",
			},
			"random": {
				Source:  "hashicorp/random",
				Version: "3.7.2",
			},
		},
	}
	newVersionsJSON, _ := json.Marshal(newVersions)

	// Run update-versions command
	cmd := exec.Command(binary, "update-versions", tmpDir)
	cmd.Stdin = bytes.NewReader(newVersionsJSON)
	output, err := cmd.CombinedOutput()
	require.NoError(t, err, "Output: %s", output)

	// Read updated file
	content, err := ioutil.ReadFile(filepath.Join(tmpDir, "terraform.tf"))
	require.NoError(t, err)
	contentStr := string(content)

	// Verify updates
	assert.Contains(t, contentStr, `required_version = ">= 1.5.0"`)
	assert.Contains(t, contentStr, `version = "6.13.0"`)
	assert.Contains(t, contentStr, "random = {")
	assert.Contains(t, contentStr, `version = "3.7.2"`)
	
	// Verify configuration_aliases were preserved
	assert.Contains(t, contentStr, "configuration_aliases = [aws.prod, aws.non_prod]")
}

func TestValidateOrganizationCommand(t *testing.T) {
	binary := buildHCLTool(t)
	
	// Create test directory
	tmpDir, err := ioutil.TempDir("", "test_validate_org")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	t.Run("ValidOrganization", func(t *testing.T) {
		// Create properly organized files
		err := ioutil.WriteFile(filepath.Join(tmpDir, "main.tf"), []byte(`
resource "aws_instance" "example" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
}`), 0644)
		require.NoError(t, err)

		err = ioutil.WriteFile(filepath.Join(tmpDir, "variables.tf"), []byte(`
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}`), 0644)
		require.NoError(t, err)

		err = ioutil.WriteFile(filepath.Join(tmpDir, "outputs.tf"), []byte(`
output "instance_id" {
  value = aws_instance.example.id
}`), 0644)
		require.NoError(t, err)

		// Run validate-organization command
		cmd := exec.Command(binary, "validate-organization", tmpDir)
		output, err := cmd.CombinedOutput()
		require.NoError(t, err, "Output: %s", output)
		assert.Contains(t, string(output), "valid")
	})

	t.Run("InvalidOrganization", func(t *testing.T) {
		// Create improperly organized file
		badDir, err := ioutil.TempDir("", "test_bad_org")
		require.NoError(t, err)
		defer os.RemoveAll(badDir)

		err = ioutil.WriteFile(filepath.Join(badDir, "main.tf"), []byte(`
variable "region" {
  description = "Should be in variables.tf"
  type        = string
}

resource "aws_instance" "example" {
  ami = "ami-12345678"
}

output "id" {
  value       = "Should be in outputs.tf"
  description = "Instance ID"
}`), 0644)
		require.NoError(t, err)

		// Run validate-organization command
		cmd := exec.Command(binary, "validate-organization", badDir)
		output, err := cmd.CombinedOutput()
		assert.Error(t, err)
		assert.Contains(t, strings.ToLower(string(output)), "invalid")
	})
}

func TestReorganizeCommand(t *testing.T) {
	binary := buildHCLTool(t)
	
	// Create test directory
	tmpDir, err := ioutil.TempDir("", "test_reorganize")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create mixed content file
	err = ioutil.WriteFile(filepath.Join(tmpDir, "main.tf"), []byte(`
terraform {
  required_version = ">= 1.5.0"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

resource "aws_instance" "example" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
}

output "instance_id" {
  value       = aws_instance.example.id
  description = "The instance ID"
}

locals {
  common_tags = {
    Environment = "test"
  }
}`), 0644)
	require.NoError(t, err)

	// Run reorganize command
	cmd := exec.Command(binary, "reorganize", tmpDir)
	output, err := cmd.CombinedOutput()
	require.NoError(t, err, "Output: %s", output)

	// Check that files were created
	assert.FileExists(t, filepath.Join(tmpDir, "terraform.tf"))
	assert.FileExists(t, filepath.Join(tmpDir, "variables.tf"))
	assert.FileExists(t, filepath.Join(tmpDir, "outputs.tf"))
	assert.FileExists(t, filepath.Join(tmpDir, "locals.tf"))

	// Verify terraform.tf content
	terraformContent, err := ioutil.ReadFile(filepath.Join(tmpDir, "terraform.tf"))
	require.NoError(t, err)
	assert.Contains(t, string(terraformContent), "terraform {")
	assert.Contains(t, string(terraformContent), `required_version = ">= 1.5.0"`)

	// Verify variables.tf content
	variablesContent, err := ioutil.ReadFile(filepath.Join(tmpDir, "variables.tf"))
	require.NoError(t, err)
	assert.Contains(t, string(variablesContent), "variable \"region\"")

	// Verify outputs.tf content
	outputsContent, err := ioutil.ReadFile(filepath.Join(tmpDir, "outputs.tf"))
	require.NoError(t, err)
	assert.Contains(t, string(outputsContent), "output \"instance_id\"")

	// Verify locals.tf content
	localsContent, err := ioutil.ReadFile(filepath.Join(tmpDir, "locals.tf"))
	require.NoError(t, err)
	assert.Contains(t, string(localsContent), "locals {")
	assert.Contains(t, string(localsContent), "common_tags")

	// Main.tf should still have the resource
	mainContent, err := ioutil.ReadFile(filepath.Join(tmpDir, "main.tf"))
	require.NoError(t, err)
	assert.Contains(t, string(mainContent), "resource \"aws_instance\"")
}