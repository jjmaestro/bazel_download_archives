# `download_archives`

[![pre-commit](
    ../../actions/workflows/pre-commit.yaml/badge.svg
)](../../actions/workflows/pre-commit.yaml)
[![CI](
    ../../actions/workflows/ci.yaml/badge.svg
)](../../actions/workflows/ci.yaml)

Bazel module to help create and maintain Bazel external repos.

## 📦 Install

First, make sure you are running Bazel with [Bzlmod]. Then, add the module as a
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

[`download_archives`] is a [repository rule] to create and maintain Bazel
external repos. It helps reduce boilerplate code by keeping a JSON index file
with all of the metadata required to download and extract an archive: the
archive's `version`(s) and the `source`(s) from which to try to download the
archive.

This repository rule wraps [`rctx.download_and_extract`] and creates a Bazel
repo under `@<REPO_NAME>`, downloading and extracting *one archive* from *one*
of the sources for *each* of the archive versions in the [repo JSON index].

When downloading the archive, if a source fails it will try the next one, and
only fail if all sources are exhausted.

On top of just reducing boilerplate code, the `download_archives` repository
rule also adds helper constants and `alias`es to the Bazel repo. Please read
the docs for more information about all of their additional functionality.

Here's an example that shows how to create a `@wget_src` repo for [GNU wget]:

### 1. Create the repo index

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

### 2. Add the `download_archives` repo to `MODULE.bazel`

Then, add the following to `MODULE.bazel`:

<!-- markdownlint-capture -->
<!-- markdownlint-disable MD013 -->
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
<!-- markdownlint-restore -->

### 3. Test it

To test the Bazel repo, run `bazel fetch @wget_src`. This will attempt to
download and extract all the versions defined in the repo index from the
available sources.

And, to list all the targets in the repo, run `bazel query @wget_src//...`.

## 📄 [Docs]

* [`download/archives`]
* [`lib/index`]

## 💡 Contributing

Please feel free to open [issues] and [PRs], contributions are always welcome!
See [CONTRIBUTING.md] for more info on how to work with this repo.

[Bzlmod]: https://bazel.build/external/migration
[CONTRIBUTING.md]: CONTRIBUTING.md
[Docs]: docs/README.md
[GNU wget]: https://www.gnu.org/software/wget/
[PRs]: ../../pulls
[`archive_override`]: https://bazel.build/rules/lib/globals/module#archive_override
[`download_archives`]: docs/download/archives/repository.md
[`download/archives`]: docs/download/archives/repository.md
[issues]: ../../issues
[`lib/index`]: docs/lib/index.md
[non-registry override]: https://bazel.build/external/module#non-registry_overrides
[`rctx.download_and_extract`]: https://bazel.build/rules/lib/builtins/repository_ctx#download_and_extract
[repository rule]: https://bazel.build/extending/repo
