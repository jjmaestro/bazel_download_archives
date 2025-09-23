#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Argument provided by reusable workflow caller, see
# https://github.com/bazel-contrib/.github/blob/d197a6427c5435ac22e56e33340dff912bc9334e/.github/workflows/release_ruleset.yaml#L72
TAG="${1}"
GH_REPO_NAME="${2-bazel_download_archives}"

VERSION="${TAG#v}"

# The prefix is chosen to match what GitHub generates for source archives
# This guarantees that users can easily switch from a released artifact to a source archive
# with minimal differences in their code (e.g. strip_prefix remains the same)
PREFIX="${GH_REPO_NAME}-${VERSION}"
ARCHIVE="${GH_REPO_NAME}-${TAG}.tar.gz"

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix="${PREFIX}/" "${TAG}" | gzip > "${ARCHIVE}"

cat << EOF
## 📦 Install

To start using this module:

* Make sure you have set up [Bzlmod] according to the user guide
* Add the module as a dependency in your \`MODULE.bazel\` with:

\`\`\`starlark
bazel_dep(name = "download_archives", version = "${VERSION}")
\`\`\`

[Bzlmod]: https://bazel.build/external/migration
EOF
