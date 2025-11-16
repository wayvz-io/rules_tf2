package cmd

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/spf13/cobra"
	tfhcl "github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/hcl"
)

var (
	versionsFile string
	lockOutputFile string
)

var extractModuleLockCmd = &cobra.Command{
	Use:   "extract-module-lock [uber-lock-json]",
	Short: "Extract module-specific lock file from a central uber lock",
	Long:  `Extract a module-specific terraform.lock.hcl from a central repository-wide lock file.

This command is used in monorepo setups where there's a central "uber" lock file 
containing hashes for all providers used across the entire repository. It extracts 
only the providers your specific module needs based on its versions.json file.

Inputs:
  - versions.json: Specifies which providers and versions your module needs (via --versions flag)
  - uber-lock.json: Central lock file containing hashes for all providers

Output: terraform.lock.hcl with only the providers your module requires`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		// Read versions file
		versionsContent, err := os.ReadFile(versionsFile)
		if err != nil {
			return fmt.Errorf("failed to read versions file %s: %w", versionsFile, err)
		}

		// Parse versions.json to extract provider sources
		var versions struct {
			RequiredProviders map[string]struct {
				Source  string `json:"source"`
				Version string `json:"version"`
			} `json:"required_providers"`
		}
		if err := json.Unmarshal(versionsContent, &versions); err != nil {
			return fmt.Errorf("failed to parse versions.json: %w", err)
		}

		// Extract provider sources with versions for precise matching
		var filterList []string
		for _, provider := range versions.RequiredProviders {
			if provider.Source != "" && provider.Version != "" {
				// Create provider:version key to match uber lock format
				filterList = append(filterList, provider.Source+":"+provider.Version)
			}
		}

		// Read uber lock file
		uberLockContent, err := os.ReadFile(args[0])
		if err != nil {
			return fmt.Errorf("failed to read uber lock file %s: %w", args[0], err)
		}

		// Parse uber lock JSON with new structure
		// Keys are now "provider:version" and values have {provider, version, hashes}
		var uberLock map[string]struct {
			Provider string   `json:"provider"`
			Version  string   `json:"version"`
			Hashes   []string `json:"hashes"`
		}
		if err := json.Unmarshal(uberLockContent, &uberLock); err != nil {
			return fmt.Errorf("failed to parse uber lock JSON: %w", err)
		}

		// Filter providers by exact provider:version match
		filteredProviders := make(map[string]tfhcl.LockFileProvider)
		for _, providerVersionKey := range filterList {
			if lockData, ok := uberLock[providerVersionKey]; ok {
				// Convert to expected format for HCL generation
				filteredProviders[lockData.Provider] = tfhcl.LockFileProvider{
					Version: lockData.Version,
					Hashes:  lockData.Hashes,
				}
			}
		}

		// Generate HCL
		lockFile := tfhcl.LockFile{
			Providers: filteredProviders,
		}
		
		hcl := generateLockHCL(&lockFile)

		// Write output
		var output io.Writer = os.Stdout
		if lockOutputFile != "" && lockOutputFile != "-" {
			file, err := os.Create(lockOutputFile)
			if err != nil {
				return fmt.Errorf("failed to create output file %s: %w", lockOutputFile, err)
			}
			defer file.Close()
			output = file
		}

		if _, err := fmt.Fprint(output, hcl); err != nil {
			return fmt.Errorf("failed to write output: %w", err)
		}

		return nil
	},
}

func generateLockHCL(lockFile *tfhcl.LockFile) string {
	var lines []string
	
	// Add header
	lines = append(lines, 
		`# This file is maintained automatically by "terraform init".`,
		`# Manual edits may be lost in future updates.`,
		``,
	)
	
	// Sort providers for consistent output
	var providers []string
	for name := range lockFile.Providers {
		providers = append(providers, name)
	}
	sort.Strings(providers)
	
	// Generate provider blocks
	for _, name := range providers {
		data := lockFile.Providers[name]
		
		// Ensure we have the full registry path
		fullName := name
		if !strings.HasPrefix(fullName, "registry.terraform.io/") {
			fullName = "registry.terraform.io/" + fullName
		}
		
		lines = append(lines, fmt.Sprintf(`provider "%s" {`, fullName))
		
		// Use Version if present, otherwise use Constraints
		version := data.Version
		if version == "" && data.Constraints != "" {
			version = data.Constraints
		}
		
		if version != "" {
			lines = append(lines, fmt.Sprintf(`  version     = "%s"`, version))
		}
		
		if data.Constraints != "" {
			lines = append(lines, fmt.Sprintf(`  constraints = "%s"`, data.Constraints))
		}
		
		if len(data.Hashes) > 0 {
			lines = append(lines, `  hashes = [`)
			for _, hash := range data.Hashes {
				lines = append(lines, fmt.Sprintf(`    "%s",`, hash))
			}
			lines = append(lines, `  ]`)
		}
		
		lines = append(lines, `}`, ``)
	}
	
	return strings.Join(lines, "\n")
}

func init() {
	extractModuleLockCmd.Flags().StringVar(&versionsFile, "versions", "", "Path to versions.json file specifying module's provider requirements")
	extractModuleLockCmd.Flags().StringVarP(&lockOutputFile, "output", "o", "-", "Output file (default: stdout)")
	extractModuleLockCmd.MarkFlagRequired("versions")
	rootCmd.AddCommand(extractModuleLockCmd)
}