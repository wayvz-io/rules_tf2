package cmd

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"

	"github.com/spf13/cobra"
	"github.com/wayvz-io/network_intent_manager/build/rules/tf2/hcl_tool/pkg/terraform"
)

var parseLockCmd = &cobra.Command{
	Use:   "parse-lock [file]",
	Short: "Parse a terraform.lock.hcl file and output JSON",
	Long: `Parse a terraform.lock.hcl file and output provider information as JSON.
This is useful for Bazel rules to consume lock file information.`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		var content []byte
		var err error

		if len(args) > 0 {
			// Read from file
			content, err = ioutil.ReadFile(args[0])
			if err != nil {
				return fmt.Errorf("failed to read file: %w", err)
			}
		} else {
			// Read from stdin
			content, err = ioutil.ReadAll(os.Stdin)
			if err != nil {
				return fmt.Errorf("failed to read stdin: %w", err)
			}
		}

		// Parse the lock file
		lockFile, err := terraform.ParseLockFile(content)
		if err != nil {
			return fmt.Errorf("failed to parse lock file: %w", err)
		}

		// Output as JSON
		output, err := json.MarshalIndent(lockFile, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal JSON: %w", err)
		}

		fmt.Println(string(output))
		return nil
	},
}

func init() {
	rootCmd.AddCommand(parseLockCmd)
}