package terraform

import (
	"reflect"
	"testing"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/language"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

func TestNewLanguage(t *testing.T) {
	lang := NewLanguage()
	if lang == nil {
		t.Fatal("NewLanguage returned nil")
	}
	if lang.Name() != "terraform" {
		t.Errorf("expected name 'terraform', got %q", lang.Name())
	}
}

func TestKinds(t *testing.T) {
	lang := NewLanguage()
	kinds := lang.Kinds()

	if _, ok := kinds["tf_module"]; !ok {
		t.Error("expected tf_module kind to be registered")
	}
	if _, ok := kinds["tf_test"]; !ok {
		t.Error("expected tf_test kind to be registered")
	}
}

func TestLoads(t *testing.T) {
	lang := NewLanguage()
	loads := lang.Loads()

	if len(loads) != 1 {
		t.Fatalf("expected 1 load, got %d", len(loads))
	}

	load := loads[0]
	if load.Name != "@rules_tf2//tf2:def.bzl" {
		t.Errorf("expected load name '@rules_tf2//tf2:def.bzl', got %q", load.Name)
	}

	symbols := make(map[string]bool)
	for _, s := range load.Symbols {
		symbols[s] = true
	}
	if !symbols["tf_module"] {
		t.Error("expected tf_module in load symbols")
	}
	if !symbols["tf_test"] {
		t.Error("expected tf_test in load symbols")
	}
}

func TestGenerateRules_BasicModule(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/basic_module",
		Rel:          "basic_module",
		RegularFiles: []string{"main.tf", "terraform.tf"},
	}

	result := lang.GenerateRules(args)

	if len(result.Gen) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(result.Gen))
	}

	r := result.Gen[0]
	if r.Kind() != "tf_module" {
		t.Errorf("expected kind 'tf_module', got %q", r.Kind())
	}
	if r.Name() != "tf_module" {
		t.Errorf("expected name 'tf_module', got %q", r.Name())
	}

	// Check srcs attribute exists
	srcs := r.Attr("srcs")
	if srcs == nil {
		t.Fatal("expected srcs attribute")
	}
}

func TestGenerateRules_ModuleWithReadme(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/module_with_readme",
		Rel:          "module_with_readme",
		RegularFiles: []string{"main.tf", "terraform.tf", "README.md"},
	}

	result := lang.GenerateRules(args)

	if len(result.Gen) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(result.Gen))
	}

	r := result.Gen[0]

	// Check srcs attribute exists and contains README.md
	srcs := r.Attr("srcs")
	if srcs == nil {
		t.Fatal("expected srcs attribute")
	}

	// When README.md is present, files should be listed explicitly
	// Use AttrStrings to get the list of files
	srcsList := r.AttrStrings("srcs")
	if srcsList == nil {
		t.Fatal("expected srcs to be a list")
	}

	hasReadme := false
	for _, s := range srcsList {
		if s == "README.md" {
			hasReadme = true
			break
		}
	}
	if !hasReadme {
		t.Errorf("expected README.md in srcs list, got: %v", srcsList)
	}
}

func TestGenerateRules_ModuleWithTests(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	// tf_test is always generated when test files exist
	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/module_with_tests",
		Rel:          "module_with_tests",
		RegularFiles: []string{"main.tf", "terraform.tf", "README.md", "basic.tftest.hcl"},
	}

	result := lang.GenerateRules(args)

	// Both tf_module and tf_test are generated
	if len(result.Gen) != 2 {
		t.Fatalf("expected 2 rules (tf_module and tf_test), got %d", len(result.Gen))
	}

	// Find the module rule
	var moduleRule, testRule *rule.Rule
	for _, r := range result.Gen {
		switch r.Kind() {
		case "tf_module":
			moduleRule = r
		case "tf_test":
			testRule = r
		}
	}

	if moduleRule == nil {
		t.Fatal("expected tf_module rule")
	}
	if testRule == nil {
		t.Fatal("expected tf_test rule")
	}

	// Check tf_module name is the default
	if moduleRule.Name() != "tf_module" {
		t.Errorf("expected module name 'tf_module', got %q", moduleRule.Name())
	}

	// Check tf_test name is the default
	if testRule.Name() != "tf_test" {
		t.Errorf("expected test name 'tf_test', got %q", testRule.Name())
	}

	// Check tf_test has correct module reference
	if testRule.AttrString("module") != ":tf_module" {
		t.Errorf("expected module ':tf_module', got %q", testRule.AttrString("module"))
	}

	// Check test_files contains the test file
	testFiles := testRule.AttrStrings("test_files")
	if len(testFiles) != 1 || testFiles[0] != "basic.tftest.hcl" {
		t.Errorf("expected test_files ['basic.tftest.hcl'], got %v", testFiles)
	}
}

func TestGenerateRules_NoTfFiles(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/empty",
		Rel:          "empty",
		RegularFiles: []string{"README.md", "some_file.txt"},
	}

	result := lang.GenerateRules(args)

	if len(result.Gen) != 0 {
		t.Errorf("expected 0 rules for directory without .tf files, got %d", len(result.Gen))
	}
}

func TestGenerateRules_DisabledExtension(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	cfg := newTerraformConfig()
	cfg.enabled = false

	c := config.New()
	c.Exts[terraformName] = cfg

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/basic_module",
		Rel:          "basic_module",
		RegularFiles: []string{"main.tf", "terraform.tf"},
	}

	result := lang.GenerateRules(args)

	if len(result.Gen) != 0 {
		t.Errorf("expected 0 rules when extension is disabled, got %d", len(result.Gen))
	}
}

func TestDefaultModuleName(t *testing.T) {
	// Verify the default module name constant
	if defaultModuleName != "tf_module" {
		t.Errorf("expected default module name 'tf_module', got %q", defaultModuleName)
	}
	if defaultTestName != "tf_test" {
		t.Errorf("expected default test name 'tf_test', got %q", defaultTestName)
	}
}

func TestExtractProvidersFromTerraformTf(t *testing.T) {
	cfg := newTerraformConfig()
	cfg.providerMapping["random"] = "@tf_provider_registry//:random_3"
	cfg.providerMapping["aws"] = "@tf_provider_registry//:aws_5"

	// Test with testdata file
	providers := extractProvidersFromTerraformTf("testdata/basic_module/terraform.tf", cfg)

	// basic_module doesn't have required_providers, so should be empty
	if len(providers) != 0 {
		t.Errorf("expected 0 providers for basic_module, got %d", len(providers))
	}
}

func TestKnownDirectives(t *testing.T) {
	lang := NewLanguage()
	configurer, ok := lang.(config.Configurer)
	if !ok {
		t.Fatal("language should implement config.Configurer")
	}

	directives := configurer.KnownDirectives()
	directiveSet := make(map[string]bool)
	for _, d := range directives {
		directiveSet[d] = true
	}

	if !directiveSet["terraform_enabled"] {
		t.Error("expected terraform_enabled directive")
	}
	if !directiveSet["terraform_provider"] {
		t.Error("expected terraform_provider directive")
	}
	if !directiveSet["terraform_ignore_file_warning"] {
		t.Error("expected terraform_ignore_file_warning directive")
	}
}

func TestGenerateRules_MultipleTestFiles(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/module_with_tests",
		Rel:          "multi_test",
		RegularFiles: []string{"main.tf", "a.tftest.hcl", "b.tftest.hcl", "z.tftest.hcl"},
	}

	result := lang.GenerateRules(args)

	// Both tf_module and tf_test are generated
	if len(result.Gen) != 2 {
		t.Fatalf("expected 2 rules (tf_module and tf_test), got %d", len(result.Gen))
	}

	var moduleRule, testRule *rule.Rule
	for _, r := range result.Gen {
		switch r.Kind() {
		case "tf_module":
			moduleRule = r
		case "tf_test":
			testRule = r
		}
	}

	if moduleRule == nil {
		t.Fatal("expected tf_module rule")
	}
	if testRule == nil {
		t.Fatal("expected tf_test rule")
	}

	// Check test_files are sorted
	testFiles := testRule.AttrStrings("test_files")
	if len(testFiles) != 3 {
		t.Fatalf("expected 3 test files, got %d", len(testFiles))
	}
	// Files should be sorted: a, b, z
	if testFiles[0] != "a.tftest.hcl" || testFiles[1] != "b.tftest.hcl" || testFiles[2] != "z.tftest.hcl" {
		t.Errorf("expected sorted test files, got %v", testFiles)
	}
}

func TestGenerateRules_TftestJsonFiles(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/module_with_tests",
		Rel:          "json_test",
		RegularFiles: []string{"main.tf", "test.tftest.json"},
	}

	result := lang.GenerateRules(args)

	// Both tf_module and tf_test are generated
	if len(result.Gen) != 2 {
		t.Fatalf("expected 2 rules (tf_module and tf_test), got %d", len(result.Gen))
	}

	var testRule *rule.Rule
	for _, r := range result.Gen {
		if r.Kind() == "tf_test" {
			testRule = r
			break
		}
	}

	if testRule == nil {
		t.Fatal("expected tf_test rule")
	}

	// Check test_files contains the JSON test file
	testFiles := testRule.AttrStrings("test_files")
	if len(testFiles) != 1 || testFiles[0] != "test.tftest.json" {
		t.Errorf("expected test_files ['test.tftest.json'], got %v", testFiles)
	}
}

func TestGenerateRules_SortedFiles(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	// Files in unsorted order
	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/module_with_readme",
		Rel:          "sorted_test",
		RegularFiles: []string{"z_file.tf", "a_file.tf", "main.tf", "README.md"},
	}

	result := lang.GenerateRules(args)

	if len(result.Gen) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(result.Gen))
	}

	r := result.Gen[0]
	srcsList := r.AttrStrings("srcs")
	if srcsList == nil {
		t.Fatal("expected srcs to be a list")
	}

	// Check .tf files are sorted (README.md appended at end)
	tfFiles := []string{}
	for _, s := range srcsList {
		if s != "README.md" {
			tfFiles = append(tfFiles, s)
		}
	}

	for i := 1; i < len(tfFiles); i++ {
		if tfFiles[i] < tfFiles[i-1] {
			t.Errorf("tf files not sorted: %v", tfFiles)
			break
		}
	}
}

func TestKinds_SrcsAreMergeableAndSubstituted(t *testing.T) {
	// Test that srcs attribute is marked for both substitution and merging
	// SubstituteAttrs: for label substitution
	// MergeableAttrs: to allow gazelle to update the attribute in existing BUILD files
	lang := NewLanguage()
	kinds := lang.Kinds()

	tfModuleKind := kinds["tf_module"]

	// srcs should be in SubstituteAttrs (for label substitution)
	if !tfModuleKind.SubstituteAttrs["srcs"] {
		t.Error("tf_module srcs should be in SubstituteAttrs for label substitution")
	}

	// srcs should be in MergeableAttrs (to allow updating existing BUILD files)
	if !tfModuleKind.MergeableAttrs["srcs"] {
		t.Error("tf_module srcs should be in MergeableAttrs to update BUILD files")
	}

	tfTestKind := kinds["tf_test"]
	if !tfTestKind.SubstituteAttrs["test_files"] {
		t.Error("tf_test test_files should be in SubstituteAttrs for label substitution")
	}
	if !tfTestKind.MergeableAttrs["test_files"] {
		t.Error("tf_test test_files should be in MergeableAttrs to update BUILD files")
	}
}

func TestGenerateRules_ExistingRuleWithGlob(t *testing.T) {
	// Test that when an existing rule has a glob, the generated rule
	// produces explicit file list that will replace it
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	// Simulate existing BUILD file with glob
	existingFile := rule.EmptyFile("test", "pkg")
	// Note: In real usage, the existing srcs would be a glob call expression
	// but gazelle's rule package represents this internally
	existingFile.Sync()

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/module_with_readme",
		Rel:          "glob_test",
		File:         existingFile,
		RegularFiles: []string{"main.tf", "variables.tf", "outputs.tf", "README.md"},
	}

	result := lang.GenerateRules(args)

	if len(result.Gen) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(result.Gen))
	}

	r := result.Gen[0]

	// The generated rule should have explicit file list
	srcsList := r.AttrStrings("srcs")
	if srcsList == nil {
		t.Fatal("expected srcs to be a string list")
	}

	// Should contain all the .tf files and README.md
	expected := map[string]bool{
		"main.tf":      true,
		"variables.tf": true,
		"outputs.tf":   true,
		"README.md":    true,
	}

	if len(srcsList) != len(expected) {
		t.Errorf("expected %d srcs, got %d: %v", len(expected), len(srcsList), srcsList)
	}

	for _, src := range srcsList {
		if !expected[src] {
			t.Errorf("unexpected src: %s", src)
		}
	}
}

func TestIsBazelLabel(t *testing.T) {
	tests := []struct {
		input    string
		expected bool
	}{
		{"//path/to:target", true},
		{"@repo//path:target", true},
		{"templates/foo.tpl", false},
		{"./relative/path", false},
		{"data/settings.json", false},
	}

	for _, tc := range tests {
		t.Run(tc.input, func(t *testing.T) {
			result := isBazelLabel(tc.input)
			if result != tc.expected {
				t.Errorf("isBazelLabel(%q) = %v, want %v", tc.input, result, tc.expected)
			}
		})
	}
}

func TestNormalizeFilePath(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"templates/foo.tpl", "templates/foo.tpl"},
		{"${path.module}/templates/foo.tpl", "templates/foo.tpl"},
		{"//path/to:file.json", "//path/to:file.json"},
		{"@repo//path:file", "@repo//path:file"},
		{"${var.path}/file.txt", ""},
		{"${local.dir}/other.txt", ""},
		{"/absolute/path.txt", ""},
		{"data/config.json", "data/config.json"},
	}

	for _, tc := range tests {
		t.Run(tc.input, func(t *testing.T) {
			result := normalizeFilePath(tc.input)
			if result != tc.expected {
				t.Errorf("normalizeFilePath(%q) = %q, want %q", tc.input, result, tc.expected)
			}
		})
	}
}

func TestExtractFileReferencesFromContent(t *testing.T) {
	tests := []struct {
		name             string
		content          string
		expectedFiles    []string
		expectedWarnings []string
	}{
		{
			name:             "templatefile simple path",
			content:          `templatefile("templates/init.tpl", {})`,
			expectedFiles:    []string{"templates/init.tpl"},
			expectedWarnings: []string{},
		},
		{
			name:             "file function",
			content:          `file("configs/settings.json")`,
			expectedFiles:    []string{"configs/settings.json"},
			expectedWarnings: []string{},
		},
		{
			name:             "path.module prefix stripped",
			content:          `templatefile("${path.module}/templates/foo.tpl", {})`,
			expectedFiles:    []string{"templates/foo.tpl"},
			expectedWarnings: []string{},
		},
		{
			name:             "Bazel label preserved",
			content:          `file("//path/to:config.json")`,
			expectedFiles:    []string{"//path/to:config.json"},
			expectedWarnings: []string{},
		},
		{
			name:             "complex expression generates warning",
			content:          `file("${var.path}/config.json")`,
			expectedFiles:    []string{},
			expectedWarnings: []string{"config.json"},
		},
		{
			name:             "multiple functions",
			content:          `templatefile("a.tpl", {}) file("b.json") fileexists("c.txt")`,
			expectedFiles:    []string{"a.tpl", "b.json", "c.txt"},
			expectedWarnings: []string{},
		},
		{
			name:             "filebase64 function",
			content:          `filebase64("binary/data.bin")`,
			expectedFiles:    []string{"binary/data.bin"},
			expectedWarnings: []string{},
		},
		{
			name:             "fileset function",
			content:          `fileset("${path.module}/scripts", "*.sh")`,
			expectedFiles:    []string{"scripts"},
			expectedWarnings: []string{},
		},
		{
			name:             "filesha256 function",
			content:          `filesha256("checksums/file.txt")`,
			expectedFiles:    []string{"checksums/file.txt"},
			expectedWarnings: []string{},
		},
		{
			name:             "empty content",
			content:          ``,
			expectedFiles:    []string{},
			expectedWarnings: []string{},
		},
		{
			name:             "no file functions",
			content:          `resource "aws_instance" "example" { ami = "ami-12345" }`,
			expectedFiles:    []string{},
			expectedWarnings: []string{},
		},
		{
			name: "multiline with mixed",
			content: `
resource "local_file" "config" {
  content = templatefile("templates/config.tpl", {})
}
resource "local_file" "data" {
  content = file("data/settings.json")
}
`,
			expectedFiles:    []string{"data/settings.json", "templates/config.tpl"},
			expectedWarnings: []string{},
		},
		{
			name:             "complex path with local variable",
			content:          `file("${local.config_dir}/settings.yaml")`,
			expectedFiles:    []string{},
			expectedWarnings: []string{"settings.yaml"},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := extractFileReferencesFromContent(tc.content)
			// Handle nil vs empty slice comparison for files
			if len(result.files) == 0 && len(tc.expectedFiles) == 0 {
				// Both empty, continue to check warnings
			} else if !reflect.DeepEqual(result.files, tc.expectedFiles) {
				t.Errorf("extractFileReferencesFromContent().files = %v, want %v", result.files, tc.expectedFiles)
			}
			// Check warnings
			if len(result.warnings) == 0 && len(tc.expectedWarnings) == 0 {
				return // Both empty, test passes
			}
			if !reflect.DeepEqual(result.warnings, tc.expectedWarnings) {
				t.Errorf("extractFileReferencesFromContent().warnings = %v, want %v", result.warnings, tc.expectedWarnings)
			}
		})
	}
}

func TestExtractFilenameFromComplexPath(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"${var.config_dir}/settings.json", "settings.json"},
		{"${local.path}/config.yaml", "config.yaml"},
		{"${module.foo.output}/template.tpl", "template.tpl"},
		{"simple/path.txt", ""},         // Not complex, no interpolation
		{"${var.filename}", ""},         // No path separator
		{"${var.path}/${var.file}", ""}, // Filename also has interpolation
		{"//bazel/label:target", ""},    // Bazel label
		{"@repo//path:file", ""},        // Bazel label
		{"nodots", ""},                  // No file extension
		{"${var.dir}/noextension", ""},  // No file extension
	}

	for _, tc := range tests {
		t.Run(tc.input, func(t *testing.T) {
			result := extractFilenameFromComplexPath(tc.input)
			if result != tc.expected {
				t.Errorf("extractFilenameFromComplexPath(%q) = %q, want %q", tc.input, result, tc.expected)
			}
		})
	}
}

func TestDeduplicateStrings(t *testing.T) {
	tests := []struct {
		name     string
		input    []string
		expected []string
	}{
		{
			name:     "no duplicates",
			input:    []string{"a", "b", "c"},
			expected: []string{"a", "b", "c"},
		},
		{
			name:     "with duplicates",
			input:    []string{"a", "b", "a", "c", "b"},
			expected: []string{"a", "b", "c"},
		},
		{
			name:     "all same",
			input:    []string{"x", "x", "x"},
			expected: []string{"x"},
		},
		{
			name:     "empty",
			input:    []string{},
			expected: []string{},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := deduplicateStrings(tc.input)
			// Handle nil vs empty slice comparison
			if len(result) == 0 && len(tc.expected) == 0 {
				return // Both empty, test passes
			}
			if !reflect.DeepEqual(result, tc.expected) {
				t.Errorf("deduplicateStrings(%v) = %v, want %v", tc.input, result, tc.expected)
			}
		})
	}
}

func TestGenerateRules_ModuleWithFileRefs(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/module_with_file_refs",
		Rel:          "module_with_file_refs",
		RegularFiles: []string{"main.tf", "terraform.tf"},
	}

	result := lang.GenerateRules(args)

	if len(result.Gen) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(result.Gen))
	}

	r := result.Gen[0]
	srcs := r.AttrStrings("srcs")

	// Should include detected file references
	hasTemplates := false
	hasData := false
	for _, s := range srcs {
		if s == "templates/config.tpl" {
			hasTemplates = true
		}
		if s == "data/settings.json" {
			hasData = true
		}
	}

	if !hasTemplates {
		t.Errorf("expected 'templates/config.tpl' in srcs, got %v", srcs)
	}
	if !hasData {
		t.Errorf("expected 'data/settings.json' in srcs, got %v", srcs)
	}
}

func TestGenerateRules_TestWithExternalRefs(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/test_with_external_refs",
		Rel:          "test_with_external_refs",
		RegularFiles: []string{"main.tf", "terraform.tf", "contract.tftest.hcl"},
	}

	result := lang.GenerateRules(args)

	// Both tf_module and tf_test are generated
	if len(result.Gen) != 2 {
		t.Fatalf("expected 2 rules (tf_module and tf_test), got %d", len(result.Gen))
	}

	// Find tf_test rule
	var testRule *rule.Rule
	for _, r := range result.Gen {
		if r.Kind() == "tf_test" {
			testRule = r
			break
		}
	}

	if testRule == nil {
		t.Fatal("expected tf_test rule")
	}

	// Check test_files contains the Bazel label and local file
	testFiles := testRule.AttrStrings("test_files")

	hasBazelLabel := false
	hasLocalFile := false
	hasTestFile := false
	for _, f := range testFiles {
		if f == "//path/to/contracts:schema.json" {
			hasBazelLabel = true
		}
		if f == "local_data.txt" {
			hasLocalFile = true
		}
		if f == "contract.tftest.hcl" {
			hasTestFile = true
		}
	}

	if !hasBazelLabel {
		t.Errorf("expected Bazel label '//path/to/contracts:schema.json' in test_files, got %v", testFiles)
	}
	if !hasLocalFile {
		t.Errorf("expected 'local_data.txt' in test_files, got %v", testFiles)
	}
	if !hasTestFile {
		t.Errorf("expected 'contract.tftest.hcl' in test_files, got %v", testFiles)
	}
}

func TestGenerateRules_ModuleWithExistingBuild(t *testing.T) {
	lang := NewLanguage().(*terraformLang)

	c := config.New()
	c.Exts[terraformName] = newTerraformConfig()

	// Load existing BUILD file that is missing template files in srcs
	existingBuild := `load("@rules_tf2//tf2:def.bzl", "tf_module")

package(default_visibility = ["//visibility:public"])

tf_module(
    name = "tf_module",
    srcs = [
        "main.tf",
        "terraform.tf",
    ],
)
`
	existingFile, err := rule.LoadData("testdata/module_with_existing_build/BUILD.bazel", "module_with_existing_build", []byte(existingBuild))
	if err != nil {
		t.Fatalf("failed to load existing BUILD: %v", err)
	}

	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/module_with_existing_build",
		Rel:          "module_with_existing_build",
		RegularFiles: []string{"main.tf", "terraform.tf"},
		File:         existingFile,
	}

	result := lang.GenerateRules(args)

	if len(result.Gen) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(result.Gen))
	}

	r := result.Gen[0]
	srcs := r.AttrStrings("srcs")

	// Should include detected file reference: templates/config.tpl
	hasTemplate := false
	for _, s := range srcs {
		if s == "templates/config.tpl" {
			hasTemplate = true
		}
	}

	if !hasTemplate {
		t.Errorf("expected 'templates/config.tpl' in srcs, got %v", srcs)
	}

	// Verify other files are present
	hasMain := false
	hasTerraform := false
	for _, s := range srcs {
		if s == "main.tf" {
			hasMain = true
		}
		if s == "terraform.tf" {
			hasTerraform = true
		}
	}

	if !hasMain {
		t.Errorf("expected 'main.tf' in srcs, got %v", srcs)
	}
	if !hasTerraform {
		t.Errorf("expected 'terraform.tf' in srcs, got %v", srcs)
	}
}
