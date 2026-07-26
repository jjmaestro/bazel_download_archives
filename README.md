# `download_archives`

[![pre-commit](
    ../../actions/workflows/pre-commit.yaml/badge.svg
)](../../actions/workflows/pre-commit.yaml)
[![CI](
    ../../actions/workflows/ci.yaml/badge.svg
)](../../actions/workflows/ci.yaml)

Bazel module to manage multi-version, multi-source archive repositories. Define
your versions and sources once in a JSON index, and Bazel downloads only what
your build actually needs.

## 📦 Install

Make sure you are running Bazel with [Bzlmod]. Then, add the module as a
dependency in your `MODULE.bazel`:

```starlark
bazel_dep(name = "download_archives", version = "<VERSION>")
```

<details>
<summary><h3>Non-registry overrides</h3></summary>

If you need to use a specific commit or version tag from the repo instead of a
version from the registry, add a [non-registry override] in your `MODULE.bazel`
file, e.g. [`archive_override`]:

<!-- markdownlint-capture -->
<!-- markdownlint-disable MD013 -->
```starlark
REF = "v<VERSION>"  # NOTE: can be a repo tag or a commit hash

archive_override(
    module_name = "download_archives",
    integrity = "",  # TODO: copy the SRI hash that Bazel prints when fetching
    strip_prefix = "bazel_download_archives-%s" % REF.strip("v"),
    urls = ["https://github.com/jjmaestro/bazel_download_archives/archive/%s.tar.gz" % REF],
)
```
<!-- markdownlint-restore -->

**NOTE**:
`integrity` is intentionally empty so Bazel will warn and print the SRI hash of
the downloaded artifact. **Leaving it empty is a security risk**. Always verify
the contents of the downloaded artifact, copy the printed hash and update
`MODULE.bazel` accordingly.

</details>

## 🚀 Getting Started

Here's how to create a `@wget_src` repo for [GNU wget] with two mirror sources:

### 1. Create the repo index

Create a package with a `repo.json` [index file][repo JSON index] that declares
the download sources and versions:

```sh
mkdir -p third-party/wget
touch third-party/wget/BUILD.bazel
```

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

Source contexts can be templated with `{placeholders}` that are [materialized]
from the combined source and version context. See the [repo JSON index] docs
for details.

### 2. Add to `MODULE.bazel`

#### Module extension (lazy, recommended)

The [module extension] creates a lightweight index repo and downloads each
version on demand (lazily), only when your build actually references it:

```starlark
download = use_extension(
    "@download_archives//download/archives:extensions.bzl",
    "download_archives",
)

download.archives(
    name = "wget_src",
    index = "//third-party/wget:repo.json",
)

use_repo(download, "wget_src")
```

#### Repository rule (eager)

Alternatively, use the [repository rule] directly. This downloads all declared
versions eagerly when the repo is first fetched:

```starlark
download_archives = use_repo_rule(
    "@download_archives//download/archives:defs.bzl",
    "download_archives",
)

download_archives(
    name = "wget_src",
    index = "//third-party/wget:repo.json",
)
```

### 3. Test it

Fetch the repo and list its targets:

```sh
bazel fetch @wget_src
bazel query @wget_src//...
```

To build against a specific version:

```starlark
# BUILD.bazel
cc_binary(
    name = "my_tool",
    srcs = ["main.c"],
    data = ["@wget_src//1.24.5:files"],
)
```

## ✨ Features

- **Lazy per-version downloads**: only fetch what your build needs
- **Multi-source failover**: mirrors tried in order, transparent to the build
- **Archive [`matrix`]**: for versions published as a *set* of archives (e.g. a
  toolchain, one archive per target triple and component), download every
  combination and either merge them into one tree or partition it, one target
  per partition
- **Patching**: apply patches selectively by version and/or source using
  [version spec][patching] patterns (e.g. `>=1.24.5/*`, `<2.0.0/github.com`)
- **Integrity checking**: [SRI hashes][Subresource Integrity (SRI)] per source
  with optional [`strict_integrity`] mode requiring all sources to agree
- **Source tracking**: `source.bzl` records which source and URL were used
- **Custom version schemes**: supports [semantic versioning] by default, with
  pluggable schemes via [`version_utils`]

## ⚙️ How it works

### Lazy mode (module extension)

The module extension creates two kinds of repositories:

- **Index repo** (`@<NAME>`): created immediately. Parses the JSON index,
  generates per-version BUILD files with aliases pointing to download repos,
  and writes repo metadata (`repo.bzl`, `index.json`). No archives are
  downloaded.

- **Download repos** (`@<NAME>-<VERSION>`): one per version, created on demand.
  Each downloads and extracts its version from the first source that succeeds.

When you reference `@wget_src//1.24.5:files`, Bazel resolves the alias in the
index repo and fetches only the `@wget_src-1.24.5` download repo.

### Eager mode (repository rule)

When using `use_repo_rule`, all versions are downloaded eagerly in a single
repository rule evaluation. Simpler, but slower for large indices with many
versions.

### Multi-source failover

Sources are tried in order. If a download fails, the next source is attempted.
The download only fails if all sources are exhausted.

### Archive `matrix`

Some archives are published as a *set* of files per version rather than as a
single file. The index [`matrix`] declares the axes of that set (e.g. `triple`
and `component`) and the version is downloaded once per combination.

The index `output` template then decides the subpath each combination is
extracted into: combinations that render the same `output` *merge* into one
tree, the rest *partition* it, and every rendered `output` gets a target of its
own, e.g. `@rust_toolchain//1.97.1:x86_64-unknown-linux-gnu`.

A source is only used if *all* of its combinations download, so a partial
mirror falls through to the next source instead of leaving behind a
half-materialized tree.

### Source tracking

Each version's package includes a `source.bzl` file that exports `SOURCE` (the
source name that succeeded) and `URL` (the URL that was used). This makes it
easy to audit which mirror actually provided each archive:

```starlark
load("@wget_src//1.24.5:source.bzl", "SOURCE", "URL")
```

## 📄 [Docs]

- [`download/archives` repository rule]
- [`download/archives` module extension]
- [`lib/index`]

## 💡 Contributing

Please feel free to open [issues] and [PRs], contributions are always welcome!
See [CONTRIBUTING.md] for more info on how to work with this repo.

[Bzlmod]: https://bazel.build/external/migration
[CONTRIBUTING.md]: CONTRIBUTING.md
[Docs]: docs/README.md
[GNU wget]: https://www.gnu.org/software/wget/
[PRs]: ../../pulls
[Subresource Integrity (SRI)]: https://w3c.github.io/webappsec-subresource-integrity/
[`archive_override`]: https://bazel.build/rules/lib/globals/module#archive_override
[`download/archives` module extension]: docs/download/archives/extensions.md
[`download/archives` repository rule]: docs/download/archives/repository.md
[`lib/index`]: docs/lib/index.md
[`matrix`]: docs/lib/index.md#matrix
[`strict_integrity`]: docs/download/archives/repository.md
[`version_utils`]: https://github.com/jjmaestro/bazel_version_utils
[issues]: ../../issues
[materialized]: docs/lib/index.md#materialized-repo-context
[module extension]: docs/download/archives/extensions.md
[non-registry override]: https://bazel.build/external/module#non-registry_overrides
[patching]: docs/download/archives/repository.md#patching
[repo JSON index]: docs/lib/index.md
[repository rule]: docs/download/archives/repository.md
[semantic versioning]: https://semver.org
