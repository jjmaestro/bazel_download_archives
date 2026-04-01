# 💡 Contributing

Please feel free to open [issues] and [PRs], contributions are always welcome!

## 🛠️ Development Setup

Ready to contribute? Here’s how to set up your fork and get started with
development.

### ❄️ Nix dev environment

The `nix/` directory has a flake with a dev shell that provides all the tools
needed to work on this repo (Bazel, [`prek`], `nixfmt`, etc). With [direnv]
and [nix-direnv], the dev shell loads automatically when entering the repo.
Otherwise, run:

```sh
nix develop path:./nix
```

### ✅ `pre-commit` hooks

This project uses [`prek`] to run [`pre-commit`] hooks that enforce automatic
checks on commits.

You can see the config and all of the checks in the `.pre-commit-config.yaml`
file.

The dev shell installs the Git hooks automatically. To install them manually,
run `prek install` from the root of the repo. Once installed, `prek` will do
automatic checks on every commit.

Note that there's also a GH Actions that will run the checks when submitting
PRs and when pushing to any branch except the `wip/*` branches.

### 🧱 Building

This project is built with [Bazel]. You can build everything and run all the
tests in the repo with:

```sh
bazel test //...
```

[Bazel]: https://bazel.build
[issues]: ../../issues
[`pre-commit`]: https://pre-commit.com
[`prek`]: https://prek.j178.dev
[direnv]: https://direnv.net
[nix-direnv]: https://github.com/nix-community/nix-direnv
