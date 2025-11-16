package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/terraform"
)

var reorganizeCmd = &cobra.Command{
	Use:   "reorganize <directory>",
	Short: "Reorganize Terraform files into standard structure",
	Long: `Reorganizes Terraform files in a directory to follow the standard structure:
- Consolidates all terraform blocks into terraform.tf
- Moves all provider blocks to providers.tf
- Moves all variable blocks to variables.tf
- Moves all output blocks to outputs.tf
- Moves all import blocks to imports.tf
- Preserves resources, data sources, locals, and modules in their original files
- Preserves comments associated with moved blocks`,
	Args: cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		dir := args[0]

		// Parse current configuration
		config, err := terraform.ParseTerraformConfig(dir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error parsing Terraform configuration: %v\n", err)
			os.Exit(1)
		}

		// Organize the configuration
		if err := terraform.OrganizeTerraformFiles(config); err != nil {
			fmt.Fprintf(os.Stderr, "Error organizing configuration: %v\n", err)
			os.Exit(1)
		}

		// Write reorganized files
		if err := terraform.WriteTerraformConfig(dir, config); err != nil {
			fmt.Fprintf(os.Stderr, "Error writing reorganized files: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("Successfully reorganized Terraform files in %s\n", dir)
		
		// List what was done
		if config.TerraformFile != "" {
			fmt.Println("  ✓ Consolidated terraform blocks into terraform.tf")
		}
		if config.ProvidersFile != "" {
			fmt.Println("  ✓ Moved provider blocks to providers.tf")
		}
		if config.VariablesFile != "" {
			fmt.Println("  ✓ Moved variable blocks to variables.tf")
		}
		if config.OutputsFile != "" {
			fmt.Println("  ✓ Moved output blocks to outputs.tf")
		}
		if config.ImportsFile != "" {
			fmt.Println("  ✓ Moved import blocks to imports.tf")
		}
		if len(config.FilesToDelete) > 0 {
			fmt.Println("  ✓ Cleaned up old files")
		}
	},
}

func init() {
	rootCmd.AddCommand(reorganizeCmd)
}