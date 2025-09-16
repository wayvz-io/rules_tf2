package terraform

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"path/filepath"
	"strings"

	"github.com/hashicorp/hcl/v2/hclparse"
	tfhcl "github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/hcl"
)

// ReadVersionsFromDir reads all terraform blocks from .tf files in a directory
func ReadVersionsFromDir(dir string) (*tfhcl.TerraformBlock, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.tf"))
	if err != nil {
		return nil, fmt.Errorf("failed to list .tf files: %w", err)
	}

	// Also check for .tf.json files
	jsonFiles, err := filepath.Glob(filepath.Join(dir, "*.tf.json"))
	if err == nil {
		files = append(files, jsonFiles...)
	}

	var result *tfhcl.TerraformBlock
	for _, file := range files {
		content, err := ioutil.ReadFile(file)
		if err != nil {
			continue
		}

		var block *tfhcl.TerraformBlock
		if strings.HasSuffix(file, ".json") {
			block, err = readVersionsFromJSON(content)
		} else {
			block, err = readVersionsFromHCL(content, file)
		}

		if err != nil || block == nil {
			continue
		}

		// Merge blocks
		result = MergeTerraformBlocks(result, block)
	}

	return result, nil
}

// readVersionsFromHCL parses terraform blocks from HCL content using declarative schemas
func readVersionsFromHCL(content []byte, filename string) (*tfhcl.TerraformBlock, error) {
	parser := hclparse.NewParser()
	file, diags := parser.ParseHCL(content, filename)
	if diags.HasErrors() {
		return nil, fmt.Errorf("failed to parse HCL: %s", diags.Error())
	}

	// Use the declarative schema-based decoder
	return tfhcl.DecodeTerraformBlock(file.Body)
}

// readVersionsFromJSON parses terraform blocks from JSON content
func readVersionsFromJSON(content []byte) (*tfhcl.TerraformBlock, error) {
	var data map[string]interface{}
	if err := json.Unmarshal(content, &data); err != nil {
		return nil, fmt.Errorf("failed to parse JSON: %w", err)
	}

	terraformData, ok := data["terraform"].(map[string]interface{})
	if !ok {
		return nil, nil // No terraform block
	}

	result := &tfhcl.TerraformBlock{}

	// Parse required_version
	if version, ok := terraformData["required_version"].(string); ok {
		result.RequiredVersion = version
	}

	// Parse required_providers
	if providers, ok := terraformData["required_providers"].(map[string]interface{}); ok {
		result.RequiredProviders = make(map[string]tfhcl.Provider)
		for name, providerData := range providers {
			provider := parseJSONProvider(providerData)
			if provider != nil {
				result.RequiredProviders[name] = *provider
			}
		}
	}

	return result, nil
}

// parseJSONProvider parses a provider from JSON data
func parseJSONProvider(data interface{}) *tfhcl.Provider {
	switch p := data.(type) {
	case string:
		// Simple version string
		return &tfhcl.Provider{
			Version: p,
		}
	case map[string]interface{}:
		// Object with source, version, and possibly configuration_aliases
		provider := &tfhcl.Provider{}
		if source, ok := p["source"].(string); ok {
			provider.Source = source
		}
		if version, ok := p["version"].(string); ok {
			provider.Version = version
		}
		if aliases, ok := p["configuration_aliases"].([]interface{}); ok {
			for _, alias := range aliases {
				if aliasStr, ok := alias.(string); ok {
					provider.ConfigurationAliases = append(provider.ConfigurationAliases, aliasStr)
				}
			}
		}
		return provider
	}
	return nil
}