package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/spf13/cobra"
	tfhcl "github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/hcl"
	"github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/terraform"
)

var tflintValidateVersionsCmd = &cobra.Command{
	Use:   "tflint-validate-versions <directory>",
	Short: "Validate Terraform versions and emit TFLint-compatible output",
	Long: `Validates that the Terraform version requirements in .tf files
match the expected values provided via JSON input. Outputs results in
TFLint-compatible format for integration with TFLint workflows.

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
			emitTFLintError("", fmt.Sprintf("Error reading expected versions from stdin: %v", err))
			os.Exit(1)
		}

		// Read actual versions from directory
		actual, err := terraform.ReadVersionsFromDir(dir)
		if err != nil {
			emitTFLintError("", fmt.Sprintf("Error reading versions from directory: %v", err))
			os.Exit(1)
		}

		// Validate versions
		result := terraform.ValidateVersions(actual, &expected)

		if !result.Valid {
			for _, errMsg := range result.Errors {
				// Version validation errors should reference terraform.tf since that's where versions should be defined
				emitTFLintError("terraform.tf", errMsg)
			}
			os.Exit(1)
		}

		fmt.Println("Version validation successful")
	},
}

var tflintValidateOrganizationCmd = &cobra.Command{
	Use:   "tflint-validate-organization <directory>",
	Short: "Validate Terraform file organization and emit TFLint-compatible output",
	Long: `Validates that Terraform files in a directory follow the standard organization
and outputs results in TFLint-compatible format for integration with TFLint workflows.

Exit codes:
  0 - Files are properly organized
  1 - Files need reorganization or error occurred`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		dir := args[0]

		// Parse current configuration
		current, err := terraform.ParseTerraformConfig(dir)
		if err != nil {
			emitTFLintError("", fmt.Sprintf("Error parsing Terraform configuration: %v", err))
			os.Exit(1)
		}

		// Check if reorganization is needed
		needsReorg, orgErrors := terraform.CheckOrganizationDetailed(current)

		if needsReorg {
			for _, err := range orgErrors {
				emitTFLintError(err.Filename, err.Message)
			}
			os.Exit(1)
		}

		fmt.Println("Terraform files are properly organized")
	},
}

// emitTFLintError outputs an error in TFLint-compatible format
func emitTFLintError(filename, message string) {
	if filename == "" {
		filename = "rules_tf2"
	}
	fmt.Fprintf(os.Stderr, "%s: %s\n", filename, message)
}

func init() {
	rootCmd.AddCommand(tflintValidateVersionsCmd)
	rootCmd.AddCommand(tflintValidateOrganizationCmd)
}