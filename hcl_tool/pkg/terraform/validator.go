package terraform

import (
	"fmt"
	
	tfhcl "github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/hcl"
)

// ValidationResult holds the result of validating terraform versions
type ValidationResult struct {
	Valid  bool
	Errors []string
}

// ValidateVersions validates that actual terraform versions match expected values
// Note: configuration_aliases are intentionally not validated as they are user-defined
func ValidateVersions(actual, expected *tfhcl.TerraformBlock) ValidationResult {
	result := ValidationResult{Valid: true}

	// Handle nil blocks
	if actual == nil {
		actual = &tfhcl.TerraformBlock{}
	}
	if expected == nil {
		expected = &tfhcl.TerraformBlock{}
	}

	// Validate required_version
	if expected.RequiredVersion != "" && expected.RequiredVersion != actual.RequiredVersion {
		result.Valid = false
		if actual.RequiredVersion == "" {
			result.Errors = append(result.Errors, 
				fmt.Sprintf("Missing required_version (expected: %s)", expected.RequiredVersion))
		} else {
			result.Errors = append(result.Errors,
				fmt.Sprintf("Incorrect required_version (expected: %s, found: %s)",
					expected.RequiredVersion, actual.RequiredVersion))
		}
	}

	// Validate required_providers
	if expected.RequiredProviders != nil {
		if actual.RequiredProviders == nil {
			result.Valid = false
			result.Errors = append(result.Errors, "Missing required_providers block")
		} else {
			// Check each expected provider
			for name, expectedProvider := range expected.RequiredProviders {
				actualProvider, exists := actual.RequiredProviders[name]
				if !exists {
					result.Valid = false
					result.Errors = append(result.Errors,
						fmt.Sprintf("Missing provider '%s' (expected version: %s)",
							name, expectedProvider.Version))
				} else {
					// Validate version
					if expectedProvider.Version != actualProvider.Version {
						result.Valid = false
						result.Errors = append(result.Errors,
							fmt.Sprintf("Incorrect version for provider '%s' (expected: %s, found: %s)",
								name, expectedProvider.Version, actualProvider.Version))
					}
					// Validate source
					if expectedProvider.Source != "" && expectedProvider.Source != actualProvider.Source {
						result.Valid = false
						result.Errors = append(result.Errors,
							fmt.Sprintf("Incorrect source for provider '%s' (expected: %s, found: %s)",
								name, expectedProvider.Source, actualProvider.Source))
					}
					// Note: configuration_aliases are intentionally NOT validated
					// They are user-defined and should be preserved, not validated against BUILD files
				}
			}

			// Check for unexpected providers
			for name := range actual.RequiredProviders {
				if _, expected := expected.RequiredProviders[name]; !expected {
					result.Valid = false
					result.Errors = append(result.Errors,
						fmt.Sprintf("Unexpected provider '%s' found (not defined in BUILD file)", name))
				}
			}
		}
	}

	return result
}