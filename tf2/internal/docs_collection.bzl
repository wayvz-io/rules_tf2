"""Documentation collection utilities for Terraform module exports

This module provides utilities for collecting documentation files from a
module and its nested module tree, handling path rewriting for nested modules.
"""

load("//tf2/providers/core:info.bzl", "TfModuleInfo")

def collect_module_docs(module_info):
    """Collect documentation files from a module and its nested modules.

    This function traverses the module tree iteratively and collects all
    documentation files, rewriting paths for nested modules to match their
    staged locations.

    Args:
        module_info: TfModuleInfo provider from the root module

    Returns:
        Dict mapping destination paths to source File objects. For example:
        {
            "README.md": File(...),
            "modules/nested_a/README.md": File(...),
            "modules/nested_b/README.md": File(...),
        }
    """
    docs_map = {}
    visited = {}

    # Use a work queue for iterative traversal (Starlark doesn't support recursion)
    # Each item is (module_info, module_path)
    work_queue = [(module_info, "")]

    # Process up to 100 levels deep (should be more than enough)
    for _ in range(100):
        if not work_queue:
            break

        # Pop from front of queue
        current_info, current_path = work_queue[0]
        work_queue = work_queue[1:]

        # Prevent cycles
        module_key = str(current_info.name) + ":" + current_path
        if module_key in visited:
            continue
        visited[module_key] = True

        # Collect docs from this module
        if hasattr(current_info, "docs") and current_info.docs:
            for doc_file in current_info.docs.to_list():
                if current_path:
                    # Nested module: docs go to modules/<name>/README.md
                    dest_path = "{}/{}".format(current_path, doc_file.basename)
                else:
                    # Root module: docs go to README.md
                    dest_path = doc_file.basename
                docs_map[dest_path] = doc_file

        # Add nested modules to work queue
        if hasattr(current_info, "modules") and current_info.modules:
            for nested_module in current_info.modules:
                if TfModuleInfo in nested_module:
                    nested_info = nested_module[TfModuleInfo]
                    nested_name = nested_info.name

                    # Construct path for nested module
                    if current_path:
                        nested_path = "{}/modules/{}".format(current_path, nested_name)
                    else:
                        nested_path = "modules/{}".format(nested_name)

                    work_queue.append((nested_info, nested_path))

    return docs_map

def docs_map_to_list(docs_map):
    """Convert a docs map to a list of (dest_path, source_file) tuples.

    Args:
        docs_map: Dict from collect_module_docs

    Returns:
        List of (dest_path, source_file) tuples, sorted by dest_path
    """
    items = [(k, v) for k, v in docs_map.items()]
    # Sort by destination path for deterministic ordering
    return sorted(items, key = lambda x: x[0])
