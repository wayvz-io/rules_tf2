"""Stardoc-generated reference pages, assembled into the mdbook at build time.

Each reference page that documents a public rule or macro is generated from that
symbol's docstrings by a `//tf2:*_docs` Stardoc target. `generated_reference_pages`
prepends a "generated, do not edit" banner to each and emits it at its final
in-book path under `gen/`, collected in one filegroup.

The pages are NOT committed to the repo -- they are pure build outputs, like any
other codegen. `//docs:book` (and `//docs:serve`) drop this filegroup into the
mdbook source tree just before building, so editing a docstring and rebuilding is
all it takes to refresh the docs; there is no separate regenerate/commit step.

The page -> Stardoc mapping lives ONLY in the `pages` dict below. Consumers
reconstruct each page's destination from the generated file's own `gen/<path>`
location, so nothing has to repeat the mapping.

Hand-curated pages are intentionally absent: the section overview READMEs, and
`reference/cloud/tfc-agent-image.md` (whose `.bzl` transitively loads
`@rules_pkg//pkg:tar.bzl`, which exposes no `bzl_library` for `starlark_doc_extract`).
"""

def generated_reference_pages(name, banner, pages):
    """Emit banner+Stardoc reference pages at their in-book paths.

    Args:
        name: Name of the filegroup collecting every generated page.
        banner: Label of the Markdown banner file prepended to every page.
        pages: Dict mapping a book-relative Markdown path (e.g.
            `"reference/rules/tf-module.md"`) to the Stardoc label that
            generates it (e.g. `"//tf2:tf_module_docs"`).
    """
    outs = []
    for book_path, stardoc_label in pages.items():
        slug = book_path.replace("/", "_").replace(".", "_").replace("-", "_")
        gen = "_gen_" + slug
        native.genrule(
            name = gen,
            srcs = [banner, stardoc_label],
            outs = ["gen/" + book_path],
            # Banner, a blank line, then the raw Stardoc output.
            cmd = "{ cat $(location %s); echo; cat $(location %s); } > $@" % (banner, stardoc_label),
        )
        outs.append(":" + gen)
    native.filegroup(name = name, srcs = outs)
