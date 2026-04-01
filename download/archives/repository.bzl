"""
# `archives` repository rule

Repository rule to create and maintain Bazel external repos. It helps reduce
boilerplate code by keeping a JSON index file with all of the metadata required
to download and extract an archive: the archive's `version`(s) and the
`source`(s) from which to try to download the archive.
"""

load("@version_utils//spec:spec.bzl", Spec = "spec")
load("@version_utils//version:version.bzl", Version = "version")
load("//lib:index.bzl", Index = "index")

DOC = """
This repository rule wraps [`rctx.download_and_extract`] and creates a Bazel
repo under `@<REPO_NAME>`, downloading and extracting *one archive* from *one*
of the sources for *each* of the archive versions in the [repo JSON index].

When downloading the archive, if a source fails it will try the next one, and
only fail if all sources are exhausted.

To construct the arguments passed to [`rctx.download_and_extract`] it uses the
["materialized repo `context`"], which includes at minimum the materialized
`url` from which to download the archive.

### Repo structure

```
  @<REPO_NAME>/
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

- `@<REPO_NAME>//:<REPO_NAME>`: points to the `:files` target of the
  `DEFAULT_VERSION`.
- `@<REPO_NAME>//:<TARGET>`: points to the specific `TARGET` of the
  `DEFAULT_VERSION`.
- `@<REPO_NAME>//<VERSION>:<TARGET>`: points to the specific `TARGET` of that
  `VERSION`.

The `archives` repository rule creates a `@<REPO_NAME>` Bazel repo with a
public `//<VERSION>` package for every version in the index.

Each `//<VERSION>` package has three targets:
- `:files`: to access all the files in the downloaded archive.
- `:dir`: the path to the directory where the archive was extracted.
- `:<VERSION>`: `alias` of `:files`.

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
- `:<REPO_NAME>`: `alias` of `:files`.

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

["Patching"]: #patching
[Subresource Integrity (SRI)]: https://w3c.github.io/webappsec-subresource-integrity/
["materialized repo `context`"]: ../../lib/index.md#materialized-repo-context
[`rctx.download_and_extract`]: https://bazel.build/rules/lib/builtins/repository_ctx#download_and_extract
[repo JSON index]: ../../lib/index.md

### Selecting `versions` and `sources`

Users can also override the default selection of versions and sources with the
`versions` and `sources` arguments.

Note that selecting specific versions and/or arguments will change the values
of `VERSIONS` and `DEFAULT_VERSION`.

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
+[`version_utils` `spec` extension]: https://github.com/jjmaestro/bazel_version_utils/blob/main/docs/specs/spec.md
[`git format-patch`]: https://git-scm.com/docs/git-format-patch

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
"""

REPO = '''\
"""Generated by download_archives. DO NOT EDIT."""

REPO_NAME = "{repo_name}"
VERSIONS = {versions}
DEFAULT_VERSION = "{default_version}"
METADATA = {metadata}
LOCK = {lock}
'''

BUILD_TARGETS = """
alias(
    name = "files",
    actual = "//{{}}/{{}}:files".format(VERSION, SOURCE),
)

alias(
    name = "dir",
    actual = "//{{}}/{{}}:dir".format(VERSION, SOURCE),
)

alias(
    name = "{alias}",
    actual = ":files",
)
"""

BUILD_ROOT = '''\
"""Generated by download_archives. DO NOT EDIT."""

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("//:repo.bzl", "DEFAULT_VERSION", "VERSIONS")

package(default_visibility = ["//visibility:public"])

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

VERSION = DEFAULT_VERSION

SOURCE = VERSIONS[VERSION]
''' + BUILD_TARGETS

BUILD_VERSION = '''\
"""Generated by download_archives. DO NOT EDIT."""

load("//:repo.bzl", "VERSIONS")

package(default_visibility = ["//visibility:public"])

VERSION = "{version}"

SOURCE = VERSIONS[VERSION]
''' + BUILD_TARGETS

BUILD_SOURCE = '''\
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
'''

BUILD_PATCHES = '''\
"""Generated by download_archives. DO NOT EDIT."""

package(default_visibility = ["//visibility:public"])

exports_files(glob(
    [
        "*.patch",
        "*.diff",
    ],
    allow_empty = True,
))
'''

def _should_apply_patch(pattern_spec, version, source, spec_syntax, version_scheme):
    if "/" in pattern_spec:
        cspec, csource = pattern_spec.split("/", 1)
    else:
        cspec, csource = pattern_spec, "*"

    spec = Spec.new(cspec, syntax = spec_syntax, version_scheme = version_scheme)

    return spec.match(version) and (csource == "*" or csource == source)

def _apply_patch(rctx, version, source, patch):
    patch_content = rctx.read(patch)

    # NOTE:
    # The patches are generated from the root of the repo but the archives are
    # extracted into /version/source so the patch has to be modified to match
    # the new path in the Bazel repo
    for letter in ("a", "b"):
        for prefix in ("git %s/", "--- %s/", "+++ %s/"):
            patch_content = patch_content.replace(
                prefix % letter,
                (prefix % letter) + "%s/%s/" % (version, source),
            )

    patch_path = "patches/%s/%s" % (version, source)
    rctx.file("%s/BUILD.bazel" % patch_path, BUILD_PATCHES, executable = False)

    patch_file = "%s/%s" % (patch_path, patch.name)
    rctx.file(patch_file, patch_content, executable = False)

    rctx.patch(patch_file, strip = 1)

def _make_download_args(repo_path, repo_context, _print = print):
    # https://bazel.build/rules/lib/builtins/repository_ctx#download_and_extract
    allowed = [
        "url",
        "sha256",
        "type",
        "strip_prefix",
        "canonical_id",
        "auth",
        "headers",
        "integrity",
        "rename_files",
    ]

    # output and allow_fail cannot be exposed to the users: output is fixed and
    # allow_fail has to be True to attempt the downloads from the different
    # sources
    ignored = ["output", "allow_fail"]

    args = {}

    for arg in allowed + ignored:
        if arg not in repo_context:
            continue

        if arg in ignored:
            msg = "{}: ignoring '{}' in context"
            _print(msg.format(repo_path, arg))
            continue

        if (
            arg == "strip_prefix" and
            native.bazel_version and native.bazel_version < "8.0.0"
        ):
            # https://github.com/bazelbuild/bazel/issues/24034
            args["stripPrefix"] = repo_context[arg]
        else:
            args[arg] = repo_context[arg]

    # Bazel download expects either 'sha256' or 'integrity' but not both.
    # And, even when we've validated the index to prevent the users from using
    # both, we are actually adding both to the context, so we need to remove it
    # here to have compatible arguments for the download method
    if "sha256" in args and "integrity" in args:
        args.pop("sha256")

    return args

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
    rctx.file(
        "BUILD.bazel",
        BUILD_ROOT.format(alias = repo_name),
        executable = False,
    )

    repo_lock = {}
    failed_downloads = {}

    for version, repos in index.repos.items():
        if rctx.attr.strict_integrity:
            integrities = {
                repo.context["integrity"]: None
                for repo in repos
                if repo.context.get("integrity", None) != None
            }

            if len(integrities) >= 2:
                msg = "Version {} has {} different integrities "
                msg += "while strict_integrity=True"
                _fail(msg.format(version, len(integrities)))

        for repo in repos:
            if version in repo_lock:
                if not rctx.attr.strict_integrity:
                    # we've already successfully downloaded one of the sources
                    # and the integrity is the same or strict_integrity is False
                    continue

                # check for the case where the integrity of the downloaded
                # version was None but was set for the second+ source
                integrity_repo = repo.context.get("integrity", False)
                integrity_down = repo_lock[version]["integrity"]

                if integrity_repo and integrity_repo != integrity_down:
                    msg = "Integrity mismatch between downloaded ('{}') and "
                    msg += "other source(s) ('{}') while strict_integrity=True "
                    msg += "for version {}"
                    _fail(msg.format(repo_lock[version]["source"], repo.source, version))

                continue

            repo_path = "/".join([repo.version, repo.source])
            download_args = _make_download_args(repo_path, repo.context)

            download = rctx.download_and_extract(
                output = repo_path,
                allow_fail = True,
                **download_args
            )

            if not download.success:
                if version not in failed_downloads:
                    failed_downloads[version] = []
                failed_downloads[version].append(repo.source)
                continue

            if "integrity" not in repo.context:
                msg = "{}/{}: WARNING: integrity missing. "
                msg += "Please add the integrity / sha256 to the index: {} / {}"
                _print(msg.format(repo_name, repo_path, download.integrity, download.sha256))

            repo_lock[repo.version] = dict(
                source = repo.source,
                url = repo.context["url"],
                integrity = download.integrity,
                patches = None,
            )

            alias = "{}".format(repo.version)
            rctx.file(
                "%s/BUILD.bazel" % repo.version,
                BUILD_VERSION.format(alias = alias, version = repo.version),
                executable = False,
            )

            alias = "{}".format(repo.source)
            rctx.file(
                "%s/BUILD.bazel" % repo_path,
                BUILD_SOURCE.format(alias = alias, version = repo.version),
                executable = False,
            )

            applied_patches = []

            for patch, pattern_spec in rctx.attr.patches.items():
                should_apply = _should_apply_patch(
                    pattern_spec,
                    repo.version,
                    repo.source,
                    rctx.attr.spec_syntax,
                    rctx.attr.version_scheme,
                )

                if should_apply:
                    _apply_patch(rctx, repo.version, repo.source, patch)
                    applied_patches.append(str(patch))

            if applied_patches:
                repo_lock[repo.version]["patches"] = applied_patches

    failed_all_versions = []
    for version, failures in failed_downloads.items():
        if len(failures) == len(index.repos[version]):
            failed_all_versions.append(version)

    if failed_all_versions:
        msg = "{}: failed to download all sources for versions: {}"
        _fail(msg.format(repo_name, failed_all_versions))

    versions = {version: repo["source"] for version, repo in repo_lock.items()}
    default_version = versions.keys()[0]

    rctx.file(
        "repo.bzl",
        REPO.format(
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
        doc = "Label of the repo JSON index",
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
        Source names from which to download the archive. If none is specified,
        it will use all of the sources available in the repo index to try to
        download and extract the archive.
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

archives = repository_rule(
    doc = DOC,
    attrs = ATTRS,
    implementation = _impl,
)
