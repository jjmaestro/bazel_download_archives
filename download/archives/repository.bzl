"""
# `archives` repository rule

Repository rule to create and maintain Bazel external repos. It helps reduce
boilerplate code by keeping a JSON index file with all of the metadata required
to download and extract an archive: the archive's `version`(s) and the
`source`(s) from which to try to download the archive.
"""

load("@version_utils//spec:spec.bzl", Spec = "spec")
load("@version_utils//version:version.bzl", Version = "version")
load("//lib:download.bzl", Download = "download")
load("//lib:index.bzl", Index = "index")
load("//lib:utils.bzl", Utils = "utils")

_DOC_INTRO = """
This repository rule wraps [`rctx.download_and_extract`] and creates a Bazel
repo under `@<NAME>`, downloading and extracting *one archive* from *one*
of the sources for *each* of the archive versions in the [repo JSON index].

When downloading the archive, if a source fails it will try the next one, and
only fail if all sources are exhausted.

To construct the arguments passed to [`rctx.download_and_extract`] it uses the
["materialized repo `context`"], which includes at minimum the materialized
`url` from which to download the archive.

### Repo structure

```
  @<NAME>/
   |
   |-- <VERSION>/
   |   |-- BUILD.bazel
   |   `-- <SOURCE>/
   |       |-- BUILD.bazel
   |       |-- ...
   |       `-- ...
   |
   |-- BUILD.bazel
   |-- index.json
   |-- lock.json
   |-- metadata.json
   |-- repo.bzl
   `-- patches/
       |-- <VERSION>/
           `-- <SOURCE>/
               |-- <PATCH_NAME>
               `-- ...
```

TL;DR, the repo can be used as follows:

- `@<NAME>//:<NAME>`: points to the `:files` target of the
  `DEFAULT_VERSION`.
- `@<NAME>//:<TARGET>`: points to the specific `TARGET` of the
  `DEFAULT_VERSION`.
- `@<NAME>//<VERSION>:<TARGET>`: points to the specific `TARGET` of that
  `VERSION`.

The `archives` repository rule creates a `@<NAME>` Bazel repo with a
public `//<VERSION>` package for every version in the index.

Each `//<VERSION>` package has three targets:
- `:files`: to access all the files in the downloaded archive.
- `:dir`: the path to the directory where the archive was extracted.
- `:<VERSION>`: `alias` of `:files`.
- `:<OUTPUT>`: one per subpath rendered by the index [`matrix`] `output`, to
  access only the files of that partition of the extracted tree. There are
  none of these when the index has no `matrix` or no `output`.

and two constants:
- `VERSION`: the version of the archive.
- `SOURCE`: the source from which the archive was downloaded.

Each `//<VERSION>` package has an *internal* `<SOURCE>` sub-package with
the actual files from the downloaded archive for that specific `version` and
`source`. The targets in the `//<VERSION>` package are aliases for targets in
the `//<VERSION>/<SOURCE>` sub-packages.

The root package `//` has three targets:
- `:files`: to access all the files in the `DEFAULT_VERSION` package.
- `:dir`: the path to the directory of the `DEFAULT_VERSION` package.
- `:<NAME>`: `alias` of `:files`.
- `:<OUTPUT>`: one per [`matrix`] `output` of the `DEFAULT_VERSION` package,
  as above.

and two constants:
- `VERSION`: the `DEFAULT_VERSION` of the archive.
- `SOURCE`: the source from which the default version was downloaded.

The root package also has the following:
- `//:index.json`: a copy of the repo index JSON file.
- `//:lock.json`: the repo lock file (see below).
- `//:metadata.json`: the repo metadata.
- `//:repo.bzl`: extension with the following constants:
  - `REPO_NAME`: The short repo name.
  - `VERSIONS`: a mapping of the downloaded `version`s to the `source` from
    which the archive was downloaded.
  - `DEFAULT_VERSION`: the default `version` of the archive.
  - `LOCK`: a `dict` with the contents of the repo `lock.json`.
  - `METADATA`: the free-form metadata map straight from the repo JSON index,
    if any.
- `//patches`: a package with `<VERSION>/<SOURCE>` sub-packages with the
  applied patches applied to that archive, if any (see ["Patching"] below).

The repo lock file contains a mapping of the downloaded `version` to a "lock
object" with the following properties:
  - `source`: the source from which the archive was downloaded.
  - `url`: the URL from which the archive was downloaded.
  - `integrity`: the SRI ([Subresource Integrity (SRI)]) of the downloaded archive.
  - `patches`: the list of patches applied to the archive after download, if any.
"""

DOC_LINK_REFS = """
["Patching"]: #patching
[`matrix`]: ../../lib/index.md#matrix
[Subresource Integrity (SRI)]: https://w3c.github.io/webappsec-subresource-integrity/
["materialized repo `context`"]: ../../lib/index.md#materialized-repo-context
[`rctx.download_and_extract`]: https://bazel.build/rules/lib/builtins/repository_ctx#download_and_extract
[repo JSON index]: ../../lib/index.md
"""

_DOC_SELECTING = """
### Selecting `versions` and `sources`

Users can also override the default selection of versions and sources with the
`versions` and `sources` arguments.

Note that selecting specific versions and/or arguments will change the values
of `VERSIONS` and `DEFAULT_VERSION`.
"""

_DOC_MATRIX = """
### Downloading a `matrix` of archives

Some archives are published as a *set* of files per version rather than as a
single file, e.g. a toolchain that publishes one archive per (target triple,
component). The index [`matrix`] describes that set, and the index `output`
decides how the combinations lay out in the extracted tree: combinations that
render the same `output` merge into a single tree, the rest partition it.

E.g. this index downloads four archives for version `1.97.1`, one per
(`triple`, `component`) combination, and partitions them by `triple`:

```json
{
  "version": 1,
  "sources": {
    "static.rust-lang.org": {
      "url": "https://{source}/dist/{component}-{version}-{triple}.tar.xz",
      "strip_prefix": "{component}-{version}-{triple}/{piece}"
    }
  },
  "matrix": [
    {
      "key": "triple",
      "values": ["x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu"]
    },
    {
      "key": "component",
      "values": {
        "cargo": {"piece": "cargo"},
        "rustfmt": {"piece": "rustfmt-preview"}
      }
    }
  ],
  "output": "{triple}",
  "versions": {
    "1.97.1": {
      "x86_64-unknown-linux-gnu": {
        "cargo": "sha256-4b5Xkw2Cfk73/RSNy0jgUv/AqIsGpKKO9EhIOqvsG2E=",
        "rustfmt": "sha256-kH/pfWr73h7KGzTJksduFAbUIuLm8TeBPTgqzsfrTRQ="
      },
      "aarch64-unknown-linux-gnu": {
        "cargo": "sha256-j3C8rM6lukvRh8P9TWTiRZK04Wr1E0lyAfWQnWFpHb4=",
        "rustfmt": "sha256-Pb3hXTB5SSQZWuRG89LOtUKhMTBtIq55EsdjTUFGIqg="
      }
    }
  }
}
```

which lays out the repo as:

```
  @rust_toolchain/
   |
   |-- 1.97.1/
   |   |-- BUILD.bazel
   |   `-- static.rust-lang.org/
   |       |-- BUILD.bazel
   |       |-- aarch64-unknown-linux-gnu/
   |       |   |-- bin/
   |       |   `-- ...
   |       `-- x86_64-unknown-linux-gnu/
   |           |-- bin/
   |           `-- ...
   (...)
```

So, on top of `:files`, which is all of the combinations, each rendered
`output` gets its own target:

- `@rust_toolchain//1.97.1:x86_64-unknown-linux-gnu`
- `@rust_toolchain//1.97.1:aarch64-unknown-linux-gnu`

Note that the `cargo` and `rustfmt` archives of a triple *merge* into that
triple's tree, giving one usable prefix with both binaries in `bin/`, while the
two triples stay apart.
"""

DOC_VERSION_SCHEME = """
### Version scheme

The `version_scheme` attribute defines the format used for versions in both the
`index` and `patches`. The supported schemes are those in [`version_utils`'
`version` extension], with `SCHEME.SEMVER` ([semantic versioning]) being the
default.

[semantic versioning]: https://semver.org
[`version_utils`' `version` extension]: https://github.com/jjmaestro/bazel_version_utils/blob/main/docs/version/version.md
"""

DOC_PATCHING = """
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
"""

_DOC_USAGE = """
### Usage:

Here's an example that shows how to create a `@wget_src` repo for [GNU wget]:

[GNU wget]: https://www.gnu.org/software/wget/

#### 1. Create the repo index

First, define a `repo.json` JSON index file in a package. Don't forget to add a
`BUILD.bazel` file in it if one doesn't already exists).

E.g. for a `//third-party/wget` package:

```sh
mkdir -p third-party/wget
touch third-party/wget/BUILD.bazel
```

Then add the following to the `repo.json` file:

```json
{
  "version": 1,
  "sources": {
    "github.com": {
      "owner": "mirror",
      "repo": "wget",
      "tag": "v{version}",
      "url": "https://{source}/{owner}/{repo}/archive/refs/tags/{tag}.tar.gz",
      "strip_prefix": "{repo}-{version}"
    },
    "gitlab.com": {
      "owner": "gnuwget",
      "repo": "wget",
      "tag": "v{version}",
      "filename": "{repo}-{tag}",
      "url": "https://{source}/{owner}/{repo}/-/archive/{tag}/{filename}.tar.gz",
      "strip_prefix": "{filename}"
    }
  },
  "versions": {
    "1.24.5": {
      "integrity": {
        "gitlab.com": "sha256-1Yw1cok0niLv563o07/BrjbCQIflWxK8UFlav9srtcw="
      }
    },
    "1.21.3": {
      "integrity": {
        "github.com": "sha256-VbH6fHnent2TtbYxbNoatK4RNkY3MVPXokJhRzPZBg8=",
        "gitlab.com": "sha256-3w3ImvW4t/H2eMkZbUH+F1zkARSI3cIJSgJFg4ULPU4="
      }
    }
  }
}
```

#### 2. Add the `download_archives` repo to `MODULE.bazel`

Then, add the following to `MODULE.bazel`:

```starlark
download_archives = use_repo_rule("@download_archives//download/archives:defs.bzl", "download_archives")

download_archives(
    name = "wget_src",
    index = "//third-party/wget:repo.json",
    # NOTE:
    # This is how you would add a custom patch for one of the versions. See
    # "Patching" docs for more information about patches.
    # patches = {
    #    "//third-party/wget/patches:0001-1.24.5-test-patch.patch": ">=1.24.5/*",
    # },
    # NOTE:
    # This is needed because the archives have different integrity across the
    # mirrors (see v1.21.3)
    strict_integrity = False,
)
```

#### 3. Test it

To test the Bazel repo, run `bazel fetch @wget_src`. This will attempt to
download and extract all the versions defined in the repo index from the
available sources.

As mentioned before, it will stop downloading any other source for a specific
version when there's a successful download from one source. And, if all
downloads from all sources of a given version fail, it will `fail` with an
error.

Note that in the `repo.json` JSON index file there's one `integrity` missing
for one of the sources (version `1.24.5`, source `github.com`). When this
happens a warning message is printed when the archive download begins asking
the user to add the integrity to the index. And, if the archive is successfully
downloaded, a message with the [Subresource Integrity (SRI)] (`integrity`) and
`SHA256` hex digest will be printed so that it's easy to copy-paste one of them
in the index.

Also note that we set `strict_integrity = False` because the archives for
version `1.21.3` have different integrity hashes across sources. With
`strict_integrity = True`, this would cause the download to fail. Since this
can make builds non-reproducible, the default remains `True`. The option exists
because many artifacts share identical source code but differ in packaging or
other details, resulting in mismatched integrities.

Once installed, the `@wget_src` repo will have the following:

- helper constants available to import from `@wget_src//:repo.bzl`:
  - `REPO_NAME = "wget_src"`
  - `VERSIONS = {"1.24.5": "github.com", "1.21.3": "github.com"}`
  - `DEFAULT_VERSION = "1.24.5"`
  - `LOCK = {...}` (the contents of the repo `lock.json`)

- specific `<VERSION>/<SOURCE>` repos:
  - `@wget_src//1.24.5/github.com`
  - `@wget_src//1.21.3/github.com`

- `alias` repos:
  - `@wget_src` --> `@wget_src//1.24.5/github.com`
  - `@wget_src//1.24.5` --> `@wget_src//1.24.5/github.com`
  - `@wget_src//1.21.3` --> `@wget_src//1.21.3/github.com`

<details>
<summary><h4>More details</h4></summary>

To list all the targets in the repo, run `bazel query @wget_src//...`:

```sh
@wget_src//:dir
@wget_src//:files
@wget_src//:wget_src
@wget_src//1.21.3:1.21.3
@wget_src//1.21.3:dir
@wget_src//1.21.3:files
@wget_src//1.21.3/github.com:dir
@wget_src//1.21.3/github.com:files
@wget_src//1.21.3/github.com:github.com
@wget_src//1.24.5:1.24.5
@wget_src//1.24.5:dir
@wget_src//1.24.5:files
@wget_src//1.24.5/github.com:dir
@wget_src//1.24.5/github.com:files
@wget_src//1.24.5/github.com:github.com
```

In cases where we have many versions and sources in the index we can select the
versions and/or sources from which to download using the `versions` and
`sources` arguments:

```starlark
download_archives(
    name = "wget_src",
    index = "//third-party/wget:repo.json",
    versions = ["1.21.3"],
    sources = ["gitlab.com"],
)
```

Selecting `versions` and `sources` changes what's installed and available in
the `@wget_src` repo:

- helper constants available to import from `@wget_src//:repo.bzl`:
  - `REPO_NAME = "wget_src"`
  - `VERSIONS = {"1.21.3": "gitlab.com"}`
  - `DEFAULT_VERSION = "1.21.3"`

- specific `<VERSION>/<SOURCE>` repos:
  - `@wget_src//1.21.3/gitlab.com`

- `alias` repos:
  - `@wget_src` --> `@wget_src//1.21.3/gitlab.com`
  - `@wget_src//1.21.3` --> `@wget_src//1.21.3/gitlab.com`

Again, let's list all the targets with `bazel query @wget_src//...`:

```sh
@wget_src//:dir
@wget_src//:files
@wget_src//:wget_src
@wget_src//1.21.3:1.21.3
@wget_src//1.21.3:dir
@wget_src//1.21.3:files
@wget_src//1.21.3/gitlab.com:dir
@wget_src//1.21.3/gitlab.com:files
@wget_src//1.21.3/gitlab.com:gitlab.com
```

Similarly, remember that the sources are used as "mirrors" so if the first one
fails to download, the next source will be attempted. Thus, the `VERSIONS`
helper constant, the `alias` repos and the repo `lock.json` will all change
accordingly.

For example, imagine that `github` has version `1.24.5` available but not
`1.21.3`. Then, the download will fall back to the `gitlab.com` source and, if
successful, the `@wget_src` repo will have the following:

- helper constants available to import from `@wget_src//:repo.bzl`:
  - `REPO_NAME = "wget_src"`
  - `VERSIONS = {"1.24.5": "github.com", "1.21.3": "gitlab.com"}`
  - `DEFAULT_VERSION = "1.24.5"`
  - `LOCK = {...}` (the new contents of the repo `lock.json`)

- specific `<VERSION>/<SOURCE>` repos:
  - `@wget_src//1.24.5/github.com`
  - `@wget_src//1.21.3/gitlab.com`

- `alias` repos:
  - `@wget_src` --> `@wget_src//1.24.5/github`
  - `@wget_src//1.24.5` --> `@wget_src//1.24.5/github.com`
  - `@wget_src//1.21.3` --> `@wget_src//1.21.3/gitlab.com`


In this case, the list of targets would look like:

```sh
@wget_src//:dir
@wget_src//:files
@wget_src//:wget_src
@wget_src//1.21.3:1.21.3
@wget_src//1.21.3:dir
@wget_src//1.21.3:files
@wget_src//1.21.3/gitlab.com:dir
@wget_src//1.21.3/gitlab.com:files
@wget_src//1.21.3/gitlab.com:gitlab.com
@wget_src//1.24.5:1.24.5
@wget_src//1.24.5:dir
@wget_src//1.24.5:files
@wget_src//1.24.5/github.com:dir
@wget_src//1.24.5/github.com:files
@wget_src//1.24.5/github.com:github.com
```

</details>

### Per-version downloads (module extension)

For repositories with many versions, use the `download_archives` module
extension from `extensions.bzl` instead of this rule. The module extension
creates one download repository per version, so archives are only downloaded
when a build references a specific version:

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
"""

_DOC = (
    _DOC_INTRO +
    _DOC_SELECTING +
    _DOC_MATRIX +
    DOC_VERSION_SCHEME +
    DOC_PATCHING +
    _DOC_USAGE +
    DOC_LINK_REFS
)

_REPO = '''\
"""Generated by download_archives. DO NOT EDIT."""

REPO_NAME = "{repo_name}"
VERSIONS = {versions}
DEFAULT_VERSION = "{default_version}"
METADATA = {metadata}
LOCK = {lock}
'''

_BUILD_TARGETS = """
alias(
    name = "files",
    actual = "{actual_prefix}:files",
)

alias(
    name = "dir",
    actual = "{actual_prefix}:dir",
)

alias(
    name = "{alias}",
    actual = ":files",
)
{outputs}"""

# One target per `output` subpath rendered by the index `matrix`, so that
# consumers can depend on one partition of the extracted tree instead of on
# all of it. Without a `matrix`, or without an `output`, there are none of
# these and ':files' is the only way in, as before.
_BUILD_OUTPUT_FILEGROUP = """
filegroup(
    name = "{output}",
    srcs = glob(["{output}/**"]),
)
"""

_BUILD_OUTPUT_ALIAS = """
alias(
    name = "{output}",
    actual = "{actual_prefix}:{output}",
)
"""

_BUILD_ROOT_EXPORTS = """
exports_files([
    "repo.bzl",
    "index.json",
    "lock.json",
    "metadata.json",
])

bzl_library(
    name = "repo",
    srcs = ["repo.bzl"],
)
"""

_BUILD_ROOT = '''\
"""Generated by download_archives. DO NOT EDIT."""

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("//{version}:source.bzl", "SOURCE")

package(default_visibility = ["//visibility:public"])
''' + _BUILD_ROOT_EXPORTS + '''\
VERSION = "{version}"
''' + _BUILD_TARGETS

_BUILD_VERSION = '''\
"""Generated by download_archives. DO NOT EDIT."""

load("//{version}:source.bzl", "SOURCE")

package(default_visibility = ["//visibility:public"])

VERSION = "{version}"
''' + _BUILD_TARGETS

_SOURCE_BZL_LAZY = '''\
"""Generated by download_archives. DO NOT EDIT."""

load("@{dl_repo}//{version}:source.bzl", _SOURCE = "SOURCE", _URL = "URL")

SOURCE = _SOURCE
URL = _URL
'''

_BUILD_SOURCE = '''\
"""Generated by download_archives. DO NOT EDIT."""

# source packages are only visible to their version package
package(default_visibility = ["//:__subpackages__"])

filegroup(
    name = "files",
    srcs = glob(["**"]),
)

# NOTE:
# When using ':dir' we get a warning:
#   WARNING: input '' of <TARGET> is a directory;
#   dependency checking of directories is unsound
# but... yeah, sometimes, we really just want the directory!
filegroup(
    name = "dir",
    srcs = ["."],
)

alias(
    name = "{alias}",
    actual = ":files",
)
{outputs}'''

def _build_outputs(template, outputs, **kwargs):
    """Render one `template` block per `output`, in index `matrix` order."""
    return "".join([
        template.format(output = output, **kwargs)
        for output in outputs
    ])

def _apparent_repo_name(rctx):
    # HACK to get the apparent repo name ("short name"). This should be
    # equivalent to native.package_relative_label but that's only available
    # for macros, not rules.
    apparent_repo_name = rctx.name.split("~")[-1]

    if native.bazel_version and native.bazel_version >= "8.0.0":
        apparent_repo_name = apparent_repo_name.split("+")[-1]

    return apparent_repo_name

def _impl(rctx, _print = print, _fail = fail):
    repo_name = _apparent_repo_name(rctx)

    msg = "{}: parsing repo index: {}".format(repo_name, rctx.attr.index)
    rctx.report_progress(msg)

    index_json = rctx.read(rctx.attr.index)

    index = Index.new(
        repo_name,
        index_json,
        rctx.attr.versions,
        rctx.attr.sources,
    )

    rctx.report_progress("{}: creating repo".format(repo_name))

    lazy = rctx.attr.lazy
    repo_lock = {}
    repo_outputs = {}
    failed_versions = []

    for version, repos in index.repos.items():
        if lazy:
            first_repo = repos[0]
            dl_repo_name = "%s-%s" % (repo_name, version)

            dl = struct(
                source = first_repo.source,
                url = first_repo.context["url"],
                integrity = first_repo.context.get("integrity", ""),
                # The outputs don't depend on the source that ends up winning
                # the download, so they can be rendered here, without knowing
                # it, and aliased into the download repo.
                outputs = Utils.dedupe([
                    ctx.output
                    for ctx in first_repo.contexts
                    if ctx.output
                ]),
                patches = [],
            )
            actual_prefix = "@%s//%s" % (dl_repo_name, version)

            rctx.file(
                "%s/source.bzl" % version,
                _SOURCE_BZL_LAZY.format(dl_repo = dl_repo_name, version = version),
                executable = False,
            )
        else:
            dl = Download.try_sources(
                rctx,
                repo_name,
                version,
                repos,
                patches = rctx.attr.patches,
                spec_syntax = rctx.attr.spec_syntax,
                version_scheme = rctx.attr.version_scheme,
                strict_integrity = rctx.attr.strict_integrity,
                _print = _print,
                _fail = _fail,
            )

            if not dl:
                failed_versions.append(version)
                continue

            actual_prefix = "//%s/%s" % (version, dl.source)

            rctx.file(
                "%s/%s/BUILD.bazel" % (version, dl.source),
                _BUILD_SOURCE.format(
                    alias = dl.source,
                    version = version,
                    outputs = _build_outputs(
                        _BUILD_OUTPUT_FILEGROUP,
                        dl.outputs,
                    ),
                ),
                executable = False,
            )

        repo_outputs[version] = dl.outputs

        repo_lock[version] = dict(
            source = dl.source,
            url = dl.url,
            integrity = dl.integrity,
            patches = [str(p) for p in dl.patches] if dl.patches else None,
        )

        rctx.file(
            "%s/BUILD.bazel" % version,
            _BUILD_VERSION.format(
                version = version,
                actual_prefix = actual_prefix,
                alias = version,
                outputs = _build_outputs(
                    _BUILD_OUTPUT_ALIAS,
                    dl.outputs,
                    actual_prefix = actual_prefix,
                ),
            ),
            executable = False,
        )

    if failed_versions:
        msg = "{}: failed to download all sources for versions: {}"
        _fail(msg.format(repo_name, failed_versions))

    versions = {version: repo["source"] for version, repo in repo_lock.items()}
    default_version = versions.keys()[0]

    if rctx.attr.lazy:
        actual_prefix = "//%s" % default_version
    else:
        actual_prefix = "//%s/%s" % (default_version, versions[default_version])

    rctx.file(
        "BUILD.bazel",
        _BUILD_ROOT.format(
            version = default_version,
            actual_prefix = actual_prefix,
            alias = repo_name,
            outputs = _build_outputs(
                _BUILD_OUTPUT_ALIAS,
                repo_outputs[default_version],
                actual_prefix = actual_prefix,
            ),
        ),
        executable = False,
    )

    rctx.file(
        "repo.bzl",
        _REPO.format(
            repo_name = repo_name,
            versions = versions,
            default_version = default_version,
            metadata = index.metadata,
            lock = repo_lock,
        ),
        executable = False,
    )

    rctx.file(
        "index.json",
        index_json,
        executable = False,
    )
    rctx.file(
        "lock.json",
        json.encode_indent(repo_lock, indent = "  "),
        executable = False,
    )

    rctx.file(
        "metadata.json",
        json.encode_indent(index.metadata, indent = "  "),
        executable = False,
    )

ATTRS = dict(
    index = attr.label(
        doc = "Label of the repo JSON index file.",
        allow_single_file = True,
        mandatory = True,
    ),
    versions = attr.string_list(
        doc = """
        Versions of the archive to download. If none is specified it will
        download all of the versions available in the repo index.
        """,
    ),
    sources = attr.string_list(
        doc = """
        Source names from which to download the archive. If none, all sources
        from the index are tried in order.
        """,
    ),
    # TODO: in 7.4 we can use string_keyed_label_dict
    patches = attr.label_keyed_string_dict(
        doc = """
        Diff files to apply as patches at the root of the downloaded archive.
        The `dict` values represent "patch specs" in the
        `<VERSION_SPEC>/<SOURCE>` format, and determine when patches apply to
        the downloaded archive. Patches must be in standard [unified diff
        format], created from the root of the archive. All patches are applied
        from the root of the archive with `patch -p1`. For more details, see
        ["Patching"].
        """,
    ),
    spec_syntax = attr.string(
        default = Spec.SYNTAX.SIMPLE,
        doc = """
        The syntax of the version constraints specification. The available
        syntaxes are those supported by `version_utils` (see `SYNTAX` in
        [`version_utils`' `spec`
        extension](https://github.com/jjmaestro/bazel_version_utils/blob/main/spec/spec.bzl)).
        Defaults to `SYNTAX.SIMPLE`.
        """,
    ),
    version_scheme = attr.string(
        default = Version.SCHEME.SEMVER,
        doc = """
        The scheme of the versions in `index` and `patches`. The available
        version schemes are those supported by `version_utils` (see `SCHEME` in
        [`version_utils`' `version`
        extension](https://github.com/jjmaestro/bazel_version_utils/blob/main/version/version.bzl)).
        Defaults to `SCHEME.SEMVER`.
        """,
    ),
    strict_integrity = attr.bool(
        default = True,
        doc = """
        If `True`, all sources of a given archive version must share the same
        integrity hash. If they differ, the download will fail. Defaults to
        `True`.
        """,
    ),
)

_ATTRS = ATTRS | dict(
    lazy = attr.bool(
        default = False,
        doc = """
        Internal. When True, creates index-only repos with stub BUILD files
        that alias to per-version download repositories instead of downloading
        archives eagerly. Used by the `download_archives` module extension,
        should not be set directly.
        """,
    ),
)

archives = repository_rule(
    doc = _DOC,
    attrs = _ATTRS,
    implementation = _impl,
)
