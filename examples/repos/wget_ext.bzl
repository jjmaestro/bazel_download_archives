"""e2e wget_ext tests (module extension)"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@wget_ext//:repo.bzl", "DEFAULT_VERSION", "REPO_NAME", "VERSIONS")
load("@wget_ext//1.24.5:source.bzl", "SOURCE", "URL")
load("//:suite.bzl", _examples_suite = "test_suite")

def _repo_name_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "wget_ext", REPO_NAME)

    return unittest.end(env)

repo_name_test = unittest.make(_repo_name_impl)

def _default_version_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "1.24.5", DEFAULT_VERSION)

    return unittest.end(env)

default_version_test = unittest.make(_default_version_impl)

def _versions_has_entry_impl(ctx):
    env = unittest.begin(ctx)

    asserts.true(env, "1.24.5" in VERSIONS)

    return unittest.end(env)

versions_has_entry_test = unittest.make(_versions_has_entry_impl)

def _source_from_download_repo_impl(ctx):
    env = unittest.begin(ctx)

    # SOURCE comes from the per-version download repo via source.bzl re-export
    known_sources = ["github.com", "gitlab.com"]
    asserts.true(env, SOURCE in known_sources, "SOURCE %r not in %r" % (SOURCE, known_sources))
    asserts.true(env, "1.24.5" in URL or "v1.24.5" in URL, "URL %r doesn't contain version" % URL)

    return unittest.end(env)

source_from_download_repo_test = unittest.make(_source_from_download_repo_impl)

SUITE_NAME = "wget_ext"

SUITE = dict(
    repo_name = repo_name_test,
    default_version = default_version_test,
    versions_has_entry = versions_has_entry_test,
    source_from_download_repo = source_from_download_repo_test,
)

examples_suite = lambda: _examples_suite(SUITE_NAME, SUITE)
