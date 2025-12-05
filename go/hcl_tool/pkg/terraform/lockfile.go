package terraform

import (
	"fmt"
	"strings"

	"github.com/hashicorp/hcl/v2/hclparse"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	tfhcl "github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/hcl"
	"github.com/zclconf/go-cty/cty"
)

// ParseLockFile parses a terraform.lock.hcl file
func ParseLockFile(content []byte) (*tfhcl.LockFile, error) {
	parser := hclparse.NewParser()
	file, diags := parser.ParseHCL(content, "terraform.lock.hcl")
	if diags.HasErrors() {
		return nil, fmt.Errorf("failed to parse HCL: %s", diags.Error())
	}

	lockFile := &tfhcl.LockFile{
		Providers: make(map[string]tfhcl.LockFileProvider),
	}

	// Parse the body
	body, ok := file.Body.(*hclsyntax.Body)
	if !ok {
		// Try simple parsing for basic lock files
		return parseSimpleLockFile(string(content))
	}

	// Look for provider blocks
	for _, block := range body.Blocks {
		if block.Type == "provider" && len(block.Labels) > 0 {
			providerName := block.Labels[0]
			provider := tfhcl.LockFileProvider{}

			// Parse attributes
			attrs, diags := block.Body.JustAttributes()
			if !diags.HasErrors() {
				if versionAttr, exists := attrs["version"]; exists {
					val, _ := versionAttr.Expr.Value(nil)
					if val.Type() == cty.String {
						provider.Version = val.AsString()
					}
				}

				if constraintsAttr, exists := attrs["constraints"]; exists {
					val, _ := constraintsAttr.Expr.Value(nil)
					if val.Type() == cty.String {
						provider.Constraints = val.AsString()
					}
				}

				if hashesAttr, exists := attrs["hashes"]; exists {
					val, _ := hashesAttr.Expr.Value(nil)
					if val.Type().IsListType() || val.Type().IsTupleType() {
						provider.Hashes = []string{}
						it := val.ElementIterator()
						for it.Next() {
							_, v := it.Element()
							if v.Type() == cty.String {
								provider.Hashes = append(provider.Hashes, v.AsString())
							}
						}
					}
				}
			}

			lockFile.Providers[providerName] = provider
		}
	}

	return lockFile, nil
}

// parseSimpleLockFile provides a simple string-based parser as fallback
func parseSimpleLockFile(content string) (*tfhcl.LockFile, error) {
	lockFile := &tfhcl.LockFile{
		Providers: make(map[string]tfhcl.LockFileProvider),
	}

	lines := strings.Split(content, "\n")
	currentProvider := ""
	currentProviderData := tfhcl.LockFileProvider{}
	inHashes := false
	hashes := []string{}

	for _, line := range lines {
		line = strings.TrimSpace(line)

		// Check for provider block start
		if strings.HasPrefix(line, "provider \"") {
			// Save previous provider if exists
			if currentProvider != "" {
				if inHashes {
					currentProviderData.Hashes = hashes
				}
				lockFile.Providers[currentProvider] = currentProviderData
			}

			// Extract provider name
			parts := strings.Split(line, "\"")
			if len(parts) >= 2 {
				currentProvider = parts[1]
				currentProviderData = tfhcl.LockFileProvider{}
				inHashes = false
				hashes = []string{}
			}
		} else if currentProvider != "" {
			// Parse version
			if strings.HasPrefix(line, "version") {
				parts := strings.Split(line, "\"")
				if len(parts) >= 2 {
					currentProviderData.Version = parts[1]
				}
			}
			// Parse constraints
			if strings.HasPrefix(line, "constraints") {
				parts := strings.Split(line, "\"")
				if len(parts) >= 2 {
					currentProviderData.Constraints = parts[1]
				}
			}
			// Parse hashes
			if strings.HasPrefix(line, "hashes = [") {
				inHashes = true
				hashes = []string{}
			} else if inHashes {
				if strings.Contains(line, "]") {
					inHashes = false
					currentProviderData.Hashes = hashes
				} else if strings.Contains(line, "\"") {
					parts := strings.Split(line, "\"")
					if len(parts) >= 2 {
						hashes = append(hashes, parts[1])
					}
				}
			}
		}
	}

	// Save last provider
	if currentProvider != "" {
		if inHashes {
			currentProviderData.Hashes = hashes
		}
		lockFile.Providers[currentProvider] = currentProviderData
	}

	return lockFile, nil
}