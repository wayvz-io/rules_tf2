"""Shell toolchain utilities for rules_tf2.

This module provides a drop-in replacement for ctx.actions.run_shell() that
works in both Nix environments (where /bin/bash doesn't exist) and RBE
(where the Nix shell path doesn't exist on remote executors).

The approach:
1. Write the command to a script with #!/usr/bin/env bash shebang
2. Execute the script directly (not through bash)
3. The OS uses /usr/bin/env to find bash in PATH

This works because:
- /usr/bin/env exists on both Nix and standard Linux (RBE executors)
- With use_default_shell_env=True, bash is in PATH on both systems

Usage:
    1. Add SH_TOOLCHAIN_TYPE to your rule's toolchains attribute
    2. Use run_shell() instead of ctx.actions.run_shell()

Example:
    load("//tf2/tools/runners:sh_toolchain.bzl", "SH_TOOLCHAIN_TYPE", "run_shell")

    my_rule = rule(
        implementation = _my_rule_impl,
        toolchains = [SH_TOOLCHAIN_TYPE],
    )

    def _my_rule_impl(ctx):
        run_shell(
            ctx,
            inputs = [...],
            outputs = [...],
            command = "...",
            mnemonic = "MyAction",
        )
"""

# Shell toolchain type from rules_shell
# We still require this for API compatibility, but use a portable approach for execution
SH_TOOLCHAIN_TYPE = "@rules_shell//shell:toolchain_type"

def run_shell(
        ctx,
        inputs,
        outputs,
        command,
        mnemonic = None,
        progress_message = None,
        env = None,
        execution_requirements = None,
        use_default_shell_env = True):
    """Run a shell command using a portable shell invocation.

    This is a drop-in replacement for ctx.actions.run_shell() that works
    in both Nix environments and RBE by using #!/usr/bin/env bash shebang.

    Args:
        ctx: Rule context with shell toolchain configured
        inputs: Input files for the action (list or depset)
        outputs: Output files for the action
        command: Shell command to execute
        mnemonic: Action mnemonic
        progress_message: Progress message to display
        env: Environment variables dict
        execution_requirements: Execution requirements dict
        use_default_shell_env: Whether to use default shell environment (default: True)
    """

    # Convert inputs to list if it's a depset
    if type(inputs) == "depset":
        input_list = inputs.to_list()
    else:
        input_list = list(inputs)

    # Write the command to a script file with a portable shebang
    # Using #!/usr/bin/env bash works on both Nix and standard Linux (RBE)
    # because /usr/bin/env is universally available and finds bash in PATH
    if outputs:
        # Create a unique suffix from the first output's path
        output_suffix = outputs[0].short_path.replace("/", "_").replace(".", "_")
    else:
        output_suffix = "script"
    script_name = "{}_{}".format(ctx.label.name, output_suffix)
    script = ctx.actions.declare_file(script_name + ".sh")

    # Prepend shebang if the command doesn't already have one
    if not command.startswith("#!"):
        script_content = "#!/usr/bin/env bash\nset -euo pipefail\n" + command
    else:
        script_content = command

    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    # Build the action arguments
    # Execute the script directly - the shebang handles finding bash
    run_kwargs = {
        "executable": script,
        "inputs": depset(input_list + [script]),
        "outputs": outputs,
        "toolchain": SH_TOOLCHAIN_TYPE,
    }

    if mnemonic:
        run_kwargs["mnemonic"] = mnemonic
    if progress_message:
        run_kwargs["progress_message"] = progress_message
    if env:
        run_kwargs["env"] = env
    if execution_requirements:
        run_kwargs["execution_requirements"] = execution_requirements
    if use_default_shell_env:
        run_kwargs["use_default_shell_env"] = use_default_shell_env

    ctx.actions.run(**run_kwargs)
