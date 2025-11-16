package test

import (
	"io/ioutil"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	tfhcl "github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/hcl"
	"github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/terraform"
)

func TestParseBasicTerraformConfig(t *testing.T) {
	tmpDir, err := ioutil.TempDir("", "test-parse-config")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create a main.tf with mixed content
	mainContent := `terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t2.micro"
}

resource "aws_instance" "example" {
  ami           = "ami-12345678"
  instance_type = var.instance_type
}

output "instance_id" {
  value = aws_instance.example.id
}`

	err = ioutil.WriteFile(filepath.Join(tmpDir, "main.tf"), []byte(mainContent), 0644)
	require.NoError(t, err)

	// Parse the configuration
	config, err := terraform.ParseTerraformConfig(tmpDir)
	require.NoError(t, err)
	require.NotNil(t, config)

	// Check that blocks were correctly categorized
	assert.Len(t, config.TerraformBlocks, 1)
	assert.Len(t, config.VariableBlocks, 1)
	assert.Len(t, config.OutputBlocks, 1)
	
	// Variable should be named "instance_type"
	assert.Equal(t, "instance_type", config.VariableBlocks[0].Name)
	
	// Output should be named "instance_id"
	assert.Equal(t, "instance_id", config.OutputBlocks[0].Name)
}

func TestOrganizeTerraformFiles(t *testing.T) {
	tmpDir, err := ioutil.TempDir("", "test-organize")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create a main.tf with everything mixed
	mainContent := `terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

resource "aws_instance" "example" {
  ami           = "ami-12345678"
  instance_type = var.instance_type
}

output "instance_id" {
  value = aws_instance.example.id
}`

	err = ioutil.WriteFile(filepath.Join(tmpDir, "main.tf"), []byte(mainContent), 0644)
	require.NoError(t, err)

	// Parse the configuration
	config, err := terraform.ParseTerraformConfig(tmpDir)
	require.NoError(t, err)

	// Organize the configuration
	err = terraform.OrganizeTerraformFiles(config)
	require.NoError(t, err)

	// Check that files were organized
	assert.NotEmpty(t, config.TerraformFile, "Should have terraform.tf content")
	assert.NotEmpty(t, config.ProvidersFile, "Should have providers.tf content")
	assert.NotEmpty(t, config.VariablesFile, "Should have variables.tf content")
	assert.NotEmpty(t, config.OutputsFile, "Should have outputs.tf content")
	
	// Check that terraform file contains terraform block
	assert.Contains(t, config.TerraformFile, "terraform {")
	assert.Contains(t, config.TerraformFile, "required_version")
	
	// Check that providers file contains provider block
	assert.Contains(t, config.ProvidersFile, "provider")
	
	// Check that variables file contains variable block
	assert.Contains(t, config.VariablesFile, "variable")
	assert.Contains(t, config.VariablesFile, "instance_type")
	
	// Check that outputs file contains output block
	assert.Contains(t, config.OutputsFile, "output")
	assert.Contains(t, config.OutputsFile, "instance_id")
}

func TestMultipleTerraformBlocksMerge(t *testing.T) {
	tmpDir, err := ioutil.TempDir("", "test-merge-terraform")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create main.tf with a terraform block
	mainContent := `terraform {
  required_version = ">= 1.5.0"
}

resource "aws_instance" "example" {
  ami = "ami-12345678"
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "main.tf"), []byte(mainContent), 0644)
	require.NoError(t, err)

	// Create providers.tf with another terraform block
	providersContent := `terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}`
	err = ioutil.WriteFile(filepath.Join(tmpDir, "providers.tf"), []byte(providersContent), 0644)
	require.NoError(t, err)

	// Parse the configuration
	config, err := terraform.ParseTerraformConfig(tmpDir)
	require.NoError(t, err)

	// Should have found 2 terraform blocks
	assert.Len(t, config.TerraformBlocks, 2)

	// Organize the configuration
	err = terraform.OrganizeTerraformFiles(config)
	require.NoError(t, err)

	// Check that terraform blocks were merged
	assert.NotEmpty(t, config.TerraformFile)
	// Both blocks should be in the merged output (for now we concatenate)
	assert.Contains(t, config.TerraformFile, "required_version")
	assert.Contains(t, config.TerraformFile, "required_providers")
}

func TestPreserveResourcesAndDataSources(t *testing.T) {
	tmpDir, err := ioutil.TempDir("", "test-preserve")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create main.tf with resources and data sources
	mainContent := `resource "aws_instance" "example" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
}

locals {
  instance_name = "example-instance"
}`

	err = ioutil.WriteFile(filepath.Join(tmpDir, "main.tf"), []byte(mainContent), 0644)
	require.NoError(t, err)

	// Parse the configuration
	config, err := terraform.ParseTerraformConfig(tmpDir)
	require.NoError(t, err)

	// Organize the configuration
	err = terraform.OrganizeTerraformFiles(config)
	require.NoError(t, err)

	// Check that resources, data sources, and locals are preserved
	assert.NotEmpty(t, config.PreservedFiles["main.tf"])
	preserved := config.PreservedFiles["main.tf"]
	assert.Contains(t, preserved, "resource")
	assert.Contains(t, preserved, "aws_instance")
	assert.Contains(t, preserved, "data")
	assert.Contains(t, preserved, "aws_ami")
	assert.Contains(t, preserved, "locals")
}

func TestWriteTerraformConfig(t *testing.T) {
	tmpDir, err := ioutil.TempDir("", "test-write-config")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create a simple configuration
	config := &tfhcl.ModuleOrganization{
		TerraformFile: `terraform {
  required_version = ">= 1.5.0"
}`,
		VariablesFile: `variable "region" {
  type    = string
  default = "us-west-2"
}`,
		OutputsFile: `output "region" {
  value = var.region
}`,
		PreservedFiles: map[string]string{
			"main.tf": `resource "aws_instance" "example" {
  ami = "ami-12345678"
}`,
		},
	}

	// Write the configuration
	err = terraform.WriteTerraformConfig(tmpDir, config)
	require.NoError(t, err)

	// Check that files were created
	terraformFile := filepath.Join(tmpDir, "terraform.tf")
	variablesFile := filepath.Join(tmpDir, "variables.tf")
	outputsFile := filepath.Join(tmpDir, "outputs.tf")
	mainFile := filepath.Join(tmpDir, "main.tf")

	assert.FileExists(t, terraformFile)
	assert.FileExists(t, variablesFile)
	assert.FileExists(t, outputsFile)
	assert.FileExists(t, mainFile)

	// Read and verify content
	content, err := ioutil.ReadFile(terraformFile)
	require.NoError(t, err)
	assert.Contains(t, string(content), "required_version")

	content, err = ioutil.ReadFile(variablesFile)
	require.NoError(t, err)
	assert.Contains(t, string(content), "variable")
	assert.Contains(t, string(content), "region")

	content, err = ioutil.ReadFile(outputsFile)
	require.NoError(t, err)
	assert.Contains(t, string(content), "output")

	content, err = ioutil.ReadFile(mainFile)
	require.NoError(t, err)
	assert.Contains(t, string(content), "resource")
	assert.Contains(t, string(content), "aws_instance")
}

func TestEmptyDirectory(t *testing.T) {
	tmpDir, err := ioutil.TempDir("", "test-empty")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Parse empty directory
	config, err := terraform.ParseTerraformConfig(tmpDir)
	require.NoError(t, err)
	require.NotNil(t, config)

	// Should have no blocks
	assert.Empty(t, config.TerraformBlocks)
	assert.Empty(t, config.VariableBlocks)
	assert.Empty(t, config.OutputBlocks)
	assert.Empty(t, config.ProviderBlocks)
	assert.Empty(t, config.ImportBlocks)
}

func TestProviderBlockParsing(t *testing.T) {
	tmpDir, err := ioutil.TempDir("", "test-provider")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	// Create providers.tf with aliased providers
	providersContent := `provider "aws" {
  region = "us-west-2"
}

provider "aws" {
  alias  = "east"
  region = "us-east-1"
}`

	err = ioutil.WriteFile(filepath.Join(tmpDir, "providers.tf"), []byte(providersContent), 0644)
	require.NoError(t, err)

	// Parse the configuration
	config, err := terraform.ParseTerraformConfig(tmpDir)
	require.NoError(t, err)

	// Should have found 2 provider blocks
	assert.Len(t, config.ProviderBlocks, 2)
	
	// Check provider names
	for _, provider := range config.ProviderBlocks {
		assert.Equal(t, "aws", provider.Name)
		// One should have alias "east"
		if provider.Alias != "" {
			assert.Equal(t, "east", provider.Alias)
		}
	}
}