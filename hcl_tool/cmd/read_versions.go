package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"
	tfhcl "github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/hcl"
	"github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/terraform"
)

var readVersionsCmd = &cobra.Command{
	Use:   "read-versions [directory]",
	Short: "Read terraform version requirements from .tf files",
	Long: `Read terraform blocks from all .tf and .tf.json files in a directory
and output the combined version requirements as JSON.`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		dir := "."
		if len(args) > 0 {
			dir = args[0]
		}

		// Read versions from directory
		block, err := terraform.ReadVersionsFromDir(dir)
		if err != nil {
			return fmt.Errorf("failed to read versions: %w", err)
		}

		// Handle nil result (no terraform blocks found)
		if block == nil {
			block = &tfhcl.TerraformBlock{}
		}

		// Output as JSON
		output, err := json.MarshalIndent(block, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal JSON: %w", err)
		}

		fmt.Println(string(output))
		return nil
	},
}

func init() {
	rootCmd.AddCommand(readVersionsCmd)
}