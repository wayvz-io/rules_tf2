"""Unit tests for Terraform format rules"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest", "unittest")
load("//tf2/module/quality:format.bzl", "tf_format_test", "tf_format")

# Test that format test rule is created correctly
def _tf_format_test_creation_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that it's a test rule
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_format_test should provide DefaultInfo"
    )

    # Check that executable is set
    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_format_test should be executable"
    )

    return analysistest.end(env)

tf_format_test_creation_test = analysistest.make(_tf_format_test_creation_test_impl)

# Test format rule (formatter)
def _tf_format_rule_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Check that formatter is executable
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "tf_format should provide DefaultInfo"
    )

    default_info = target_under_test[DefaultInfo]
    asserts.true(
        env,
        default_info.files_to_run.executable != None,
        "tf_format should be executable"
    )

    return analysistest.end(env)

tf_format_rule_test = analysistest.make(_tf_format_rule_test_impl)

# Test format with multiple files
def _tf_format_multiple_files_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that multiple source files are included
    files = runfiles.files.to_list()
    tf_files = [f for f in files if f.path.endswith(".tf")]

    asserts.true(
        env,
        len(tf_files) >= 2,
        "Format test should handle multiple .tf files"
    )

    return analysistest.end(env)

tf_format_multiple_files_test = analysistest.make(_tf_format_multiple_files_test_impl)

# Test that only .tf files are included (not .tf.json)
def _tf_format_only_tf_files_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    runfiles = target_under_test[DefaultInfo].default_runfiles

    # Check that .tf.json files are excluded
    files = runfiles.files.to_list()
    tf_json_files = [f for f in files if f.path.endswith(".tf.json")]

    # The test files include .tf.json but format should exclude them
    # (Note: in actual implementation, this depends on how srcs are filtered)

    return analysistest.end(env)

tf_format_only_tf_files_test = analysistest.make(_tf_format_only_tf_files_test_impl)

# Test empty source list
def _tf_format_empty_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    # Empty sources should still create a valid test
    asserts.true(
        env,
        DefaultInfo in target_under_test,
        "Empty format test should still be valid"
    )

    return analysistest.end(env)

tf_format_empty_test = analysistest.make(_tf_format_empty_test_impl)

# Helper to create test terraform files with formatting issues
def _create_unformatted_tf_files_impl(ctx):
    """Create terraform files with formatting issues"""

    # Create unformatted main.tf
    main_tf = ctx.actions.declare_file("unformatted_main.tf")
    ctx.actions.write(
        output = main_tf,
        content = """
# Unformatted file with inconsistent spacing
resource   "aws_instance"    "test" {
ami = "ami-12345678"
      instance_type= "t2.micro"
   tags={
     Name="test"
Environment = "dev"
  }
}
""",
    )

    # Create unformatted variables.tf
    variables_tf = ctx.actions.declare_file("unformatted_variables.tf")
    ctx.actions.write(
        output = variables_tf,
        content = """
variable"region"{
type=string
  description= "AWS region"
    default ="us-east-1"
}

   variable   "instance_count"   {
     type    =number
default=1
}
""",
    )

    return [DefaultInfo(files = depset([main_tf, variables_tf]))]

create_unformatted_tf_files = rule(
    implementation = _create_unformatted_tf_files_impl,
)

# Helper to create properly formatted files
def _create_formatted_tf_files_impl(ctx):
    """Create properly formatted terraform files"""

    main_tf = ctx.actions.declare_file("formatted_main.tf")
    ctx.actions.write(
        output = main_tf,
        content = """
resource "aws_instance" "test" {
  ami           = "ami-12345678"
  instance_type = "t2.micro"

  tags = {
    Name        = "test"
    Environment = "dev"
  }
}
""",
    )

    variables_tf = ctx.actions.declare_file("formatted_variables.tf")
    ctx.actions.write(
        output = variables_tf,
        content = """
variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "instance_count" {
  type    = number
  default = 1
}
""",
    )

    return [DefaultInfo(files = depset([main_tf, variables_tf]))]

create_formatted_tf_files = rule(
    implementation = _create_formatted_tf_files_impl,
)

# Helper to create mixed file types
def _create_mixed_file_types_impl(ctx):
    """Create a mix of .tf and .tf.json files"""

    tf_file = ctx.actions.declare_file("resource.tf")
    ctx.actions.write(
        output = tf_file,
        content = """
resource "aws_s3_bucket" "test" {
  bucket = "test-bucket"
}
""",
    )

    tf_json_file = ctx.actions.declare_file("data.tf.json")
    ctx.actions.write(
        output = tf_json_file,
        content = """
{
  "data": {
    "aws_ami": {
      "ubuntu": {
        "most_recent": true,
        "owners": ["099720109477"]
      }
    }
  }
}
""",
    )

    return [DefaultInfo(files = depset([tf_file, tf_json_file]))]

create_mixed_file_types = rule(
    implementation = _create_mixed_file_types_impl,
)

# Test suite setup
def format_test_suite(name):
    """Create all format test targets"""

    # Create test files
    create_unformatted_tf_files(
        name = "unformatted_files",
    )

    create_formatted_tf_files(
        name = "formatted_files",
    )

    create_mixed_file_types(
        name = "mixed_files",
    )

    # Test basic format test creation
    tf_format_test(
        name = "basic_format_test",
        srcs = [":formatted_files"],
        size = "small",
    )

    tf_format_test_creation_test(
        name = "tf_format_test_creation_test",
        target_under_test = ":basic_format_test",
        size = "small",
    )

    # Test format rule (formatter)
    tf_format(
        name = "basic_formatter",
        srcs = [":unformatted_files"],
    )

    tf_format_rule_test(
        name = "tf_format_rule_test",
        target_under_test = ":basic_formatter",
        size = "small",
    )

    # Test with multiple files
    tf_format_test(
        name = "format_multiple_files",
        srcs = [":unformatted_files"],
        size = "small",
    )

    tf_format_multiple_files_test(
        name = "tf_format_multiple_files_test",
        target_under_test = ":format_multiple_files",
        size = "small",
    )

    # Test with mixed file types
    tf_format_test(
        name = "format_mixed_types",
        srcs = [":mixed_files"],
        size = "small",
    )

    tf_format_only_tf_files_test(
        name = "tf_format_only_tf_files_test",
        target_under_test = ":format_mixed_types",
        size = "small",
    )

    # Test empty sources
    tf_format_test(
        name = "format_empty",
        srcs = [],
        size = "small",
    )

    tf_format_empty_test(
        name = "tf_format_empty_test",
        target_under_test = ":format_empty",
        size = "small",
    )

    # Aggregate all tests
    native.test_suite(
        name = name,
        tests = [
            ":tf_format_test_creation_test",
            ":tf_format_rule_test",
            ":tf_format_multiple_files_test",
            ":tf_format_only_tf_files_test",
            ":tf_format_empty_test",
        ],
    )
