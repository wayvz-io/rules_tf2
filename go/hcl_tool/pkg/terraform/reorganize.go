package terraform

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclparse"
	"github.com/hashicorp/hcl/v2/hclwrite"
	tfhcl "github.com/wayvz-io/rules_tf2/go/hcl_tool/pkg/hcl"
)

// ParseTerraformConfig reads all .tf files in a directory and parses them into a ModuleOrganization
func ParseTerraformConfig(dir string) (*tfhcl.ModuleOrganization, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.tf"))
	if err != nil {
		return nil, fmt.Errorf("failed to list .tf files: %w", err)
	}

	config := &tfhcl.ModuleOrganization{
		PreservedFiles: make(map[string]string),
	}

	for _, file := range files {
		// Skip .tf.json files for now
		if strings.HasSuffix(file, ".tf.json") {
			continue
		}

		content, err := ioutil.ReadFile(file)
		if err != nil {
			return nil, fmt.Errorf("failed to read %s: %w", file, err)
		}

		// Parse the file to extract blocks
		if err := parseFileContent(config, filepath.Base(file), content); err != nil {
			return nil, fmt.Errorf("failed to parse %s: %w", file, err)
		}
	}

	return config, nil
}

// parseFileContent parses HCL content and categorizes blocks
func parseFileContent(config *tfhcl.ModuleOrganization, filename string, content []byte) error {
	parser := hclparse.NewParser()
	_, diags := parser.ParseHCL(content, filename)
	if diags.HasErrors() {
		return fmt.Errorf("HCL parse error: %s", diags.Error())
	}

	// Parse using hclwrite to preserve formatting and comments
	writeFile, diags := hclwrite.ParseConfig(content, filename, hcl.InitialPos)
	if diags.HasErrors() {
		return fmt.Errorf("HCL write parse error: %s", diags.Error())
	}

	// Get the raw tokens to extract comments
	tokens := writeFile.BuildTokens(nil)
	
	// Track blocks that should be preserved in original files
	var preservedBlocks []string
	
	// Track if blocks are being moved from this file
	hasMovedBlocks := false
	
	// Special handling for versions.tf - all content should be migrated
	if filename == "versions.tf" {
		hasMovedBlocks = true
	}

	// Process each block in the file
	for _, block := range writeFile.Body().Blocks() {
		blockType := block.Type()
		labels := block.Labels()
		
		// Get the block content including formatting
		blockTokens := block.BuildTokens(nil)
		blockContent := string(blockTokens.Bytes())

		// Extract leading comments (simplified - just get any comment before block)
		leadingComments := extractLeadingComments(tokens, blockTokens)
		
		// Track if this specific block is being moved
		blockMoved := false

		switch blockType {
		case "terraform":
			config.TerraformBlocks = append(config.TerraformBlocks, tfhcl.Block{
				Type:            blockType,
				Labels:          labels,
				Content:         blockContent,
				LeadingComments: leadingComments,
				SourceFile:      filename,
			})
			blockMoved = true
			hasMovedBlocks = true

		case "provider":
			providerName := ""
			alias := ""
			if len(labels) > 0 {
				providerName = labels[0]
			}
			
			// Check for alias in block body
			for name, attr := range block.Body().Attributes() {
				if name == "alias" {
					// Extract alias value from the expression only
					exprTokens := attr.Expr().BuildTokens(nil)
					aliasValue := strings.TrimSpace(string(exprTokens.Bytes()))
					// Remove quotes if present
					alias = strings.Trim(aliasValue, `"`)
				}
			}

			config.ProviderBlocks = append(config.ProviderBlocks, tfhcl.ProviderBlock{
				Name:            providerName,
				Alias:           alias,
				Content:         blockContent,
				LeadingComments: leadingComments,
				SourceFile:      filename,
			})
			if filename != "providers.tf" {
				blockMoved = true
				hasMovedBlocks = true
			}

		case "variable":
			varName := ""
			if len(labels) > 0 {
				varName = labels[0]
			}
			config.VariableBlocks = append(config.VariableBlocks, tfhcl.VariableBlock{
				Name:            varName,
				Content:         blockContent,
				LeadingComments: leadingComments,
				SourceFile:      filename,
			})
			if filename != "variables.tf" {
				blockMoved = true
				hasMovedBlocks = true
			}

		case "output":
			outputName := ""
			if len(labels) > 0 {
				outputName = labels[0]
			}
			config.OutputBlocks = append(config.OutputBlocks, tfhcl.OutputBlock{
				Name:            outputName,
				Content:         blockContent,
				LeadingComments: leadingComments,
				SourceFile:      filename,
			})
			if filename != "outputs.tf" {
				blockMoved = true
				hasMovedBlocks = true
			}

		case "import":
			config.ImportBlocks = append(config.ImportBlocks, tfhcl.ImportBlock{
				Content:         blockContent,
				LeadingComments: leadingComments,
				SourceFile:      filename,
			})
			if filename != "imports.tf" {
				blockMoved = true
				hasMovedBlocks = true
			}

		default:
			// Keep resources, data sources, locals, modules in original files
			blockMoved = false
		}
		
		// Only add to preserved blocks if this block is NOT being moved
		if !blockMoved {
			preservedBlocks = append(preservedBlocks, leadingComments+blockContent)
		}
	}

	// File preservation logic:
	// 1. If file has blocks that should stay, preserve it with only those blocks
	// 2. If file has no blocks to preserve and had blocks moved, mark for deletion
	if len(preservedBlocks) > 0 {
		// File has content that should stay - preserve it with only that content
		config.PreservedFiles[filename] = strings.Join(preservedBlocks, "\n\n")
	} else if hasMovedBlocks {
		// File has no preserved content and had blocks moved - mark for deletion
		if config.FilesToDelete == nil {
			config.FilesToDelete = make(map[string]bool)
		}
		config.FilesToDelete[filename] = true
	}

	return nil
}

// extractLeadingComments extracts comments immediately before a block
func extractLeadingComments(allTokens hclwrite.Tokens, blockTokens hclwrite.Tokens) string {
	// This is a simplified implementation
	// In production, you'd want to properly track token positions
	// and extract only comments directly above the block
	return ""
}

// OrganizeTerraformFiles reorganizes the config into standard files
func OrganizeTerraformFiles(config *tfhcl.ModuleOrganization) error {
	// Merge all terraform blocks into one
	if len(config.TerraformBlocks) > 0 {
		mergedTerraform := mergeTerraformBlocks(config.TerraformBlocks)
		config.TerraformFile = mergedTerraform
	}

	// Organize provider blocks
	if len(config.ProviderBlocks) > 0 {
		config.ProvidersFile = organizeProviderBlocks(config.ProviderBlocks)
	}

	// Organize variable blocks
	if len(config.VariableBlocks) > 0 {
		config.VariablesFile = organizeVariableBlocks(config.VariableBlocks)
	}

	// Organize output blocks
	if len(config.OutputBlocks) > 0 {
		config.OutputsFile = organizeOutputBlocks(config.OutputBlocks)
	}

	// Organize import blocks
	if len(config.ImportBlocks) > 0 {
		config.ImportsFile = organizeImportBlocks(config.ImportBlocks)
	}

	return nil
}

// mergeTerraformBlocks merges multiple terraform blocks into one
func mergeTerraformBlocks(blocks []tfhcl.Block) string {
	if len(blocks) == 0 {
		return ""
	}

	// Deduplicate blocks by content
	uniqueBlocks := make(map[string]tfhcl.Block)
	for _, block := range blocks {
		// Use content as key for deduplication
		key := strings.TrimSpace(block.Content)
		if _, exists := uniqueBlocks[key]; !exists {
			uniqueBlocks[key] = block
		}
	}

	// If we only have one unique block, return it directly
	if len(uniqueBlocks) == 1 {
		for _, block := range uniqueBlocks {
			if block.LeadingComments != "" {
				return block.LeadingComments + "\n" + block.Content
			}
			return block.Content
		}
	}

	// Merge multiple terraform blocks into one
	// For now, concatenate them - proper merging would parse and combine attributes
	
	// Collect unique blocks in deterministic order
	var sortedBlocks []tfhcl.Block
	for _, block := range uniqueBlocks {
		sortedBlocks = append(sortedBlocks, block)
	}
	
	// Sort by source file for consistency
	sort.Slice(sortedBlocks, func(i, j int) bool {
		return sortedBlocks[i].SourceFile < sortedBlocks[j].SourceFile
	})

	// Concatenate all terraform blocks
	// TODO: Implement proper attribute-level merging
	var result strings.Builder
	for i, block := range sortedBlocks {
		if i == 0 && block.LeadingComments != "" {
			result.WriteString(block.LeadingComments)
			result.WriteString("\n")
		}
		result.WriteString(block.Content)
		if i < len(sortedBlocks)-1 {
			result.WriteString("\n\n")
		}
	}
	
	return result.String()
}

// organizeProviderBlocks organizes provider blocks
func organizeProviderBlocks(blocks []tfhcl.ProviderBlock) string {
	var contents []string
	
	// Sort by provider name and alias for consistent output
	sort.Slice(blocks, func(i, j int) bool {
		if blocks[i].Name != blocks[j].Name {
			return blocks[i].Name < blocks[j].Name
		}
		return blocks[i].Alias < blocks[j].Alias
	})

	for _, block := range blocks {
		if block.LeadingComments != "" {
			contents = append(contents, block.LeadingComments)
		}
		contents = append(contents, block.Content)
	}
	
	return strings.Join(contents, "\n\n")
}

// organizeVariableBlocks organizes variable blocks
func organizeVariableBlocks(blocks []tfhcl.VariableBlock) string {
	var contents []string
	
	// Sort by variable name for consistent output
	sort.Slice(blocks, func(i, j int) bool {
		return blocks[i].Name < blocks[j].Name
	})

	for _, block := range blocks {
		if block.LeadingComments != "" {
			contents = append(contents, block.LeadingComments)
		}
		contents = append(contents, block.Content)
	}
	
	return strings.Join(contents, "\n\n")
}

// organizeOutputBlocks organizes output blocks
func organizeOutputBlocks(blocks []tfhcl.OutputBlock) string {
	var contents []string
	
	// Sort by output name for consistent output
	sort.Slice(blocks, func(i, j int) bool {
		return blocks[i].Name < blocks[j].Name
	})

	for _, block := range blocks {
		if block.LeadingComments != "" {
			contents = append(contents, block.LeadingComments)
		}
		contents = append(contents, block.Content)
	}
	
	return strings.Join(contents, "\n\n")
}

// organizeImportBlocks organizes import blocks
func organizeImportBlocks(blocks []tfhcl.ImportBlock) string {
	var contents []string
	
	for _, block := range blocks {
		if block.LeadingComments != "" {
			contents = append(contents, block.LeadingComments)
		}
		contents = append(contents, block.Content)
	}
	
	return strings.Join(contents, "\n\n")
}

// WriteTerraformConfig writes the organized config to files
func WriteTerraformConfig(dir string, config *tfhcl.ModuleOrganization) error {
	// Track which files we're creating/updating
	filesWritten := make(map[string]bool)
	
	// Write terraform.tf if content exists
	if config.TerraformFile != "" {
		if err := writeFile(filepath.Join(dir, "terraform.tf"), config.TerraformFile); err != nil {
			return err
		}
		filesWritten["terraform.tf"] = true
	}

	// Write providers.tf if content exists
	if config.ProvidersFile != "" {
		if err := writeFile(filepath.Join(dir, "providers.tf"), config.ProvidersFile); err != nil {
			return err
		}
		filesWritten["providers.tf"] = true
	}

	// Write variables.tf if content exists
	if config.VariablesFile != "" {
		if err := writeFile(filepath.Join(dir, "variables.tf"), config.VariablesFile); err != nil {
			return err
		}
		filesWritten["variables.tf"] = true
	}

	// Write outputs.tf if content exists
	if config.OutputsFile != "" {
		if err := writeFile(filepath.Join(dir, "outputs.tf"), config.OutputsFile); err != nil {
			return err
		}
		filesWritten["outputs.tf"] = true
	}

	// Write imports.tf if content exists
	if config.ImportsFile != "" {
		if err := writeFile(filepath.Join(dir, "imports.tf"), config.ImportsFile); err != nil {
			return err
		}
		filesWritten["imports.tf"] = true
	}

	// Write preserved files (resources, data, locals, modules)
	for filename, content := range config.PreservedFiles {
		if err := writeFile(filepath.Join(dir, filename), content); err != nil {
			return err
		}
		filesWritten[filename] = true
	}

	// Delete files that should be removed after reorganization
	for filename := range config.FilesToDelete {
		// Don't delete files we just wrote
		if filesWritten[filename] {
			continue
		}
		
		filePath := filepath.Join(dir, filename)
		// Check if file exists before trying to delete
		if _, err := ioutil.ReadFile(filePath); err == nil {
			// File exists, delete it
			if err := deleteFile(filePath); err != nil {
				return fmt.Errorf("failed to delete %s: %w", filename, err)
			}
		}
	}
	
	// Also delete versions.tf if it exists and we created terraform.tf
	if filesWritten["terraform.tf"] {
		versionsPath := filepath.Join(dir, "versions.tf")
		if _, err := ioutil.ReadFile(versionsPath); err == nil {
			// versions.tf exists, delete it
			if err := deleteFile(versionsPath); err != nil {
				return fmt.Errorf("failed to delete versions.tf: %w", err)
			}
		}
	}
	
	return nil
}

// writeFile writes content to a file
func writeFile(path, content string) error {
	// Add final newline if not present
	if !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	
	return ioutil.WriteFile(path, []byte(content), 0644)
}

// deleteFile deletes a file
func deleteFile(path string) error {
	return os.Remove(path)
}

// OrganizationError represents a specific organization issue with a filename
type OrganizationError struct {
	Filename string
	Message  string
}

// CheckOrganizationDetailed checks organization and returns detailed errors with filenames
func CheckOrganizationDetailed(current *tfhcl.ModuleOrganization) (bool, []OrganizationError) {
	var errors []OrganizationError
	needsReorg := false

	// Check for terraform blocks not in terraform.tf
	for _, block := range current.TerraformBlocks {
		if block.SourceFile != "terraform.tf" && block.SourceFile != "" {
			needsReorg = true
			errors = append(errors, OrganizationError{
				Filename: block.SourceFile,
				Message:  "Terraform block should be in terraform.tf",
			})
		}
	}

	// Check for misplaced provider blocks
	for _, block := range current.ProviderBlocks {
		if block.SourceFile != "" && block.SourceFile != "providers.tf" {
			needsReorg = true
			errors = append(errors, OrganizationError{
				Filename: block.SourceFile,
				Message:  "Provider block should be in providers.tf",
			})
		}
	}

	// Check for misplaced variable blocks
	for _, block := range current.VariableBlocks {
		if block.SourceFile != "" && block.SourceFile != "variables.tf" {
			needsReorg = true
			errors = append(errors, OrganizationError{
				Filename: block.SourceFile,
				Message:  "Variable block should be in variables.tf",
			})
		}
	}

	// Check for misplaced output blocks
	for _, block := range current.OutputBlocks {
		if block.SourceFile != "" && block.SourceFile != "outputs.tf" {
			needsReorg = true
			errors = append(errors, OrganizationError{
				Filename: block.SourceFile,
				Message:  "Output block should be in outputs.tf",
			})
		}
	}

	return needsReorg, errors
}

// CheckOrganization checks if the configuration needs reorganization
func CheckOrganization(current *tfhcl.ModuleOrganization) (bool, []string) {
	var differences []string
	needsReorg := false

	// Check if terraform blocks need consolidation
	if len(current.TerraformBlocks) > 1 {
		needsReorg = true
		differences = append(differences, fmt.Sprintf("Found %d terraform blocks that should be consolidated into terraform.tf", len(current.TerraformBlocks)))
	}

	// Check for terraform blocks not in terraform.tf
	for _, block := range current.TerraformBlocks {
		if block.SourceFile != "terraform.tf" && block.SourceFile != "" {
			needsReorg = true
			differences = append(differences, fmt.Sprintf("Terraform block found in %s, should be in terraform.tf", block.SourceFile))
			break
		}
	}

	// Check for misplaced provider blocks
	misplacedProviders := 0
	for _, block := range current.ProviderBlocks {
		// Provider blocks should be in providers.tf
		if block.SourceFile != "" && block.SourceFile != "providers.tf" {
			misplacedProviders++
		}
	}
	if misplacedProviders > 0 {
		needsReorg = true
		differences = append(differences, fmt.Sprintf("Found %d provider blocks that should be in providers.tf", misplacedProviders))
	}

	// Check for misplaced variable blocks
	misplacedVariables := 0
	for _, block := range current.VariableBlocks {
		if block.SourceFile != "" && block.SourceFile != "variables.tf" {
			misplacedVariables++
		}
	}
	if misplacedVariables > 0 {
		needsReorg = true
		differences = append(differences, fmt.Sprintf("Found %d variable blocks that should be in variables.tf", misplacedVariables))
	}

	// Check for misplaced output blocks
	misplacedOutputs := 0
	for _, block := range current.OutputBlocks {
		if block.SourceFile != "" && block.SourceFile != "outputs.tf" {
			misplacedOutputs++
		}
	}
	if misplacedOutputs > 0 {
		needsReorg = true
		differences = append(differences, fmt.Sprintf("Found %d output blocks that should be in outputs.tf", misplacedOutputs))
	}

	// Check for misplaced import blocks
	misplacedImports := 0
	for _, block := range current.ImportBlocks {
		if block.SourceFile != "" && block.SourceFile != "imports.tf" {
			misplacedImports++
		}
	}
	if misplacedImports > 0 {
		needsReorg = true
		differences = append(differences, fmt.Sprintf("Found %d import blocks that should be in imports.tf", misplacedImports))
	}

	return needsReorg, differences
}

// CompareTerraformConfigs compares two configs to check if reorganization is needed
func CompareTerraformConfigs(current, expected *tfhcl.ModuleOrganization) (bool, []string) {
	var differences []string
	needsReorg := false

	// Check if terraform blocks need consolidation
	if len(current.TerraformBlocks) > 1 {
		needsReorg = true
		differences = append(differences, fmt.Sprintf("Found %d terraform blocks that should be consolidated into terraform.tf", len(current.TerraformBlocks)))
	}

	// Check for terraform blocks not in terraform.tf
	for _, block := range current.TerraformBlocks {
		if block.SourceFile != "terraform.tf" && block.SourceFile != "" {
			needsReorg = true
			differences = append(differences, fmt.Sprintf("Terraform block found in %s, should be in terraform.tf", block.SourceFile))
			break
		}
	}

	// Check for misplaced provider blocks
	misplacedProviders := 0
	for _, block := range current.ProviderBlocks {
		// Provider blocks should be in providers.tf
		if block.SourceFile != "" && block.SourceFile != "providers.tf" {
			misplacedProviders++
		}
	}
	if misplacedProviders > 0 {
		needsReorg = true
		differences = append(differences, fmt.Sprintf("Found %d provider blocks that should be in providers.tf", misplacedProviders))
	}

	// Check for misplaced variable blocks
	misplacedVariables := 0
	for _, block := range current.VariableBlocks {
		if block.SourceFile != "" && block.SourceFile != "variables.tf" {
			misplacedVariables++
		}
	}
	if misplacedVariables > 0 {
		needsReorg = true
		differences = append(differences, fmt.Sprintf("Found %d variable blocks that should be in variables.tf", misplacedVariables))
	}

	// Check for misplaced output blocks
	misplacedOutputs := 0
	for _, block := range current.OutputBlocks {
		if block.SourceFile != "" && block.SourceFile != "outputs.tf" {
			misplacedOutputs++
		}
	}
	if misplacedOutputs > 0 {
		needsReorg = true
		differences = append(differences, fmt.Sprintf("Found %d output blocks that should be in outputs.tf", misplacedOutputs))
	}

	return needsReorg, differences
}