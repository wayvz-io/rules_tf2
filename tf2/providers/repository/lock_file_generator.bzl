"""Rule for generating Terraform lock files from stored provider hashes"""

def _tf_lock_file_generator_impl(ctx):
    """Generate a .terraform.lock.hcl file from stored provider lock data"""

    # Output lock file
    output_lock = ctx.actions.declare_file(".terraform.lock.hcl")

    # Create a script to generate the lock file from provider_locks.bzl
    script = ctx.actions.declare_file(ctx.label.name + "_generate.py")

    script_content = '''#!/usr/bin/env python3
import json
import sys

def main():
    provider_locks_path = sys.argv[1]
    versions_file_path = sys.argv[2]
    output_lock_path = sys.argv[3]
    
    # Load provider locks data
    provider_locks = {}
    with open(provider_locks_path, 'r') as f:
        exec_globals = {}
        exec(f.read(), exec_globals)
        provider_locks = exec_globals.get('PROVIDER_LOCKS', {})
    
    # Load required providers from Bazel module definitions
    with open(versions_file_path, 'r') as f:
        versions_data = json.load(f)
    
    required_providers = {}
    if 'terraform' in versions_data and 'required_providers' in versions_data['terraform']:
        required_providers = versions_data['terraform']['required_providers']
    
    # Generate lock file content
    lines = []
    lines.append('# This file is maintained automatically by "terraform init".')
    lines.append('# Manual edits may be lost in future updates.')
    lines.append('')
    
    # Generate lock entries for each required provider
    for provider_name, provider_config in required_providers.items():
        source = provider_config.get('source', '')
        version = provider_config.get('version', '').replace('~> ', '').replace('>= ', '').replace('<= ', '').split(',')[0].strip()
        
        # Find matching lock data
        lock_key = f"{source}:{version}"
        
        if lock_key in provider_locks:
            lines.append(f'provider "registry.terraform.io/{source}" {{')
            lines.append(f'  version     = "{version}"')
            
            # Add constraints if present in original version spec
            orig_version = provider_config.get('version', '')
            if '~>' in orig_version or '>=' in orig_version or '<=' in orig_version or ',' in orig_version:
                lines.append(f'  constraints = "{orig_version}"')
            
            lines.append('  hashes = [')
            
            for hash_val in provider_locks[lock_key]:
                lines.append(f'    "{hash_val}",')
            
            lines.append('  ]')
            lines.append('}')
            lines.append('')
    
    # Write the lock file
    with open(output_lock_path, 'w') as f:
        f.write('\\n'.join(lines))

if __name__ == "__main__":
    main()
'''

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Run the script
    ctx.actions.run(
        outputs = [output_lock],
        inputs = [ctx.file.provider_locks, ctx.file.versions_file],
        executable = script,
        arguments = [
            ctx.file.provider_locks.path,
            ctx.file.versions_file.path,
            output_lock.path,
        ],
        mnemonic = "GenerateLockFile",
        progress_message = "Generating Terraform lock file from stored hashes",
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(
            files = depset([output_lock]),
        ),
    ]

tf_lock_file_generator = rule(
    implementation = _tf_lock_file_generator_impl,
    attrs = {
        "provider_locks": attr.label(
            doc = "The provider_locks.bzl file containing all provider hashes",
            allow_single_file = [".bzl"],
            mandatory = True,
        ),
        "versions_file": attr.label(
            doc = "The provider specifications from Bazel module system",
            allow_single_file = [".json"],
            mandatory = True,
        ),
    },
    doc = """Generates a .terraform.lock.hcl file from stored provider lock data.
    
    This rule reads the provider specifications to determine which providers are needed,
    then looks up the corresponding hashes from the centralized provider_locks.bzl
    file and generates a proper .terraform.lock.hcl file.
    
    This avoids the need to regenerate lock files on each machine, as the hashes
    are already stored centrally.
    
    Example:
        tf_lock_file_generator(
            name = "stack_lock",
            provider_locks = "@tf_provider_registry//:provider_locks.bzl",
            versions_file = ":versions.tf.json",
        )
    """,
)
