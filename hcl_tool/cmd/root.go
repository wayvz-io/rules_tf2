package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "hcl_tool",
	Short: "HCL manipulation tool for Terraform files",
	Long: `A tool for reading and writing HCL files, specifically designed
for managing Terraform version requirements and lock files.

This tool provides commands to:
- Parse terraform.lock.hcl files to JSON
- Read version requirements from .tf files
- Write/update version requirements in .tf files`,
}

// Execute runs the root command
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}