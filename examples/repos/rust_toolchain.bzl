"""e2e rust_toolchain tests (an index with a `matrix` of archives)"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@rust_toolchain//:repo.bzl", "DEFAULT_VERSION", "LOCK", "REPO_NAME")
load("@rust_toolchain//1.97.1:source.bzl", "SOURCE", "URL")
load("//:suite.bzl", _examples_suite = "test_suite")

_VERSION = "1.97.1"

_TRIPLES = [
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
]

def _repo_name_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "rust_toolchain", REPO_NAME)
    asserts.equals(env, _VERSION, DEFAULT_VERSION)

    return unittest.end(env)

repo_name_test = unittest.make(_repo_name_impl)

def _source_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "static.rust-lang.org", SOURCE)

    # the URL of the first combination of the matrix, in matrix order
    expected = "https://static.rust-lang.org/dist/cargo-{}-{}.tar.xz".format(
        _VERSION,
        _TRIPLES[0],
    )
    asserts.equals(env, expected, URL)

    return unittest.end(env)

source_test = unittest.make(_source_impl)

def _lock_impl(ctx):
    env = unittest.begin(ctx)

    lock = LOCK[_VERSION]

    asserts.equals(env, "static.rust-lang.org", lock["source"])
    asserts.true(env, lock["integrity"].startswith("sha256-"))

    return unittest.end(env)

lock_test = unittest.make(_lock_impl)

SUITE_NAME = "rust_toolchain"

SUITE = dict(
    lock = lock_test,
    repo_name = repo_name_test,
    source = source_test,
)

examples_suite = lambda: _examples_suite(SUITE_NAME, SUITE)
