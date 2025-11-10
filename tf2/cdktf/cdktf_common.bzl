"""Common utilities for CDKTF repository rules"""

def create_cdktf_json(provider_name, provider_source, provider_version, major_version):
    """Create cdktf.json configuration"""
    return json.encode({
        "language": "go",
        "app": "echo",  # Dummy app since we only want to generate bindings
        "projectId": provider_name + "_" + major_version + "_bindings",
        "terraformProviders": [
            {
                "name": provider_name,
                "source": provider_source,
                "version": provider_version,
            }
        ],
        "terraformModules": [],
        "context": {},
    })

def create_go_mod(provider_name, major_version):
    """Create go.mod content for the generated bindings"""
    return """module cdktf_{provider_name}_{major_version}

go 1.21

require (
    github.com/aws/jsii-runtime-go v1.94.0
    github.com/hashicorp/terraform-cdk-go/cdktf v0.20.3
    github.com/aws/constructs-go/constructs/v10 v10.3.0
)
""".format(
        provider_name = provider_name,
        major_version = major_version,
    )

def create_build_bazel(provider_name, provider_version, major_version):
    """Create root BUILD.bazel file for CDKTF bindings"""
    return """# Generated CDKTF bindings for {provider_name} v{provider_version}
load("@gazelle//:def.bzl", "gazelle")

# gazelle:prefix cdktf_{provider_name}_{major_version}
# gazelle:go_generate_proto false
# gazelle:build_file_name BUILD.bazel
# gazelle:resolve go github.com/aws/jsii-runtime-go @com_github_aws_jsii_runtime_go//:jsii-runtime-go
# gazelle:resolve go github.com/hashicorp/terraform-cdk-go/cdktf @com_github_hashicorp_terraform_cdk_go_cdktf//:cdktf
# gazelle:resolve go github.com/aws/constructs-go/constructs/v10 @com_github_aws_constructs_go_constructs_v10//:constructs

gazelle(
    name = "gazelle",
)
""".format(
        provider_name = provider_name,
        provider_version = provider_version,
        major_version = major_version,
    )

def get_environment_for_cdktf(repository_ctx):
    """Get environment variables needed for CDKTF generation"""
    env = {}
    
    # Copy PATH if it exists
    if "PATH" in repository_ctx.os.environ:
        env["PATH"] = repository_ctx.os.environ["PATH"]
    
    # Don't set LD_LIBRARY_PATH globally - it breaks Bazel's process-wrapper
    # We'll handle library paths in the script itself for specific commands
    
    # Add standard environment variables
    env["HOME"] = repository_ctx.os.environ.get("HOME", "/tmp")
    env["CHECKPOINT_DISABLE"] = "1"
    env["JSII_SILENCE_WARNING_UNTESTED_NODE_VERSION"] = "1"
    
    # Go proxy settings
    env["GOPROXY"] = repository_ctx.os.environ.get("GOPROXY", "https://proxy.golang.org,direct")
    env["GOSUMDB"] = repository_ctx.os.environ.get("GOSUMDB", "sum.golang.org")
    
    return env

