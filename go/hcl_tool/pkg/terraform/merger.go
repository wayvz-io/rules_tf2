package terraform

import (
	"fmt"

	tfhcl "github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/hcl"
)

// MergeTerraformBlocks merges two terraform blocks, with the second block taking precedence
// for conflicting values, except for configuration_aliases which are always preserved
func MergeTerraformBlocks(existing, new *tfhcl.TerraformBlock) *tfhcl.TerraformBlock {
	if existing == nil {
		return new
	}
	if new == nil {
		return existing
	}

	result := &tfhcl.TerraformBlock{
		RequiredProviders: make(map[string]tfhcl.Provider),
	}

	// Merge required_version (first one wins - keeps original behavior)
	if existing.RequiredVersion != "" {
		result.RequiredVersion = existing.RequiredVersion
	} else if new.RequiredVersion != "" {
		result.RequiredVersion = new.RequiredVersion
	}

	// Start with existing providers
	for name, provider := range existing.RequiredProviders {
		result.RequiredProviders[name] = provider
	}

	// Merge new providers
	for name, newProvider := range new.RequiredProviders {
		if existingProvider, exists := result.RequiredProviders[name]; exists {
			// Merge the provider, preserving configuration_aliases
			result.RequiredProviders[name] = MergeProviders(existingProvider, newProvider)
		} else {
			// Add new provider
			result.RequiredProviders[name] = newProvider
		}
	}

	return result
}

// MergeProviders merges two provider configurations
// The existing provider takes precedence for source and version (first one wins),
// but configuration_aliases are always preserved from the existing provider
func MergeProviders(existing, new tfhcl.Provider) tfhcl.Provider {
	result := tfhcl.Provider{}

	// Existing source and version take precedence (first one wins)
	if existing.Source != "" {
		result.Source = existing.Source
	} else {
		result.Source = new.Source
	}

	if existing.Version != "" {
		result.Version = existing.Version
	} else {
		result.Version = new.Version
	}

	// Always preserve configuration_aliases from existing
	// unless new explicitly has them (which is rare in updates)
	if len(new.ConfigurationAliases) > 0 {
		result.ConfigurationAliases = new.ConfigurationAliases
	} else if len(existing.ConfigurationAliases) > 0 {
		result.ConfigurationAliases = existing.ConfigurationAliases
	}

	return result
}

// MergeWithUpdates merges providers from BUILD file with existing configuration
// This is specifically for the update-versions use case where we want to:
// 1. Update source and version from BUILD file (version differences are auto-updated)
// 2. Preserve configuration_aliases from existing file
// 3. Error if terraform.tf contains providers not declared in BUILD file (unless force=true)
func MergeWithUpdates(existing *tfhcl.TerraformBlock, updates map[string]tfhcl.Provider, tfVersion string, force bool) (*tfhcl.TerraformBlock, error) {
	result := &tfhcl.TerraformBlock{
		RequiredProviders: make(map[string]tfhcl.Provider),
	}

	// Set terraform version
	if tfVersion != "" {
		result.RequiredVersion = tfVersion
	} else if existing != nil {
		result.RequiredVersion = existing.RequiredVersion
	}

	// Start with providers from updates (BUILD file)
	for name, provider := range updates {
		result.RequiredProviders[name] = provider
	}

	// Check for providers in terraform.tf that aren't in BUILD file
	var missingProviders []string
	if existing != nil && existing.RequiredProviders != nil {
		for name, existingProvider := range existing.RequiredProviders {
			if updatedProvider, exists := result.RequiredProviders[name]; exists {
				// Provider exists in both - preserve configuration_aliases from existing
				if len(existingProvider.ConfigurationAliases) > 0 {
					updatedProvider.ConfigurationAliases = existingProvider.ConfigurationAliases
					result.RequiredProviders[name] = updatedProvider
				}
			} else {
				// Provider in terraform.tf but not in BUILD file
				missingProviders = append(missingProviders, name)
			}
		}
	}

	// Handle missing providers
	if len(missingProviders) > 0 {
		if !force {
			return nil, fmt.Errorf("terraform.tf contains providers not declared in BUILD file: %v\n\n"+
				"To fix this, either:\n"+
				"1. Add the missing providers to your BUILD file's 'providers' list\n"+
				"2. Add the providers to MODULE.bazel and run //:tf-update to sync to lockfile\n"+
				"3. Use --force flag to automatically remove these providers", missingProviders)
		}
		// force=true: silently skip missing providers (they won't be in result)
	}

	return result, nil
}