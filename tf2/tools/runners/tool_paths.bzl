"""Utilities for accessing downloaded tool binaries"""

def get_tool_path(ctx, tool_name):
    """Get the runfiles path to a downloaded tool binary.
    
    Args:
        ctx: Rule context
        tool_name: Name of the tool (terraform, tflint, terraform-docs)
        
    Returns:
        String path to the tool binary in runfiles
    """
    # Check if we're in the main repository or external repository
    # The tf_tools extension creates tools with different repository names:
    # - When rules_tf2 is the root module: _main~tf_tools~
    # - When rules_tf2 is an external dependency: rules_tf2~~tf_tools~
    # 
    # We can determine this by checking if any tool files have the rules_tf2~~ prefix
    is_external = False
    if hasattr(ctx.attr, '_tools') and ctx.files._tools:
        for tool_file in ctx.files._tools:
            if "rules_tf2~~tf_tools~" in tool_file.short_path:
                is_external = True
                break
    
    
    if is_external:
        # External repository - tools are under rules_tf2~~ prefix (bzlmod module extension)
        tool_paths = {
            "terraform": "rules_tf2~~tf_tools~terraform_tool/terraform",
            "tflint": "rules_tf2~~tf_tools~tflint_tool/tflint", 
            "terraform-docs": "rules_tf2~~tf_tools~terraform_docs_tool/terraform-docs",
        }
    else:
        # Main repository - tools are under _main~ prefix  
        tool_paths = {
            "terraform": "_main~tf_tools~terraform_tool/terraform",
            "tflint": "_main~tf_tools~tflint_tool/tflint", 
            "terraform-docs": "_main~tf_tools~terraform_docs_tool/terraform-docs",
        }
    
    if tool_name not in tool_paths:
        fail("Unknown tool: {}".format(tool_name))
    
    return "$RUNFILES/{}".format(tool_paths[tool_name])

def get_terraform_path(ctx):
    """Get the path to the terraform binary."""
    return get_tool_path(ctx, "terraform")

def get_tflint_path(ctx):
    """Get the path to the tflint binary."""
    return get_tool_path(ctx, "tflint")

def get_terraform_docs_path(ctx):
    """Get the path to the terraform-docs binary.""" 
    return get_tool_path(ctx, "terraform-docs")

# Common tools attribute for rules that need access to tools
TOOLS_ATTR = {
    "_tools": attr.label_list(
        default = [
            "@tf_tool_registry//:terraform_bin",
            "@tf_tool_registry//:tflint_bin",
            "@tf_tool_registry//:terraform_docs_bin",
        ],
        allow_files = True,
        doc = "Tool binaries",
    ),
}