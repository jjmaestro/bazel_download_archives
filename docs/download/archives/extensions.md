<!-- Generated with Stardoc: http://skydoc.bazel.build -->

# `download_archives` module extension

Module extension for per-version archive downloads.

<a id="archives"></a>

## archives

<pre>
load("@download_archives//download/archives:extensions.bzl", "archives")

archives(<a href="#archives-ctx">ctx</a>, <a href="#archives-name">name</a>, <a href="#archives-index">index</a>, <a href="#archives-patches">patches</a>, <a href="#archives-version_scheme">version_scheme</a>, <a href="#archives-spec_syntax">spec_syntax</a>, <a href="#archives-versions">versions</a>, <a href="#archives-sources">sources</a>,
         <a href="#archives-strict_integrity">strict_integrity</a>)
</pre>

Create a `@<NAME>` index repo and `@<NAME>-<VERSION>` download repos.

The index repo parses the JSON index, generates per-version BUILD files
with aliases pointing to the download repos, and writes repo metadata.
No archives are downloaded at this stage.

Each download repo parses the same index for its version and uses the
same download logic as the eager `archives` rule â trying each source
in order with full per-source download args from the materialized context.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="archives-ctx"></a>ctx |  The module extension context.   |  none |
| <a id="archives-name"></a>name |  Name for the index repository.   |  none |
| <a id="archives-index"></a>index |  Label of the repo JSON index file.   |  none |
| <a id="archives-patches"></a>patches |  Dict of patch labels to version spec strings.   |  `{}` |
| <a id="archives-version_scheme"></a>version_scheme |  Version scheme (default: `SEMVER`).   |  `"semver"` |
| <a id="archives-spec_syntax"></a>spec_syntax |  Spec syntax (default: `SIMPLE`).   |  `"simple"` |
| <a id="archives-versions"></a>versions |  Optional list of versions to include.   |  `[]` |
| <a id="archives-sources"></a>sources |  Optional list of sources to use.   |  `[]` |
| <a id="archives-strict_integrity"></a>strict_integrity |  If True, all sources must share the same integrity.   |  `True` |

**RETURNS**

List of per-version download repo names (`["<NAME>-<VERSION>", ...]`).


<a id="download_archives"></a>

## download_archives

<pre>
download_archives = use_extension("@download_archives//download/archives:extensions.bzl", "download_archives")
download_archives.archives(<a href="#download_archives.archives-name">name</a>, <a href="#download_archives.archives-expose_internal_repos">expose_internal_repos</a>, <a href="#download_archives.archives-index">index</a>, <a href="#download_archives.archives-patches">patches</a>, <a href="#download_archives.archives-sources">sources</a>, <a href="#download_archives.archives-spec_syntax">spec_syntax</a>,
                           <a href="#download_archives.archives-strict_integrity">strict_integrity</a>, <a href="#download_archives.archives-version_scheme">version_scheme</a>, <a href="#download_archives.archives-versions">versions</a>)
</pre>

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

### Version scheme

The `version_scheme` attribute defines the format used for versions in both the
`index` and `patches`. The supported schemes are those in [`version_utils`'
`version` extension], with `SCHEME.SEMVER` ([semantic versioning]) being the
default.

[semantic versioning]: https://semver.org
[`version_utils`' `version` extension]: https://github.com/jjmaestro/bazel_version_utils/blob/main/docs/version/version.md

### Patching

The downloaded archive can also be patched by passing a `patches` argument, a
map of `Label`s of [unified diff format] patch files (applied from the root of
the downloaded archive) to "patch specs" that determine if the patch is to be
applied.

The "patch spec" format is `<VERSION_SPEC>[/<SOURCE>]`, where:

- `<VERSION_SPEC>` is a version constraints requirement spec that
  to specify the versions to which the patch applies.
- `<SOURCE>` (optional, defaults to `*`) is the source of the downloaded
  archive to which the patch should be applied. It's optional and it can also
  be `*`, a wildcard to apply the patch to the archives downloaded from any
  source.

The `<VERSION_SPEC>` syntax is specified with the `spec_syntax` attribute. It's
one of the syntaxes supported by [`version_utils`' `spec` extension] and the
default is `SYNTAX.SIMPLE`.

This helps to maintain patches that apply to e.g.:

- a specific version and source: `1.24.5/github`
- a specific version and all sources: `1.24.5/*` or `1.24.5`
- a range of versions and all sources: `>=1.24.5, <2.0.0/*`
- all versions and sources: `*` or `*/*`

Finally, to simplify patch maintenance, it's good practice to keep a dedicated
"patched branch" for each version we want to maintain, making it easy to
generate the list of patches using [`git format-patch`].

[unified diff format]: https://en.wikipedia.org/wiki/Diff#Unified_format
[`version_utils` `spec` extension]: https://github.com/jjmaestro/bazel_version_utils/blob/main/docs/specs/spec.md
[`git format-patch`]: https://git-scm.com/docs/git-format-patch

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

["Patching"]: #patching
[Subresource Integrity (SRI)]: https://w3c.github.io/webappsec-subresource-integrity/
["materialized repo `context`"]: ../../lib/index.md#materialized-repo-context
[`rctx.download_and_extract`]: https://bazel.build/rules/lib/builtins/repository_ctx#download_and_extract
[repo JSON index]: ../../lib/index.md


**TAG CLASSES**

<a id="download_archives.archives"></a>

### archives

Declare an archive repository with per-version downloads.

Creates an index repository (`@<NAME>`) with per-version aliases, and
one download repository (`@<NAME>-<VERSION>`) per version. Archives
are only downloaded when a build references a specific version.

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="download_archives.archives-name"></a>name |  Name for the index repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="download_archives.archives-expose_internal_repos"></a>expose_internal_repos |  When True, the per-version download repositories (`@<NAME>-<VERSION>`) are exposed as direct dependencies, allowing them to be listed in `use_repo` and referenced directly. Defaults to False.   | Boolean | optional |  `False`  |
| <a id="download_archives.archives-index"></a>index |  Label of the repo JSON index file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="download_archives.archives-patches"></a>patches |  Diff files to apply as patches at the root of the downloaded archive. The `dict` values represent "patch specs" in the `<VERSION_SPEC>/<SOURCE>` format, and determine when patches apply to the downloaded archive. Patches must be in standard [unified diff format], created from the root of the archive. All patches are applied from the root of the archive with `patch -p1`. For more details, see ["Patching"].   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: Label -> String</a> | optional |  `{}`  |
| <a id="download_archives.archives-sources"></a>sources |  Source names from which to download the archive. If none, all sources from the index are tried in order.   | List of strings | optional |  `[]`  |
| <a id="download_archives.archives-spec_syntax"></a>spec_syntax |  The syntax of the version constraints specification. The available syntaxes are those supported by `version_utils` (see `SYNTAX` in [`version_utils`' `spec` extension](https://github.com/jjmaestro/bazel_version_utils/blob/main/spec/spec.bzl)). Defaults to `SYNTAX.SIMPLE`.   | String | optional |  `"simple"`  |
| <a id="download_archives.archives-strict_integrity"></a>strict_integrity |  If `True`, all sources of a given archive version must share the same integrity hash. If they differ, the download will fail. Defaults to `True`.   | Boolean | optional |  `True`  |
| <a id="download_archives.archives-version_scheme"></a>version_scheme |  The scheme of the versions in `index` and `patches`. The available version schemes are those supported by `version_utils` (see `SCHEME` in [`version_utils`' `version` extension](https://github.com/jjmaestro/bazel_version_utils/blob/main/version/version.bzl)). Defaults to `SCHEME.SEMVER`.   | String | optional |  `"semver"`  |
| <a id="download_archives.archives-versions"></a>versions |  Versions of the archive to download. If none is specified it will download all of the versions available in the repo index.   | List of strings | optional |  `[]`  |


