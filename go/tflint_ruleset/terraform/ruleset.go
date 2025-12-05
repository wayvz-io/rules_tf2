package terraform

import (
	"github.com/terraform-linters/tflint-plugin-sdk/tflint"
)

// RuleSet is the custom ruleset that injects our custom runner.
type RuleSet struct {
	tflint.BuiltinRuleSet
}

// NewRunner injects a custom runner
func (r *RuleSet) NewRunner(runner tflint.Runner) (tflint.Runner, error) {
	return NewRunner(runner), nil
}
