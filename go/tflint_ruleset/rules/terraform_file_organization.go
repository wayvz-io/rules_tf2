package rules

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/terraform-linters/tflint-plugin-sdk/hclext"
	"github.com/terraform-linters/tflint-plugin-sdk/tflint"
	"github.com/wayvz-io/rules_tf2/go/tflint_ruleset/terraform"
)

// TerraformFileOrganizationRule checks whether Terraform files follow standard organization
type TerraformFileOrganizationRule struct {
	tflint.DefaultRule
}

// NewTerraformFileOrganizationRule returns new rule with default attributes
func NewTerraformFileOrganizationRule() *TerraformFileOrganizationRule {
	return &TerraformFileOrganizationRule{}
}

// Name returns the rule name
func (r *TerraformFileOrganizationRule) Name() string {
	return "tf2_terraform_file_organization"
}

// Enabled returns whether the rule is enabled by default
func (r *TerraformFileOrganizationRule) Enabled() bool {
	return true
}

// Severity returns the rule severity
func (r *TerraformFileOrganizationRule) Severity() tflint.Severity {
	return tflint.WARNING
}

// Link returns the rule reference link
func (r *TerraformFileOrganizationRule) Link() string {
	return ""
}

// blockLocation represents where a block is and where it should be
type blockLocation struct {
	BlockType    string
	CurrentFile  string
	ExpectedFile string
	Labels       []string
	Range        hcl.Range
}

// Check validates Terraform file organization
func (r *TerraformFileOrganizationRule) Check(rr tflint.Runner) error {
	runner := rr.(*terraform.Runner)

	path, err := runner.GetModulePath()
	if err != nil {
		return err
	}
	if !path.IsRoot() {
		// This rule only evaluates root modules
		return nil
	}

	// Get all terraform blocks
	terraformBlocks, err := r.getTerraformBlocks(runner)
	if err != nil {
		return err
	}

	// Get all provider blocks
	providerBlocks, err := r.getProviderBlocks(runner)
	if err != nil {
		return err
	}

	// Get all variable blocks
	variableBlocks, err := r.getVariableBlocks(runner)
	if err != nil {
		return err
	}

	// Get all output blocks
	outputBlocks, err := r.getOutputBlocks(runner)
	if err != nil {
		return err
	}

	// Get all import blocks
	importBlocks, err := r.getImportBlocks(runner)
	if err != nil {
		return err
	}

	// Check each block type for misplacement
	for _, block := range terraformBlocks {
		if err := r.checkBlockPlacement(runner, block); err != nil {
			return err
		}
	}

	for _, block := range providerBlocks {
		if err := r.checkBlockPlacement(runner, block); err != nil {
			return err
		}
	}

	for _, block := range variableBlocks {
		if err := r.checkBlockPlacement(runner, block); err != nil {
			return err
		}
	}

	for _, block := range outputBlocks {
		if err := r.checkBlockPlacement(runner, block); err != nil {
			return err
		}
	}

	for _, block := range importBlocks {
		if err := r.checkBlockPlacement(runner, block); err != nil {
			return err
		}
	}

	return nil
}

// getTerraformBlocks retrieves all terraform blocks
func (r *TerraformFileOrganizationRule) getTerraformBlocks(runner tflint.Runner) ([]blockLocation, error) {
	files, err := runner.GetFiles()
	if err != nil {
		return nil, err
	}

	var locations []blockLocation
	for filename := range files {
		body, err := runner.GetFile(filename)
		if err != nil {
			continue
		}

		schema := &hclext.BodySchema{
			Blocks: []hclext.BlockSchema{
				{Type: "terraform"},
			},
		}

		content, diags := hclext.PartialContent(body.Body, schema)
		if diags.HasErrors() {
			continue
		}

		for _, block := range content.Blocks {
			locations = append(locations, blockLocation{
				BlockType:    "terraform",
				CurrentFile:  filepath.Base(filename),
				ExpectedFile: "terraform.tf",
				Range:        block.DefRange,
			})
		}
	}

	return locations, nil
}

// getProviderBlocks retrieves all provider blocks
func (r *TerraformFileOrganizationRule) getProviderBlocks(runner tflint.Runner) ([]blockLocation, error) {
	files, err := runner.GetFiles()
	if err != nil {
		return nil, err
	}

	var locations []blockLocation
	for filename := range files {
		body, err := runner.GetFile(filename)
		if err != nil {
			continue
		}

		schema := &hclext.BodySchema{
			Blocks: []hclext.BlockSchema{
				{
					Type:       "provider",
					LabelNames: []string{"name"},
				},
			},
		}

		content, diags := hclext.PartialContent(body.Body, schema)
		if diags.HasErrors() {
			continue
		}

		for _, block := range content.Blocks {
			locations = append(locations, blockLocation{
				BlockType:    "provider",
				CurrentFile:  filepath.Base(filename),
				ExpectedFile: "providers.tf",
				Labels:       block.Labels,
				Range:        block.DefRange,
			})
		}
	}

	return locations, nil
}

// getVariableBlocks retrieves all variable blocks
func (r *TerraformFileOrganizationRule) getVariableBlocks(runner tflint.Runner) ([]blockLocation, error) {
	files, err := runner.GetFiles()
	if err != nil {
		return nil, err
	}

	var locations []blockLocation
	for filename := range files {
		body, err := runner.GetFile(filename)
		if err != nil {
			continue
		}

		schema := &hclext.BodySchema{
			Blocks: []hclext.BlockSchema{
				{
					Type:       "variable",
					LabelNames: []string{"name"},
				},
			},
		}

		content, diags := hclext.PartialContent(body.Body, schema)
		if diags.HasErrors() {
			continue
		}

		for _, block := range content.Blocks {
			locations = append(locations, blockLocation{
				BlockType:    "variable",
				CurrentFile:  filepath.Base(filename),
				ExpectedFile: "variables.tf",
				Labels:       block.Labels,
				Range:        block.DefRange,
			})
		}
	}

	return locations, nil
}

// getOutputBlocks retrieves all output blocks
func (r *TerraformFileOrganizationRule) getOutputBlocks(runner tflint.Runner) ([]blockLocation, error) {
	files, err := runner.GetFiles()
	if err != nil {
		return nil, err
	}

	var locations []blockLocation
	for filename := range files {
		body, err := runner.GetFile(filename)
		if err != nil {
			continue
		}

		schema := &hclext.BodySchema{
			Blocks: []hclext.BlockSchema{
				{
					Type:       "output",
					LabelNames: []string{"name"},
				},
			},
		}

		content, diags := hclext.PartialContent(body.Body, schema)
		if diags.HasErrors() {
			continue
		}

		for _, block := range content.Blocks {
			locations = append(locations, blockLocation{
				BlockType:    "output",
				CurrentFile:  filepath.Base(filename),
				ExpectedFile: "outputs.tf",
				Labels:       block.Labels,
				Range:        block.DefRange,
			})
		}
	}

	return locations, nil
}

// getImportBlocks retrieves all import blocks
func (r *TerraformFileOrganizationRule) getImportBlocks(runner tflint.Runner) ([]blockLocation, error) {
	files, err := runner.GetFiles()
	if err != nil {
		return nil, err
	}

	var locations []blockLocation
	for filename := range files {
		body, err := runner.GetFile(filename)
		if err != nil {
			continue
		}

		schema := &hclext.BodySchema{
			Blocks: []hclext.BlockSchema{
				{Type: "import"},
			},
		}

		content, diags := hclext.PartialContent(body.Body, schema)
		if diags.HasErrors() {
			continue
		}

		for _, block := range content.Blocks {
			locations = append(locations, blockLocation{
				BlockType:    "import",
				CurrentFile:  filepath.Base(filename),
				ExpectedFile: "imports.tf",
				Range:        block.DefRange,
			})
		}
	}

	return locations, nil
}

// checkBlockPlacement checks if a block is in the correct file
func (r *TerraformFileOrganizationRule) checkBlockPlacement(runner tflint.Runner, block blockLocation) error {
	if block.CurrentFile == block.ExpectedFile {
		return nil // Block is in correct location
	}

	// Skip if in a subdirectory (like modules/)
	if strings.Contains(block.Range.Filename, "/modules/") {
		return nil
	}

	message := fmt.Sprintf("%s block should be in %s (currently in %s)",
		block.BlockType, block.ExpectedFile, block.CurrentFile)

	// Add label information for clarity
	if len(block.Labels) > 0 {
		message = fmt.Sprintf("%s %q should be in %s (currently in %s)",
			block.BlockType, strings.Join(block.Labels, "."), block.ExpectedFile, block.CurrentFile)
	}

	// Emit issue without autofix for now (autofix is more complex and will be added later)
	if err := runner.EmitIssue(
		r,
		message,
		block.Range,
	); err != nil {
		return err
	}

	return nil
}

// organizeBlocks performs the actual reorganization (for autofix)
// This will be implemented in a future iteration
func (r *TerraformFileOrganizationRule) organizeBlocks(runner tflint.Runner, blocks []blockLocation) error {
	// Group blocks by expected file
	fileBlocks := make(map[string][]blockLocation)
	for _, block := range blocks {
		fileBlocks[block.ExpectedFile] = append(fileBlocks[block.ExpectedFile], block)
	}

	// Sort blocks within each file for consistent output
	for filename, blocks := range fileBlocks {
		sort.Slice(blocks, func(i, j int) bool {
			// Sort by block type first, then by labels
			if blocks[i].BlockType != blocks[j].BlockType {
				return blocks[i].BlockType < blocks[j].BlockType
			}
			return strings.Join(blocks[i].Labels, ".") < strings.Join(blocks[j].Labels, ".")
		})
		fileBlocks[filename] = blocks
	}

	// TODO: Implement file reorganization logic
	// This would involve:
	// 1. Reading all blocks from current files
	// 2. Organizing them by expected file
	// 3. Writing them to the correct files
	// 4. Deleting files that only contained moved blocks

	return nil
}
