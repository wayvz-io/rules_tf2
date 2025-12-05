package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/spf13/cobra"
	tfhcl "github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/hcl"
	"github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/terraform"
)

var (
	updateForce bool
)

var updateVersionsCmd = &cobra.Command{
	Use:   "update-versions <directory>",
	Short: "Update Terraform versions in a directory to match expected values",
	Long: `Updates or creates terraform.tf in the specified directory with the
expected version requirements provided via JSON input.

Preserves configuration_aliases. By default, errors if terraform.tf contains
providers not declared in BUILD file. Use --force to automatically remove them.`,
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
		if err := terraform.UpdateVersionsInDir(dir, expected.RequiredProviders, expected.RequiredVersion, updateForce); err != nil {
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
	rootCmd.AddCommand(updateVersionsCmd)

	updateVersionsCmd.Flags().BoolVar(&updateForce, "force", false, "Automatically remove providers not in BUILD file")
}