package terraform

import (
	"testing"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/language"
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
	if load.Name != "//tf2:def.bzl" {
		t.Errorf("expected load name '//tf2:def.bzl', got %q", load.Name)
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

	// Note: tf_test is only generated if there's an existing tf_test rule
	// tf_module macro handles test files internally
	args := language.GenerateArgs{
		Config:       c,
		Dir:          "testdata/module_with_tests",
		Rel:          "module_with_tests",
		RegularFiles: []string{"main.tf", "terraform.tf", "README.md", "basic.tftest.hcl"},
	}

	result := lang.GenerateRules(args)

	// Only tf_module is generated (tf_module macro handles test files)
	if len(result.Gen) != 1 {
		t.Fatalf("expected 1 rule (tf_module only - tf_module macro handles tests), got %d", len(result.Gen))
	}

	// Find the module rule
	moduleRule := result.Gen[0]
	if moduleRule.Kind() != "tf_module" {
		t.Fatal("expected tf_module rule")
	}

	// Check tf_module name is the default
	if moduleRule.Name() != "tf_module" {
		t.Errorf("expected module name 'tf_module', got %q", moduleRule.Name())
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
}

func TestGenerateRules_MultipleTestFiles(t *testing.T) {
	// tf_module macro handles test files internally
	// Gazelle only generates tf_test if there's an existing one to update
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

	// Only tf_module generated (tf_module macro handles tests)
	if len(result.Gen) != 1 {
		t.Fatalf("expected 1 rule (tf_module only), got %d", len(result.Gen))
	}

	if result.Gen[0].Kind() != "tf_module" {
		t.Error("expected tf_module rule")
	}
}

func TestGenerateRules_TftestJsonFiles(t *testing.T) {
	// tf_module macro handles test files internally
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

	// Only tf_module generated (tf_module macro handles tests)
	if len(result.Gen) != 1 {
		t.Fatalf("expected 1 rule (tf_module only), got %d", len(result.Gen))
	}

	if result.Gen[0].Kind() != "tf_module" {
		t.Error("expected tf_module rule")
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
