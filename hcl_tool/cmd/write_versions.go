package cmd

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"strings"

	"github.com/spf13/cobra"
	tfhcl "github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/hcl"
	"github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/terraform"
)

var (
	writeDir        string
	writeLockFile   string
	writeProviders  string
	writeTfVersion  string
	writeOutputFile string
)

var writeVersionsCmd = &cobra.Command{
	Use:   "write-versions",
	Short: "Write or update terraform version requirements",
	Long: `Write or update terraform blocks in .tf files based on provider requirements.
This will create a versions.tf file or update an existing one.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// Parse providers from JSON or lock file
		providers := make(map[string]tfhcl.Provider)

		if writeLockFile != "" {
			// Parse from lock file
			content, err := ioutil.ReadFile(writeLockFile)
			if err != nil {
				return fmt.Errorf("failed to read lock file: %w", err)
			}

			lockFile, err := terraform.ParseLockFile(content)
			if err != nil {
				return fmt.Errorf("failed to parse lock file: %w", err)
			}

			// Convert lock file providers to required providers
			for name, provider := range lockFile.Providers {
				providers[getProviderShortName(name)] = tfhcl.Provider{
					Source:  name,
					Version: provider.Version,
				}
			}
		} else if writeProviders != "" {
			// Parse from JSON string
			if err := json.Unmarshal([]byte(writeProviders), &providers); err != nil {
				return fmt.Errorf("failed to parse providers JSON: %w", err)
			}
		}

		// Determine terraform version
		tfVersion := writeTfVersion
		if tfVersion == "" {
			tfVersion = ">= 1.0"
		}

		// Update versions in directory
		if writeOutputFile != "" {
			// Write to specific file
			block := &tfhcl.TerraformBlock{
				RequiredVersion:   tfVersion,
				RequiredProviders: providers,
			}
			return terraform.WriteVersionsToFile(writeOutputFile, block)
		} else {
			// Update in directory
			return terraform.UpdateVersionsInDir(writeDir, providers, tfVersion)
		}
	},
}

// getProviderShortName extracts the short name from a full provider source
// e.g., "registry.terraform.io/hashicorp/aws" -> "aws"
func getProviderShortName(source string) string {
	// Simple approach: get the last part after splitting by /
	parts := strings.Split(source, "/")
	if len(parts) > 0 {
		return parts[len(parts)-1]
	}
	return source
}

func init() {
	rootCmd.AddCommand(writeVersionsCmd)

	writeVersionsCmd.Flags().StringVar(&writeDir, "dir", ".", "Directory to write versions file to")
	writeVersionsCmd.Flags().StringVar(&writeLockFile, "lock-file", "", "Path to terraform.lock.hcl file")
	writeVersionsCmd.Flags().StringVar(&writeProviders, "providers", "", "JSON object of provider requirements")
	writeVersionsCmd.Flags().StringVar(&writeTfVersion, "tf-version", "", "Terraform version constraint")
	writeVersionsCmd.Flags().StringVar(&writeOutputFile, "output", "", "Specific output file (overrides dir)")
}