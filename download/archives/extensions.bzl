"""
# `download_archives` module extension

Module extension for per-version archive downloads.
"""

load("@version_utils//spec:spec.bzl", Spec = "spec")
load("@version_utils//version:version.bzl", Version = "version")
load("//lib:index.bzl", Index = "index")
load(
    ":repository.bzl",
    _ATTRS = "ATTRS",
    _DOC_LINK_REFS = "DOC_LINK_REFS",
    _DOC_PATCHING = "DOC_PATCHING",
    _DOC_VERSION_SCHEME = "DOC_VERSION_SCHEME",
    _archives = "archives",
)

_DOC_INTRO = """
Module extension for per-version archive downloads.

Use `download.archives(...)` to declare archive repositories. Each
declaration creates an index repository (`@<NAME>`) and one download
repository per version (`@<NAME>-<VERSION>`). Archives are only
downloaded when a build references a specific version.

### How it works

The module extension creates two kinds of repositories:

**Index repository (`@<NAME>`)**: created eagerly when the extension is
evaluated. It parses the [repo JSON index], generates per-version BUILD files
with aliases pointing to the download repositories, and writes repo metadata.
No archives are downloaded at this stage. It contains:
- Per-version packages with aliases: `@<NAME>//<VERSION>:files`, `:dir`
- Per-version `source.bzl` with `SOURCE` and `URL` of the actual download
- `repo.bzl` with `VERSIONS`, `DEFAULT_VERSION`, `METADATA`, `LOCK`
- `index.json`, `lock.json`, `metadata.json`

**Download repositories (`@<NAME>-<VERSION>`)**: one per version, created
lazily. Each download repository parses the same index for its version and
uses the same download logic as the `archives` rule, trying each source in
order with full per-source download args from the ["materialized repo
`context`"]. Each contains:
- `:files`: all files in the downloaded archive.
- `:dir`: the path to the directory where the archive was extracted.
- `:<VERSION>`: alias of `:files`.
- `source.bzl`: exports `SOURCE` (the source name) and `URL` (the URL used).
"""

_DOC_USAGE = """
### Usage:

```starlark
download = use_extension(
    "@download_archives//download/archives:extensions.bzl",
    "download_archives",
)

download.archives(
    name = "my_src",
    index = "//third-party:repo.json",
)

use_repo(download, "my_src")
```

Building `@my_src//18.1:files` downloads only version 18.1, not all versions
in the index.

To expose the per-version download repositories as direct dependencies (e.g.
for use in `use_repo`), set `expose_internal_repos = True`:

```starlark
download.archives(
    name = "my_src",
    index = "//third-party:repo.json",
    expose_internal_repos = True,
)

use_repo(download, "my_src", "my_src-18.1")
```
"""

_DOC = (
    _DOC_INTRO +
    _DOC_VERSION_SCHEME +
    _DOC_PATCHING +
    _DOC_USAGE +
    _DOC_LINK_REFS
)

def archives(
        ctx,
        name,
        index,
        patches = {},
        version_scheme = Version.SCHEME.SEMVER,
        spec_syntax = Spec.SYNTAX.SIMPLE,
        versions = [],
        sources = [],
        strict_integrity = True):
    """Create a `@<NAME>` index repo and `@<NAME>-<VERSION>` download repos.

    The index repo parses the JSON index, generates per-version BUILD files
    with aliases pointing to the download repos, and writes repo metadata.
    No archives are downloaded at this stage.

    Each download repo parses the same index for its version and uses the
    same download logic as the eager `archives` rule — trying each source
    in order with full per-source download args from the materialized context.

    Args:
        ctx: The module extension context.
        name: Name for the index repository.
        index: Label of the repo JSON index file.
        patches: Dict of patch labels to version spec strings.
        version_scheme: Version scheme (default: `SEMVER`).
        spec_syntax: Spec syntax (default: `SIMPLE`).
        versions: Optional list of versions to include.
        sources: Optional list of sources to use.
        strict_integrity: If True, all sources must share the same integrity.

    Returns:
        List of per-version download repo names (`["<NAME>-<VERSION>", ...]`).
    """

    # index repo: parses the JSON index, generates stub BUILD files and metadata
    _archives(
        name = name,
        index = index,
        patches = patches,
        version_scheme = version_scheme,
        spec_syntax = spec_syntax,
        versions = versions,
        sources = sources,
        strict_integrity = strict_integrity,
        lazy = True,
    )

    # per-version download repos: each downloads one version eagerly
    index_json = ctx.read(index)
    idx = Index.new(name, index_json, versions, sources)
    dl_repos = []

    for version in idx.repos.keys():
        _archives(
            name = "%s-%s" % (name, version),
            index = index,
            versions = [version],
            sources = sources,
            patches = patches,
            spec_syntax = spec_syntax,
            version_scheme = version_scheme,
            strict_integrity = strict_integrity,
            lazy = False,
        )

        dl_repos.append("%s-%s" % (name, version))

    return dl_repos

def _impl(ctx):
    direct_deps = []

    for mod in ctx.modules:
        for tag in mod.tags.archives:
            dl_repos = archives(
                ctx = ctx,
                name = tag.name,
                index = tag.index,
                patches = tag.patches,
                version_scheme = tag.version_scheme,
                spec_syntax = tag.spec_syntax,
                versions = tag.versions,
                sources = tag.sources,
                strict_integrity = tag.strict_integrity,
            )

            if mod.is_root:
                direct_deps.append(tag.name)

                if tag.expose_internal_repos:
                    direct_deps.extend(dl_repos)

    return ctx.extension_metadata(
        reproducible = True,
        root_module_direct_deps = sorted(direct_deps),
        root_module_direct_dev_deps = [],
    )

_ARCHIVES_TAG = tag_class(
    doc = """
    Declare an archive repository with per-version downloads.

    Creates an index repository (`@<NAME>`) with per-version aliases, and
    one download repository (`@<NAME>-<VERSION>`) per version. Archives
    are only downloaded when a build references a specific version.
    """,
    attrs = dict(
        name = attr.string(
            doc = "Name for the index repository.",
            mandatory = True,
        ),
        expose_internal_repos = attr.bool(
            default = False,
            doc = """
            When True, the per-version download repositories
            (`@<NAME>-<VERSION>`) are exposed as direct dependencies, allowing
            them to be listed in `use_repo` and referenced directly. Defaults
            to False.
            """,
        ),
        **_ATTRS
    ),
)

download_archives = module_extension(
    doc = _DOC,
    implementation = _impl,
    tag_classes = {
        "archives": _ARCHIVES_TAG,
    },
)
