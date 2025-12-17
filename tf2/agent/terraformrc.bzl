"""Rule to generate .terraformrc configuration for TFC agent images."""

def _terraformrc_impl(ctx):
    """Generate .terraformrc file pointing to provider filesystem mirror.

    The generated file configures Terraform to use a filesystem mirror at the
    specified path for all provider installations, with no fallback to the
    registry. This ensures the TFC agent uses only the bundled providers.
    """
    out = ctx.actions.declare_file("{}.terraformrc".format(ctx.attr.name))

    content = """# Auto-generated .terraformrc for TFC agent
# Configures Terraform to use bundled providers from filesystem mirror

disable_checkpoint = true

provider_installation {{
  filesystem_mirror {{
    path = "{provider_path}"
  }}
  direct {{
    exclude = ["registry.terraform.io/*/*"]
  }}
}}
""".format(provider_path = ctx.attr.provider_mirror_path)

    ctx.actions.write(output = out, content = content)

    return [DefaultInfo(files = depset([out]))]

terraformrc = rule(
    implementation = _terraformrc_impl,
    attrs = {
        "provider_mirror_path": attr.string(
            default = "/terraform/providers",
            doc = "Path to provider mirror inside container",
        ),
    },
    doc = """Generates a .terraformrc file for TFC agent filesystem mirror.

    This rule creates a Terraform CLI configuration file that points to a
    filesystem mirror containing pre-downloaded provider plugins. The configuration
    disables direct registry access to ensure reproducible builds.

    Example:
        terraformrc(
            name = "agent_terraformrc",
            provider_mirror_path = "/terraform/providers",
        )
    """,
)
