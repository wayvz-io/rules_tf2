package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/terraform"
)

var validateOrganizationCmd = &cobra.Command{
	Use:   "validate-organization <directory>",
	Short: "Validate that Terraform files are properly organized",
	Long: `Validates that Terraform files in a directory follow the standard organization:
- All terraform blocks consolidated in terraform.tf
- All provider blocks in providers.tf  
- All variable blocks in variables.tf
- All output blocks in outputs.tf
- All import blocks in imports.tf
- Resources, data sources, locals, and modules remain in their original files

Exit codes:
  0 - Files are properly organized
  1 - Files need reorganization or error occurred`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		dir := args[0]

		// Parse current configuration
		current, err := terraform.ParseTerraformConfig(dir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error parsing Terraform configuration: %v\n", err)
			os.Exit(1)
		}

		// Check if reorganization is needed using the fixed function
		needsReorg, differences := terraform.CheckOrganization(current)

		if needsReorg {
			fmt.Fprintf(os.Stderr, "Terraform files need reorganization:\n")
			for _, diff := range differences {
				fmt.Fprintf(os.Stderr, "  - %s\n", diff)
			}
			fmt.Fprintf(os.Stderr, "\nRun 'bazel run //%s:%s_reorganize' to fix these issues\n", 
				os.Getenv("BUILD_WORKSPACE_DIRECTORY"), os.Getenv("BUILD_TARGET_NAME"))
			os.Exit(1)
		}

		fmt.Println("Terraform files are properly organized")
	},
}

func init() {
	rootCmd.AddCommand(validateOrganizationCmd)
}