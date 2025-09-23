<!-- Generated with Stardoc: http://skydoc.bazel.build -->

# `archives` repository rule

Repository rule to create and maintain Bazel external repos. It helps reduce
boilerplate code by keeping a JSON index file with all of the metadata required
to download and extract an archive: the archive's `version`(s) and the
`source`(s) from which to try to download the archive.

<a id="archives"></a>

## archives

<pre>
load("@download_archives//download/archives:repository.bzl", "archives")

archives(<a href="#archives-name">name</a>, <a href="#archives-index">index</a>, <a href="#archives-patches">patches</a>, <a href="#archives-repo_mapping">repo_mapping</a>, <a href="#archives-sources">sources</a>, <a href="#archives-spec_syntax">spec_syntax</a>, <a href="#archives-version_scheme">version_scheme</a>, <a href="#archives-versions">versions</a>)
</pre>

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
  - `SOURCES`: a mapping of the downloaded `version`s to the `source` from
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
        "github.com": "sha256-VbH6fHnent2TtbYxbNoatK4RNkY3MVPXokJhRzPZBg8=",
        "gitlab.com": "sha256-3w3ImvW4t/H2eMkZbUH+F1zkARSI3cIJSgJFg4ULPU4="
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

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="archives-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="archives-index"></a>index |  Label of the repo JSON index   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="archives-patches"></a>patches |  Diff files to apply as patches at the root of the downloaded archive. The `dict` values represent "patch specs" in the `<VERSION_SPEC>/<SOURCE>` format, and determine when patches apply to the downloaded archive. Patches must be in standard [unified diff format], created from the root of the archive. All patches are applied from the root of the archive with `patch -p1`. For more details, see ["Patching"].   | <a href="https://bazel.build/rules/lib/dict">Dictionary: Label -> String</a> | optional |  `{}`  |
| <a id="archives-repo_mapping"></a>repo_mapping |  In `WORKSPACE` context only: a dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.<br><br>For example, an entry `"@foo": "@bar"` declares that, for any time this repository depends on `@foo` (such as a dependency on `@foo//some:target`, it should actually resolve that dependency within globally-declared `@bar` (`@bar//some:target`).<br><br>This attribute is _not_ supported in `MODULE.bazel` context (when invoking a repository rule inside a module extension's implementation function).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  |
| <a id="archives-sources"></a>sources |  Source names from which to download the archive. If none is specified, it will use all of the sources available in the repo index to try to download and extract the archive.   | List of strings | optional |  `[]`  |
| <a id="archives-spec_syntax"></a>spec_syntax |  The syntax of the version constraints specification. The available syntaxes are those supported by `version_utils` (see `SYNTAX` in [`version_utils`' `spec` extension](https://github.com/jjmaestro/bazel_version_utils/blob/main/spec/spec.bzl)). Defaults to `SYNTAX.SIMPLE`.   | String | optional |  `"simple"`  |
| <a id="archives-version_scheme"></a>version_scheme |  The scheme of the versions in `index` and `patches`. The available version schemes are those supported by `version_utils` (see `SCHEME` in [`version_utils`' `version` extension](https://github.com/jjmaestro/bazel_version_utils/blob/main/version/version.bzl)). Defaults to `SCHEME.SEMVER`.   | String | optional |  `"semver"`  |
| <a id="archives-versions"></a>versions |  Versions of the archive to download. If none is specified it will download all of the versions available in the repo index.   | List of strings | optional |  `[]`  |


