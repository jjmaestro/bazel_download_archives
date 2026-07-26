"download.bzl unit tests"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lib:download.bzl", Download = "download")
load("//tests:mock.bzl", Mock = "mock")
load("//tests:suite.bzl", _test_suite = "test_suite")

def _mock_fail(errors):
    """Returns a _fail function that appends errors to a list."""
    return lambda msg: errors.append(msg)

def _mock_rctx(download_results):
    """Create a mock rctx for testing try_sources.

    Args:
        download_results: list of struct(success, integrity, sha256), one per
            download_and_extract call. Results are consumed in order.

    Returns:
        (rctx, files, patches, logs) where files is a dict of written files,
        patches is a list of applied patch labels, and logs is a list of
        printed messages.
    """
    files = {}
    patches = []
    logs = []
    calls = []
    call_idx = [0]

    def _download_and_extract(**kwargs):
        i = call_idx[0]
        call_idx[0] = i + 1
        calls.append(kwargs)
        return download_results[i]

    def _file(path, content = "", **_kwargs):
        files[path] = content

    def _patch(label, **_kwargs):
        patches.append(label)

    return struct(
        calls = calls,
        download_and_extract = _download_and_extract,
        file = _file,
        patch = _patch,
    ), files, patches, logs

def _make_repos(sources, url_tpl = "https://{source}/{version}.tar.gz", version = "1.0"):
    """Create a list of repo structs for testing."""
    return [
        struct(
            version = version,
            source = source,
            context = {
                "integrity": "sha256-AAAA",
                "url": url_tpl.format(source = source, version = version),
            },
        )
        for source in sources
    ]

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

def _try_sources__first_success_wins_impl(ctx):
    env = unittest.begin(ctx)

    repos = _make_repos(["github.com", "gitlab.com"])
    rctx, files, _, _ = _mock_rctx([
        struct(success = True, integrity = "sha256-AAAA", sha256 = "deadbeef"),
    ])

    dl = Download.try_sources(rctx, "test", "1.0", repos)
    asserts.equals(env, "github.com", dl.source)
    asserts.true(env, "1.0/source.bzl" in files)

    return unittest.end(env)

try_sources__first_success_wins_test = unittest.make(
    _try_sources__first_success_wins_impl,
)

def _try_sources__failover_to_second_impl(ctx):
    env = unittest.begin(ctx)

    repos = _make_repos(["github.com", "gitlab.com"])
    rctx, _, _, _ = _mock_rctx([
        struct(success = False, integrity = "", sha256 = ""),
        struct(success = True, integrity = "sha256-AAAA", sha256 = "deadbeef"),
    ])

    dl = Download.try_sources(rctx, "test", "1.0", repos)
    asserts.equals(env, "gitlab.com", dl.source)
    asserts.true(env, "https://gitlab.com/1.0.tar.gz" in dl.url)

    return unittest.end(env)

try_sources__failover_to_second_test = unittest.make(
    _try_sources__failover_to_second_impl,
)

def _try_sources__all_fail_returns_none_impl(ctx):
    env = unittest.begin(ctx)

    repos = _make_repos(["github.com", "gitlab.com"])
    rctx, _, _, _ = _mock_rctx([
        struct(success = False, integrity = "", sha256 = ""),
        struct(success = False, integrity = "", sha256 = ""),
    ])

    dl = Download.try_sources(rctx, "test", "1.0", repos)
    asserts.equals(env, None, dl)

    return unittest.end(env)

try_sources__all_fail_returns_none_test = unittest.make(
    _try_sources__all_fail_returns_none_impl,
)

def _try_sources__missing_integrity_warns_impl(ctx):
    env = unittest.begin(ctx)

    repos = [struct(
        version = "1.0",
        source = "github.com",
        context = {"url": "https://github.com/1.0.tar.gz"},
    )]
    rctx, _, _, logs = _mock_rctx([
        struct(success = True, integrity = "sha256-AAAA", sha256 = "deadbeef"),
    ])

    Download.try_sources(rctx, "test", "1.0", repos, _print = Mock.print(logs))
    asserts.equals(env, 1, len(logs))
    asserts.true(env, "integrity missing" in logs[0])

    return unittest.end(env)

try_sources__missing_integrity_warns_test = unittest.make(
    _try_sources__missing_integrity_warns_impl,
)

def _try_sources__output_path_impl(ctx):
    env = unittest.begin(ctx)

    repos = _make_repos(["github.com"])
    rctx, _, _, _ = _mock_rctx([
        struct(success = True, integrity = "sha256-AAAA", sha256 = "deadbeef"),
    ])

    dl = Download.try_sources(rctx, "test", "1.0", repos)
    asserts.equals(env, "1.0/github.com", dl.output)

    return unittest.end(env)

try_sources__output_path_test = unittest.make(
    _try_sources__output_path_impl,
)

def _try_sources__strict_integrity_checked_impl(ctx):
    env = unittest.begin(ctx)

    repos = [
        struct(version = "1.0", source = "s1", context = {
            "integrity": "sha256-AAA",
            "url": "https://s1/1.0.tar.gz",
        }),
        struct(version = "1.0", source = "s2", context = {
            "integrity": "sha256-BBB",
            "url": "https://s2/1.0.tar.gz",
        }),
    ]
    _noop = struct(success = False, integrity = "", sha256 = "")
    rctx, _, _, _ = _mock_rctx([_noop, _noop])

    errors = []
    Download.try_sources(
        rctx,
        "test",
        "1.0",
        repos,
        strict_integrity = True,
        _fail = _mock_fail(errors),
    )
    asserts.equals(env, 1, len(errors))
    asserts.true(env, "different integrities" in errors[0])

    return unittest.end(env)

try_sources__strict_integrity_checked_test = unittest.make(
    _try_sources__strict_integrity_checked_impl,
)

def _make_matrix_repos(sources, outputs, version = "1.0"):
    """Create repo structs with one `contexts` entry per matrix combination."""
    return [
        struct(
            version = version,
            source = source,
            context = {
                "integrity": "sha256-AAAA",
                "url": "https://%s/%s.tar.gz" % (source, version),
            },
            contexts = [
                struct(
                    output = output,
                    context = {
                        "integrity": "sha256-AAAA",
                        "url": "https://%s/%s/%s.tar.gz" % (
                            source,
                            output,
                            version,
                        ),
                    },
                )
                for output in outputs
            ],
        )
        for source in sources
    ]

_OK = struct(success = True, integrity = "sha256-AAAA", sha256 = "deadbeef")
_KO = struct(success = False, integrity = "", sha256 = "")

def _check_strict_integrity__matrix_per_combo_impl(ctx):
    env = unittest.begin(ctx)

    def _repo(integrities):
        return struct(contexts = [
            struct(output = output, context = {"integrity": integrity})
            for output, integrity in integrities.items()
        ])

    # the sources agree on the first combination but not on the second: with
    # a matrix, every combination is its own archive and its own comparison
    repos = [
        _repo({"amd64": "sha256-AAA", "arm64": "sha256-BBB"}),
        _repo({"amd64": "sha256-AAA", "arm64": "sha256-CCC"}),
    ]

    errors = []
    Download.check_strict_integrity(repos, "1.0", _fail = _mock_fail(errors))
    asserts.equals(env, 1, len(errors))
    asserts.true(env, "different integrities" in errors[0])

    return unittest.end(env)

check_strict_integrity__matrix_per_combo_test = unittest.make(
    _check_strict_integrity__matrix_per_combo_impl,
)

def _try_sources__matrix_downloads_every_combo_impl(ctx):
    env = unittest.begin(ctx)

    repos = _make_matrix_repos(["github.com"], ["amd64", "arm64"])
    rctx, files, _, _ = _mock_rctx([_OK, _OK])

    dl = Download.try_sources(rctx, "test", "1.0", repos)

    # one download per combination, each extracted under its own `output`
    asserts.equals(env, 2, len(rctx.calls))
    asserts.equals(env, [
        "1.0/github.com/amd64",
        "1.0/github.com/arm64",
    ], [call["output"] for call in rctx.calls])

    # ... and one target per `output`, so consumers can pick a partition
    asserts.equals(env, ["amd64", "arm64"], dl.outputs)

    asserts.equals(env, "github.com", dl.source)
    asserts.true(env, "1.0/source.bzl" in files)

    return unittest.end(env)

try_sources__matrix_downloads_every_combo_test = unittest.make(
    _try_sources__matrix_downloads_every_combo_impl,
)

def _try_sources__matrix_merged_outputs_impl(ctx):
    env = unittest.begin(ctx)

    # combinations that render the same `output` merge into one tree, so they
    # are one target, not one per combination
    repos = _make_matrix_repos(["github.com"], ["amd64", "amd64"])
    rctx, _, _, _ = _mock_rctx([_OK, _OK])

    dl = Download.try_sources(rctx, "test", "1.0", repos)

    asserts.equals(env, 2, len(rctx.calls))
    asserts.equals(env, ["amd64"], dl.outputs)

    return unittest.end(env)

try_sources__matrix_merged_outputs_test = unittest.make(
    _try_sources__matrix_merged_outputs_impl,
)

def _try_sources__matrix_partial_source_fails_over_impl(ctx):
    env = unittest.begin(ctx)

    outputs = ["amd64", "arm64", "riscv64"]
    repos = _make_matrix_repos(["github.com", "gitlab.com"], outputs)

    # the first source is missing one of the three combinations, so it's
    # skipped entirely rather than leaving a half-materialized tree
    rctx, _, _, _ = _mock_rctx([_OK, _KO, _OK, _OK, _OK])

    dl = Download.try_sources(rctx, "test", "1.0", repos)

    asserts.equals(env, "gitlab.com", dl.source)
    asserts.equals(env, outputs, dl.outputs)

    # and the first source stops at the combination that failed
    asserts.equals(env, [
        "1.0/github.com/amd64",
        "1.0/github.com/arm64",
        "1.0/gitlab.com/amd64",
        "1.0/gitlab.com/arm64",
        "1.0/gitlab.com/riscv64",
    ], [call["output"] for call in rctx.calls])

    return unittest.end(env)

try_sources__matrix_partial_source_fails_over_test = unittest.make(
    _try_sources__matrix_partial_source_fails_over_impl,
)

def _try_sources__no_matrix_has_no_outputs_impl(ctx):
    env = unittest.begin(ctx)

    repos = _make_repos(["github.com"])
    rctx, _, _, _ = _mock_rctx([_OK])

    dl = Download.try_sources(rctx, "test", "1.0", repos)

    # without a matrix there's one archive extracted at the root of the
    # version/source directory and, thus, no per-`output` targets
    asserts.equals(env, [], dl.outputs)
    asserts.equals(env, ["1.0/github.com"], [c["output"] for c in rctx.calls])

    return unittest.end(env)

try_sources__no_matrix_has_no_outputs_test = unittest.make(
    _try_sources__no_matrix_has_no_outputs_impl,
)

TEST_SUITE_NAME = "lib/download"

TEST_SUITE_TESTS = {
    "apply_patch/rewrites_paths": apply_patch__rewrites_paths_test,
    "check_strict_integrity/all_same": check_strict_integrity__all_same_test,
    "check_strict_integrity/matrix_per_combo": check_strict_integrity__matrix_per_combo_test,
    "check_strict_integrity/mismatch": check_strict_integrity__mismatch_test,
    "check_strict_integrity/mix": check_strict_integrity__mix_test,
    "check_strict_integrity/none": check_strict_integrity__none_test,
    "make_download_args/allowed_keys_passthrough": make_download_args__allowed_keys_passthrough_test,
    "make_download_args/basic": make_download_args__basic_test,
    "make_download_args/ignored_keys": make_download_args__ignored_keys_test,
    "make_download_args/sha256_integrity_conflict": make_download_args__sha256_integrity_conflict_test,
    "make_download_args/unknown_keys_skipped": make_download_args__unknown_keys_skipped_test,
    "try_sources/all_fail_returns_none": try_sources__all_fail_returns_none_test,
    "try_sources/failover_to_second": try_sources__failover_to_second_test,
    "try_sources/first_success_wins": try_sources__first_success_wins_test,
    "try_sources/matrix/downloads_every_combo": try_sources__matrix_downloads_every_combo_test,
    "try_sources/matrix/merged_outputs": try_sources__matrix_merged_outputs_test,
    "try_sources/matrix/no_matrix_has_no_outputs": try_sources__no_matrix_has_no_outputs_test,
    "try_sources/matrix/partial_source_fails_over": try_sources__matrix_partial_source_fails_over_test,
    "try_sources/missing_integrity_warns": try_sources__missing_integrity_warns_test,
    "try_sources/output_path": try_sources__output_path_test,
    "try_sources/strict_integrity_checked": try_sources__strict_integrity_checked_test,
}

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
