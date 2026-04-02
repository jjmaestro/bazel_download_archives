"download.bzl unit tests"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lib:download.bzl", Download = "download")
load("//tests:mock.bzl", Mock = "mock")
load("//tests:suite.bzl", _test_suite = "test_suite")

def _mock_fail(errors):
    """Returns a _fail function that appends errors to a list."""
    return lambda msg: errors.append(msg)

def _check_strict_integrity__all_same_impl(ctx):
    env = unittest.begin(ctx)

    repos = [
        struct(context = {"integrity": "sha256-AAA"}),
        struct(context = {"integrity": "sha256-AAA"}),
    ]

    errors = []
    Download.check_strict_integrity(repos, "1.0", _fail = _mock_fail(errors))
    asserts.equals(env, 0, len(errors))

    return unittest.end(env)

check_strict_integrity__all_same_test = unittest.make(
    _check_strict_integrity__all_same_impl,
)

def _check_strict_integrity__mismatch_impl(ctx):
    env = unittest.begin(ctx)

    repos = [
        struct(context = {"integrity": "sha256-AAA"}),
        struct(context = {"integrity": "sha256-BBB"}),
    ]

    errors = []
    Download.check_strict_integrity(repos, "1.0", _fail = _mock_fail(errors))
    asserts.equals(env, 1, len(errors))
    asserts.true(env, "different integrities" in errors[0])

    return unittest.end(env)

check_strict_integrity__mismatch_test = unittest.make(
    _check_strict_integrity__mismatch_impl,
)

def _check_strict_integrity__mix_impl(ctx):
    env = unittest.begin(ctx)

    repos = [
        struct(context = {"integrity": "sha256-AAA"}),
        struct(context = {}),
    ]

    # one has integrity, one doesn't: should not fail (only 1 unique integrity)
    errors = []
    Download.check_strict_integrity(repos, "1.0", _fail = _mock_fail(errors))
    asserts.equals(env, 0, len(errors))

    return unittest.end(env)

check_strict_integrity__mix_test = unittest.make(
    _check_strict_integrity__mix_impl,
)

def _check_strict_integrity__none_impl(ctx):
    env = unittest.begin(ctx)

    repos = [
        struct(context = {}),
        struct(context = {}),
    ]

    # no integrities at all: should not fail
    errors = []
    Download.check_strict_integrity(repos, "1.0", _fail = _mock_fail(errors))
    asserts.equals(env, 0, len(errors))

    return unittest.end(env)

check_strict_integrity__none_test = unittest.make(
    _check_strict_integrity__none_impl,
)

def _make_download_args__basic_impl(ctx):
    env = unittest.begin(ctx)

    context = {"url": "https://example.com/foo.tar.gz"}

    args = Download.make_download_args("1.0/src", context)
    asserts.equals(env, {"url": "https://example.com/foo.tar.gz"}, args)

    return unittest.end(env)

make_download_args__basic_test = unittest.make(_make_download_args__basic_impl)

def _make_download_args__sha256_integrity_conflict_impl(ctx):
    env = unittest.begin(ctx)

    context = {
        "integrity": "sha256-AAAA",
        "sha256": "deadbeef",
        "url": "https://example.com/foo.tar.gz",
    }

    args = Download.make_download_args("1.0/src", context)

    # integrity wins, sha256 is dropped
    asserts.true(env, "integrity" in args)
    asserts.false(env, "sha256" in args)
    asserts.equals(env, "sha256-AAAA", args["integrity"])

    return unittest.end(env)

make_download_args__sha256_integrity_conflict_test = unittest.make(
    _make_download_args__sha256_integrity_conflict_impl,
)

def _make_download_args__ignored_keys_impl(ctx):
    env = unittest.begin(ctx)

    logs = []

    context = {
        "allow_fail": True,
        "output": "/some/path",
        "url": "https://example.com/foo.tar.gz",
    }

    args = Download.make_download_args("1.0/src", context, _print = Mock.print(logs))

    # output and allow_fail should be ignored (not in result)
    asserts.false(env, "output" in args)
    asserts.false(env, "allow_fail" in args)
    asserts.equals(env, {"url": "https://example.com/foo.tar.gz"}, args)

    # warnings should be printed
    asserts.equals(env, 2, len(logs))

    return unittest.end(env)

make_download_args__ignored_keys_test = unittest.make(
    _make_download_args__ignored_keys_impl,
)

def _make_download_args__unknown_keys_skipped_impl(ctx):
    env = unittest.begin(ctx)

    context = {
        "repo_name": "my_repo",
        "source": "github.com",
        "url": "https://example.com/foo.tar.gz",
        "version": "1.0",
    }

    args = Download.make_download_args("1.0/src", context)

    # only url should pass through; repo_name, version, source are not
    # in the allowed list
    asserts.equals(env, {"url": "https://example.com/foo.tar.gz"}, args)

    return unittest.end(env)

make_download_args__unknown_keys_skipped_test = unittest.make(
    _make_download_args__unknown_keys_skipped_impl,
)

def _make_download_args__allowed_keys_passthrough_impl(ctx):
    env = unittest.begin(ctx)

    # NOTE: strip_prefix is excluded because _make_download_args checks
    # native.bazel_version for the Bazel 7 compat rename, and
    # native.bazel_version is not available in test (BUILD) context.
    context = {
        "canonical_id": "foo-1.0",
        "integrity": "sha256-AAAA",
        "type": "tar.gz",
        "url": "https://example.com/foo.tar.gz",
    }

    args = Download.make_download_args("1.0/src", context)
    asserts.equals(env, "https://example.com/foo.tar.gz", args["url"])
    asserts.equals(env, "sha256-AAAA", args["integrity"])
    asserts.equals(env, "tar.gz", args["type"])
    asserts.equals(env, "foo-1.0", args["canonical_id"])

    return unittest.end(env)

make_download_args__allowed_keys_passthrough_test = unittest.make(
    _make_download_args__allowed_keys_passthrough_impl,
)

# --- apply_patch ---

_SAMPLE_PATCH = """\
diff --git a/foo.c b/foo.c
--- a/foo.c
+++ b/foo.c
@@ -1 +1 @@
-old
+new
"""

def _apply_patch__rewrites_paths_impl(ctx):
    env = unittest.begin(ctx)

    files = {}
    patches = []

    def _read(_label):
        return _SAMPLE_PATCH

    def _file(path, content = "", **_kwargs):
        files[path] = content

    def _patch(path, **_kwargs):
        patches.append(path)

    rctx = struct(read = _read, file = _file, patch = _patch)
    patch_label = struct(name = "fix.patch")

    Download.apply_patch(rctx, "1.0", "github.com", patch_label)

    # The rewritten patch should have version/source/ prepended to paths
    rewritten = files["patches/1.0/github.com/fix.patch"]
    asserts.true(env, "--- a/1.0/github.com/foo.c" in rewritten)
    asserts.true(env, "+++ b/1.0/github.com/foo.c" in rewritten)

    # The original unprefixed paths should NOT be present
    asserts.false(env, "--- a/foo.c" in rewritten)

    # Patch was applied
    asserts.equals(env, 1, len(patches))

    return unittest.end(env)

apply_patch__rewrites_paths_test = unittest.make(
    _apply_patch__rewrites_paths_impl,
)

TEST_SUITE_NAME = "lib/download"

TEST_SUITE_TESTS = {
    "apply_patch/rewrites_paths": apply_patch__rewrites_paths_test,
    "check_strict_integrity/all_same": check_strict_integrity__all_same_test,
    "check_strict_integrity/mismatch": check_strict_integrity__mismatch_test,
    "check_strict_integrity/mix": check_strict_integrity__mix_test,
    "check_strict_integrity/none": check_strict_integrity__none_test,
    "make_download_args/allowed_keys_passthrough": make_download_args__allowed_keys_passthrough_test,
    "make_download_args/basic": make_download_args__basic_test,
    "make_download_args/ignored_keys": make_download_args__ignored_keys_test,
    "make_download_args/sha256_integrity_conflict": make_download_args__sha256_integrity_conflict_test,
    "make_download_args/unknown_keys_skipped": make_download_args__unknown_keys_skipped_test,
}

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
