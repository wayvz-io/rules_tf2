package main

import (
	"github.com/terraform-linters/tflint-plugin-sdk/plugin"
	"github.com/terraform-linters/tflint-plugin-sdk/tflint"
	"github.com/wayvz-io/rules_tf2/go/tflint_ruleset/rules"
	"github.com/wayvz-io/rules_tf2/go/tflint_ruleset/terraform"
)

func main() {
	plugin.Serve(&plugin.ServeOpts{
		RuleSet: &terraform.RuleSet{
			BuiltinRuleSet: tflint.BuiltinRuleSet{
				Name:    "tf2",
				Version: "0.1.0",
				Rules: []tflint.Rule{
					rules.NewTerraformRequiredProvidersRule(),
					rules.NewTerraformFileOrganizationRule(),
				},
			},
		},
	})
}
