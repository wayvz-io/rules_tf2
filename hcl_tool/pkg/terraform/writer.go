package terraform

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/hashicorp/hcl/v2/hclwrite"
	tfhcl "github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/hcl"
	"github.com/zclconf/go-cty/cty"
)

// WriteVersionsToFile writes a terraform block to a file
func WriteVersionsToFile(filename string, block *tfhcl.TerraformBlock) error {
	if strings.HasSuffix(filename, ".json") {
		return writeVersionsToJSON(filename, block)
	}
	return writeVersionsToHCL(filename, block)
}

// writeVersionsToHCL writes terraform block to HCL file
func writeVersionsToHCL(filename string, block *tfhcl.TerraformBlock) error {
	var f *hclwrite.File
	
	// Try to read and parse existing file to preserve other content
	existingContent, err := ioutil.ReadFile(filename)
	if err == nil && len(existingContent) > 0 {
		// File exists, try to parse it
		var parseErr error
		f, parseErr = hclwrite.ParseConfig(existingContent, filename, hcl.InitialPos)
		if parseErr != nil {
			// If we can't parse it, create a new file
			f = hclwrite.NewEmptyFile()
		}
	} else {
		// File doesn't exist, create new
		f = hclwrite.NewEmptyFile()
	}

	rootBody := f.Body()
	
	// Find existing terraform block if any
	var existingTfBlock *hclwrite.Block
	for _, block := range rootBody.Blocks() {
		if block.Type() == "terraform" {
			existingTfBlock = block
			break
		}
	}
	
	// If terraform block exists, update it; otherwise create new
	var tfBody *hclwrite.Body
	if existingTfBlock != nil {
		tfBody = existingTfBlock.Body()
	} else {
		tfBlock := rootBody.AppendNewBlock("terraform", nil)
		tfBody = tfBlock.Body()
	}

	// Add or update required_version if present
	if block.RequiredVersion != "" {
		tfBody.SetAttributeValue("required_version", cty.StringVal(block.RequiredVersion))
	}

	// Add or update required_providers if present
	if len(block.RequiredProviders) > 0 {
		// Remove existing required_providers block if any
		for _, b := range tfBody.Blocks() {
			if b.Type() == "required_providers" {
				tfBody.RemoveBlock(b)
				break
			}
		}
		
		// Add new required_providers block
		providersBlock := tfBody.AppendNewBlock("required_providers", nil)
		providersBody := providersBlock.Body()

		for name, provider := range block.RequiredProviders {
			writeProvider(providersBody, name, provider)
		}
	}

	// Write to file
	return ioutil.WriteFile(filename, f.Bytes(), 0644)
}

// writeProvider writes a single provider configuration to the HCL body
func writeProvider(body *hclwrite.Body, name string, provider tfhcl.Provider) {
	if provider.Source != "" {
		// Provider with source (and possibly configuration_aliases)
		if len(provider.ConfigurationAliases) > 0 {
			// Build HCL with configuration_aliases as traversals
			tokens := buildProviderTokens(provider)
			body.SetAttributeRaw(name, tokens)
		} else {
			// Simple object without configuration_aliases
			providerMap := map[string]cty.Value{
				"source":  cty.StringVal(provider.Source),
				"version": cty.StringVal(provider.Version),
			}
			body.SetAttributeValue(name, cty.ObjectVal(providerMap))
		}
	} else {
		// Simple version string
		body.SetAttributeValue(name, cty.StringVal(provider.Version))
	}
}

// buildProviderTokens builds HCL tokens for a provider with configuration_aliases
func buildProviderTokens(provider tfhcl.Provider) hclwrite.Tokens {
	// Build the provider configuration as HCL tokens
	// This ensures configuration_aliases are written as traversals, not strings
	var tokens hclwrite.Tokens

	// Opening brace
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenOBrace,
		Bytes: []byte("{"),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenNewline,
		Bytes: []byte("\n"),
	})

	// Add source
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenIdent,
		Bytes: []byte("    source"),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenEqual,
		Bytes: []byte(" = "),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenOQuote,
		Bytes: []byte("\""),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenQuotedLit,
		Bytes: []byte(provider.Source),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenCQuote,
		Bytes: []byte("\""),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenNewline,
		Bytes: []byte("\n"),
	})

	// Add version
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenIdent,
		Bytes: []byte("    version"),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenEqual,
		Bytes: []byte(" = "),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenOQuote,
		Bytes: []byte("\""),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenQuotedLit,
		Bytes: []byte(provider.Version),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenCQuote,
		Bytes: []byte("\""),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenNewline,
		Bytes: []byte("\n"),
	})

	// Add configuration_aliases as traversals
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenIdent,
		Bytes: []byte("    configuration_aliases"),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenEqual,
		Bytes: []byte(" = "),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenOBrack,
		Bytes: []byte("["),
	})

	for i, alias := range provider.ConfigurationAliases {
		if i > 0 {
			tokens = append(tokens, &hclwrite.Token{
				Type:  hclsyntax.TokenComma,
				Bytes: []byte(", "),
			})
		}
		// Add traversal parts
		parts := strings.Split(alias, ".")
		for j, part := range parts {
			if j > 0 {
				tokens = append(tokens, &hclwrite.Token{
					Type:  hclsyntax.TokenDot,
					Bytes: []byte("."),
				})
			}
			tokens = append(tokens, &hclwrite.Token{
				Type:  hclsyntax.TokenIdent,
				Bytes: []byte(part),
			})
		}
	}

	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenCBrack,
		Bytes: []byte("]"),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenNewline,
		Bytes: []byte("\n"),
	})

	// Closing brace
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenIdent,
		Bytes: []byte("  "),
	})
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenCBrace,
		Bytes: []byte("}"),
	})

	return tokens
}

// writeVersionsToJSON writes terraform block to JSON file
func writeVersionsToJSON(filename string, block *tfhcl.TerraformBlock) error {
	data := map[string]interface{}{
		"terraform": block,
	}

	content, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal JSON: %w", err)
	}

	return ioutil.WriteFile(filename, content, 0644)
}

// UpdateVersionsInDir updates or creates terraform.tf in a directory
func UpdateVersionsInDir(dir string, providers map[string]tfhcl.Provider, tfVersion string, force bool) error {
	// Read existing versions
	existing, _ := ReadVersionsFromDir(dir)

	// Merge with updates, preserving configuration_aliases
	block, err := MergeWithUpdates(existing, providers, tfVersion, force)
	if err != nil {
		return err
	}

	// Determine output file
	// Check if there's an existing file with terraform blocks
	outputFile := ""
	possibleFiles := []string{"terraform.tf", "versions.tf", "main.tf"}
	for _, filename := range possibleFiles {
		fullPath := filepath.Join(dir, filename)
		if _, err := os.Stat(fullPath); err == nil {
			// File exists, check if it has terraform blocks
			content, err := ioutil.ReadFile(fullPath)
			if err == nil && strings.Contains(string(content), "terraform {") {
				outputFile = fullPath
				break
			}
		}
	}
	
	// If no existing terraform file found, use terraform.tf as default
	if outputFile == "" {
		outputFile = filepath.Join(dir, "terraform.tf")
	}

	return WriteVersionsToFile(outputFile, block)
}