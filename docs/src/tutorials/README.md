# Tutorials

Learning-oriented material for newcomers to rules_tf2.

> **Note**: This project is published as-is and is not actively maintained.
> Dedicated step-by-step tutorials have not been written. The runnable examples
> in the repository are the best starting point for learning by doing.

## Start from the examples

The [`examples/`](https://github.com/wayvz-io/rules_tf2/tree/main/examples)
directory contains working, tested configurations you can copy and run:

| Example | What it shows |
|---------|---------------|
| `basic_module/` | A minimal `tf_module` with providers and the auto-generated test suite |
| `module_with_dependencies/` | Composing modules, provider inheritance, and outputs |
| `parent_module/` / `child_with_nested_dep/` | Nested module dependency graphs |
| `opa_policy/` | Policy testing with `tf_opa_test` |
| `sentinel_policy/` | Policy testing with `tf_sentinel_test` |

Run an example's full test suite with:

```bash
bazel test //examples/basic_module:all
```

## Where to go next

- [How-to Guides](../guides/README.md) - task-oriented instructions
- [Reference](../reference/README.md) - the full rule and macro API
- [Explanation](../explanation/architecture.md) - how and why rules_tf2 works
