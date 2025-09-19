"""Native Starlark actions for Terraform commands"""

def terraform_format_action(ctx, src, output):
    """Runs terraform fmt on a single file.
    
    Args:
        ctx: Rule context
        src: Source .tf file
        output: Output file to write formatted content
    """
    ctx.actions.run_shell(
        inputs = [src],
        outputs = [output],
        command = "terraform fmt -write=false '$1' > '$2'",
        arguments = [src.path, output.path],
        mnemonic = "TerraformFormat",
        progress_message = "Formatting {}".format(src.short_path),
    )

def terraform_validate_action(ctx, srcs, work_dir, plugin_dir = None):
    """Runs terraform init and validate on a module.
    
    Args:
        ctx: Rule context
        srcs: Source files
        work_dir: Working directory (declared directory)
        plugin_dir: Optional plugin directory
        
    Returns:
        Output file with validation results
    """
    result = ctx.actions.declare_file(ctx.label.name + "_validate_result.txt")
    
    # Prepare the module in a work directory
    ctx.actions.run_shell(
        inputs = srcs + ([plugin_dir] if plugin_dir else []),
        outputs = [work_dir, result],
        command = """
# Create work directory
mkdir -p "$1"

# Copy all source files to work directory
for src in "${@:3}"; do
    if [[ "$src" != *"_plugin_mirror" ]]; then
        cp "$src" "$1/"
    fi
done

cd "$1"

# Initialize terraform
INIT_OPTS="-backend=false -upgrade=false -lockfile=readonly"
if [ -n "$2" ] && [ -d "$2" ]; then
    INIT_OPTS="$INIT_OPTS -plugin-dir=$2"
fi

if terraform init $INIT_OPTS > init.log 2>&1; then
    echo "Init successful" > "$2"
else
    echo "Init failed:" > "$2"
    cat init.log >> "$2"
    exit 1
fi

# Validate
if terraform validate -no-color > validate.log 2>&1; then
    echo "Validation successful" >> "$2"
else
    echo "Validation failed:" >> "$2"
    cat validate.log >> "$2"
    exit 1
fi
""",
        arguments = [work_dir.path, result.path] + [f.path for f in srcs],
        mnemonic = "TerraformValidate",
        progress_message = "Validating Terraform configuration",
    )
    
    return result

def tflint_action(ctx, srcs, result, config = None):
    """Runs tflint on terraform files.
    
    Args:
        ctx: Rule context
        srcs: Source files
        result: Output file for results
        config: Optional tflint config file
    """
    inputs = list(srcs)
    if config:
        inputs.append(config)
    
    config_arg = ""
    if config:
        config_arg = "--config={}".format(config.path)
    
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [result],
        command = """
# Create temporary directory
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Copy files
for src in "$@"; do
    if [[ "$src" == *.tf ]] || [[ "$src" == *.tf.json ]]; then
        cp "$src" "$WORK_DIR/"
    elif [[ "$src" == *.hcl ]]; then
        cp "$src" "$WORK_DIR/.tflint.hcl"
    fi
done

cd "$WORK_DIR"

# Initialize and run tflint
if tflint --init > init.log 2>&1; then
    if tflint {} > lint.log 2>&1; then
        echo "Linting successful" > "$1"
        cat lint.log >> "$1"
    else
        echo "Linting failed:" > "$1"
        cat lint.log >> "$1"
        exit 1
    fi
else
    echo "TFLint init failed:" > "$1"
    cat init.log >> "$1"
    exit 1
fi
""".format(config_arg),
        arguments = [result.path] + [f.path for f in inputs if not f.path.endswith(result.path)],
        mnemonic = "TFLint",
        progress_message = "Running TFLint",
    )

def terraform_docs_action(ctx, srcs, output, config = None):
    """Runs terraform-docs to generate documentation.
    
    Args:
        ctx: Rule context
        srcs: Source files
        output: Output file for documentation
        config: Optional terraform-docs config
    """
    inputs = list(srcs)
    if config:
        inputs.append(config)
    
    config_arg = ""
    if config:
        config_arg = "--config {}".format(config.path)
    
    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [output],
        command = """
# Create temporary directory
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Copy files
for src in "$@"; do
    if [[ "$src" != "$1" ]]; then
        cp "$src" "$WORK_DIR/"
    fi
done

cd "$WORK_DIR"

# Generate documentation
terraform-docs markdown . {} > "$1"
""".format(config_arg),
        arguments = [output.path] + [f.path for f in inputs if f.path != output.path],
        mnemonic = "TerraformDocs", 
        progress_message = "Generating Terraform documentation",
    )