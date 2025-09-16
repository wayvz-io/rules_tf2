package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/spf13/cobra"
	tfhcl "github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/hcl"
	"github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/terraform"
)

var validateVersionsCmd = &cobra.Command{
	Use:   "validate-versions <directory>",
	Short: "Validate Terraform versions in a directory match expected values",
	Long: `Validates that the Terraform version requirements in .tf files
match the expected values provided via JSON input.

The command reads version requirements from all .tf files in the specified
directory and compares them against expected values provided as JSON on stdin.

Exit codes:
  0 - Versions match expected values
  1 - Versions do not match or error occurred`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		dir := args[0]

		// Read expected versions from stdin
		var expected tfhcl.TerraformBlock
		decoder := json.NewDecoder(os.Stdin)
		if err := decoder.Decode(&expected); err != nil {
			fmt.Fprintf(os.Stderr, "Error reading expected versions from stdin: %v\n", err)
			os.Exit(1)
		}

		// Read actual versions from directory
		actual, err := terraform.ReadVersionsFromDir(dir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading versions from directory: %v\n", err)
			os.Exit(1)
		}

		// Validate versions
		result := terraform.ValidateVersions(actual, &expected)
		
		if !result.Valid {
			fmt.Fprintf(os.Stderr, "Version validation failed:\n")
			for _, err := range result.Errors {
				fmt.Fprintf(os.Stderr, "  - %s\n", err)
			}
			fmt.Fprintf(os.Stderr, "\n")
			
			// Output a summary of what was expected vs found
			fmt.Fprintf(os.Stderr, "Expected configuration:\n")
			expectedJSON, _ := json.MarshalIndent(expected, "  ", "  ")
			fmt.Fprintf(os.Stderr, "  %s\n", expectedJSON)
			
			fmt.Fprintf(os.Stderr, "\nActual configuration found:\n")
			actualJSON, _ := json.MarshalIndent(actual, "  ", "  ")
			fmt.Fprintf(os.Stderr, "  %s\n", actualJSON)
			
			os.Exit(1)
		}

		fmt.Println("Version validation successful")
	},
}

var updateVersionsCmd = &cobra.Command{
	Use:   "update-versions <directory>",
	Short: "Update Terraform versions in a directory to match expected values",
	Long: `Updates or creates terraform.tf in the specified directory with the
expected version requirements provided via JSON input.

Preserves configuration_aliases and custom providers not defined in the input.`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		dir := args[0]

		// Read expected versions from stdin
		var expected tfhcl.TerraformBlock
		decoder := json.NewDecoder(os.Stdin)
		if err := decoder.Decode(&expected); err != nil {
			fmt.Fprintf(os.Stderr, "Error reading expected versions from stdin: %v\n", err)
			os.Exit(1)
		}

		// Update versions in directory
		if err := terraform.UpdateVersionsInDir(dir, expected.RequiredProviders, expected.RequiredVersion); err != nil {
			fmt.Fprintf(os.Stderr, "Error updating versions: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("Successfully updated versions in %s\n", dir)
		if expected.RequiredVersion != "" {
			fmt.Printf("  Terraform version: %s\n", expected.RequiredVersion)
		}
		if len(expected.RequiredProviders) > 0 {
			fmt.Printf("  Providers:\n")
			for name, provider := range expected.RequiredProviders {
				if provider.Source != "" {
					fmt.Printf("    - %s: %s (%s)\n", name, provider.Version, provider.Source)
				} else {
					fmt.Printf("    - %s: %s\n", name, provider.Version)
				}
			}
		}
	},
}

func init() {
	rootCmd.AddCommand(validateVersionsCmd)
	rootCmd.AddCommand(updateVersionsCmd)
}