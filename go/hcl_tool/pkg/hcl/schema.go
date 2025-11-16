package hcl

import (
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/gohcl"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/hashicorp/hcl/v2/hclwrite"
	"github.com/zclconf/go-cty/cty"
)

// ProviderExpression represents a provider configuration with proper handling of configuration_aliases
type ProviderExpression struct {
	Source               string         `hcl:"source,optional"`
	Version              string         `hcl:"version,optional"`
	ConfigurationAliases hcl.Expression `hcl:"configuration_aliases,optional"`
}

// GetTerraformBlockSchema returns the HCL schema for terraform blocks
func GetTerraformBlockSchema() *hcl.BodySchema {
	return &hcl.BodySchema{
		Blocks: []hcl.BlockHeaderSchema{
			{
				Type: "terraform",
			},
		},
	}
}

// GetTerraformContentSchema returns the schema for the content of a terraform block
func GetTerraformContentSchema() *hcl.BodySchema {
	return &hcl.BodySchema{
		Attributes: []hcl.AttributeSchema{
			{Name: "required_version"},
		},
		Blocks: []hcl.BlockHeaderSchema{
			{Type: "required_providers"},
		},
	}
}

// DecodeTerraformBlock decodes a terraform block from HCL body using schemas
func DecodeTerraformBlock(body hcl.Body) (*TerraformBlock, error) {
	// First, get the terraform blocks
	content, _, diags := body.PartialContent(GetTerraformBlockSchema())
	if diags.HasErrors() {
		return nil, diags
	}

	if len(content.Blocks) == 0 {
		return nil, nil // No terraform block found
	}

	result := &TerraformBlock{
		RequiredProviders: make(map[string]Provider),
	}

	// Process each terraform block (usually just one)
	for _, tfBlock := range content.Blocks {
		// Get the content of the terraform block
		tfContent, _, diags := tfBlock.Body.PartialContent(GetTerraformContentSchema())
		if diags.HasErrors() {
			continue
		}

		// Parse required_version
		if attr, exists := tfContent.Attributes["required_version"]; exists {
			diags := gohcl.DecodeExpression(attr.Expr, nil, &result.RequiredVersion)
			if diags.HasErrors() {
				// Fallback to direct evaluation
				val, _ := attr.Expr.Value(nil)
				if val.Type().Equals(cty.String) {
					result.RequiredVersion = val.AsString()
				}
			}
		}

		// Parse required_providers block
		for _, rpBlock := range tfContent.Blocks {
			if rpBlock.Type != "required_providers" {
				continue
			}

			// Decode providers
			providers, err := DecodeProviders(rpBlock.Body)
			if err == nil {
				for name, provider := range providers {
					result.RequiredProviders[name] = provider
				}
			}
		}
	}

	return result, nil
}

// DecodeProviders decodes provider configurations from a required_providers block
func DecodeProviders(body hcl.Body) (map[string]Provider, error) {
	attrs, diags := body.JustAttributes()
	if diags.HasErrors() {
		return nil, diags
	}

	providers := make(map[string]Provider)
	
	for name, attr := range attrs {
		provider, err := DecodeProviderExpression(attr.Expr)
		if err == nil {
			providers[name] = provider
		}
	}

	return providers, nil
}

// DecodeProviderExpression decodes a provider configuration from an HCL expression
func DecodeProviderExpression(expr hcl.Expression) (Provider, error) {
	provider := Provider{}

	// Try to decode as a simple string (version only)
	var version string
	diags := gohcl.DecodeExpression(expr, nil, &version)
	if !diags.HasErrors() {
		provider.Version = version
		return provider, nil
	}

	// Try to decode as an object with proper handling of configuration_aliases
	if objExpr, ok := expr.(*hclsyntax.ObjectConsExpr); ok {
		for _, item := range objExpr.Items {
			// Get the key
			key, diags := item.KeyExpr.Value(nil)
			if diags.HasErrors() || !key.Type().Equals(cty.String) {
				continue
			}

			switch key.AsString() {
			case "source":
				val, diags := item.ValueExpr.Value(nil)
				if !diags.HasErrors() && val.Type().Equals(cty.String) {
					provider.Source = val.AsString()
				}
			case "version":
				val, diags := item.ValueExpr.Value(nil)
				if !diags.HasErrors() && val.Type().Equals(cty.String) {
					provider.Version = val.AsString()
				}
			case "configuration_aliases":
				// Parse as tuple of traversals
				aliases := ParseConfigurationAliases(item.ValueExpr)
				if len(aliases) > 0 {
					provider.ConfigurationAliases = aliases
				}
			}
		}
		return provider, nil
	}

	// Try to evaluate as object value for other expression types
	val, diags := expr.Value(nil)
	if !diags.HasErrors() && val.Type().IsObjectType() {
		if val.Type().HasAttribute("source") {
			sourceVal := val.GetAttr("source")
			if !sourceVal.IsNull() && sourceVal.Type().Equals(cty.String) {
				provider.Source = sourceVal.AsString()
			}
		}
		if val.Type().HasAttribute("version") {
			versionVal := val.GetAttr("version")
			if !versionVal.IsNull() && versionVal.Type().Equals(cty.String) {
				provider.Version = versionVal.AsString()
			}
		}
	}

	return provider, nil
}

// ParseConfigurationAliases parses configuration_aliases from an HCL expression
func ParseConfigurationAliases(expr hcl.Expression) []string {
	var aliases []string

	// Handle tuple expressions (the common case)
	if tupleExpr, ok := expr.(*hclsyntax.TupleConsExpr); ok {
		for _, elemExpr := range tupleExpr.Exprs {
			if alias := ParseTraversal(elemExpr); alias != "" {
				aliases = append(aliases, alias)
			}
		}
	}

	return aliases
}

// ParseTraversal parses a traversal expression into a string representation
func ParseTraversal(expr hcl.Expression) string {
	if travExpr, ok := expr.(*hclsyntax.ScopeTraversalExpr); ok {
		var parts []string
		for _, step := range travExpr.Traversal {
			switch s := step.(type) {
			case hcl.TraverseRoot:
				parts = append(parts, s.Name)
			case hcl.TraverseAttr:
				parts = append(parts, s.Name)
			}
		}
		if len(parts) > 0 {
			return strings.Join(parts, ".")
		}
	}
	return ""
}

// Helper function to create a traversal expression from a string
func CreateTraversalTokens(aliases []string) hclwrite.Tokens {
	if len(aliases) == 0 {
		return nil
	}

	var tokens hclwrite.Tokens
	tokens = append(tokens, &hclwrite.Token{
		Type:  hclsyntax.TokenOBrack,
		Bytes: []byte("["),
	})

	for i, alias := range aliases {
		if i > 0 {
			tokens = append(tokens, &hclwrite.Token{
				Type:  hclsyntax.TokenComma,
				Bytes: []byte(","),
			})
			tokens = append(tokens, &hclwrite.Token{
				Type:  hclsyntax.TokenNil,
				Bytes: []byte(" "),
			})
		}

		// Add the traversal without quotes
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

	return tokens
}