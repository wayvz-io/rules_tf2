package hcl

// Provider represents a Terraform provider configuration
type Provider struct {
	Source               string   `json:"source"`
	Version              string   `json:"version"`
	ConfigurationAliases []string `json:"configuration_aliases,omitempty"`
}

// TerraformBlock represents a terraform configuration block
type TerraformBlock struct {
	RequiredVersion   string              `json:"required_version,omitempty"`
	RequiredProviders map[string]Provider `json:"required_providers,omitempty"`
}

// LockFileProvider represents a provider entry in terraform.lock.hcl
type LockFileProvider struct {
	Version     string   `json:"version"`
	Constraints string   `json:"constraints,omitempty"`
	Hashes      []string `json:"hashes,omitempty"`
}

// LockFile represents the parsed terraform.lock.hcl
type LockFile struct {
	Providers map[string]LockFileProvider `json:"providers"`
}

// Block represents a generic HCL block with its content and comments
type Block struct {
	Type       string   // Block type (e.g., "provider", "variable", "output")
	Labels     []string // Block labels (e.g., provider "aws", variable "name")
	Content    string   // Raw HCL content of the block
	LeadingComments string   // Comments directly above the block
	SourceFile string   // Original source file
	StartLine  int      // Starting line number in source file
}

// ProviderBlock represents a provider configuration block
type ProviderBlock struct {
	Name    string // Provider name (e.g., "aws")
	Alias   string // Provider alias if specified
	Content string // Raw HCL content
	LeadingComments string // Comments directly above the block
	SourceFile string // Source file this block came from
}

// VariableBlock represents a variable block
type VariableBlock struct {
	Name        string // Variable name
	Type        string // Variable type
	Description string // Variable description
	Default     string // Default value as raw HCL
	Content     string // Raw HCL content
	LeadingComments string // Comments directly above the block
	SourceFile string // Source file this block came from
}

// OutputBlock represents an output block
type OutputBlock struct {
	Name        string // Output name
	Value       string // Output value expression
	Description string // Output description
	Sensitive   bool   // Whether output is sensitive
	Content     string // Raw HCL content
	LeadingComments string // Comments directly above the block
	SourceFile string // Source file this block came from
}

// ImportBlock represents an import block (Terraform 1.5+)
type ImportBlock struct {
	To   string // Resource address to import to
	ID   string // Resource ID to import
	Content string // Raw HCL content
	LeadingComments string // Comments directly above the block
	SourceFile string // Source file this block came from
}

// ModuleOrganization represents a complete Terraform configuration for reorganization
type ModuleOrganization struct {
	TerraformBlocks []Block // All terraform blocks found
	ProviderBlocks  []ProviderBlock // All provider blocks
	VariableBlocks  []VariableBlock // All variable blocks
	OutputBlocks    []OutputBlock   // All output blocks
	ImportBlocks    []ImportBlock   // All import blocks
	OtherBlocks     []Block // Resources, data sources, locals, modules, etc.
	
	// Organized file contents (after reorganization)
	TerraformFile  string // Content for terraform.tf
	ProvidersFile  string // Content for providers.tf
	VariablesFile  string // Content for variables.tf
	OutputsFile    string // Content for outputs.tf
	ImportsFile    string // Content for imports.tf
	
	// Files to preserve (resources, data, locals, modules)
	PreservedFiles map[string]string // filename -> content
	
	// Files to delete after reorganization
	FilesToDelete map[string]bool // filename -> should delete
}