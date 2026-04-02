"utils.bzl unit tests"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lib:utils.bzl", Utils = "utils")
load("//tests:mock.bzl", Mock = "mock")
load("//tests:suite.bzl", _test_suite = "test_suite")

_PATCH_A = "a.patch"
_PATCH_B = "b.patch"

def _get_dupes__no_dupes_impl(ctx):
    env = unittest.begin(ctx)

    values = [1, 2, 3]
    res = Utils.get_dupes(values)
    asserts.equals(env, [], res)

    return unittest.end(env)

get_dupes__no_dupes_test = unittest.make(_get_dupes__no_dupes_impl)

def _get_dupes__dupes_impl(ctx):
    env = unittest.begin(ctx)

    values = [1, 2, 3, 1]
    res = Utils.get_dupes(values)
    asserts.equals(env, [1], res)

    return unittest.end(env)

get_dupes__dupes_test = unittest.make(_get_dupes__dupes_impl)

def _replace_in_place__missing_key_impl(ctx):
    env = unittest.begin(ctx)

    d = dict(foo = "foo", bar = "bar")
    replacement = dict(foo = "FOO", foobar = "FOOBAR")

    res = Utils.replace_in_place(d, "foobar", replacement, _fail = Mock.fail)
    asserts.true(env, res.startswith("Key to replace not found"))

    return unittest.end(env)

replace_in_place__missing_key_test = unittest.make(_replace_in_place__missing_key_impl)

def _replace_in_place__valid_key_impl(ctx):
    env = unittest.begin(ctx)

    d = dict(foo = "foo", bar = "bar")
    replacement = dict(FOO = "FOO", FOOBAR = "FOOBAR")

    res = Utils.replace_in_place(d, "foo", replacement)
    asserts.equals(env, ["FOO", "FOOBAR", "bar"], res.keys())
    asserts.equals(env, ["FOO", "FOOBAR", "bar"], res.values())

    return unittest.end(env)

replace_in_place__valid_key_test = unittest.make(_replace_in_place__valid_key_impl)

def _matching_patches__wildcard_impl(ctx):
    env = unittest.begin(ctx)

    patches = {_PATCH_A: "*", _PATCH_B: "*/*"}

    params = {
        ("1.0.0", "github.com"): [_PATCH_A, _PATCH_B],
        ("2.5.3", "gitlab.com"): [_PATCH_A, _PATCH_B],
    }

    for (version, source), expected in params.items():
        res = Utils.matching_patches(patches, version, source)
        asserts.equals(env, expected, res)

    return unittest.end(env)

matching_patches__wildcard_test = unittest.make(_matching_patches__wildcard_impl)

def _matching_patches__exact_version_impl(ctx):
    env = unittest.begin(ctx)

    patches = {_PATCH_A: "1.0.0"}

    params = {
        "1.0.0": [_PATCH_A],
        "2.0.0": [],
    }

    for version, expected in params.items():
        res = Utils.matching_patches(patches, version, "github.com")
        asserts.equals(env, expected, res)

    return unittest.end(env)

matching_patches__exact_version_test = unittest.make(_matching_patches__exact_version_impl)

def _matching_patches__version_with_source_impl(ctx):
    env = unittest.begin(ctx)

    patches = {_PATCH_A: "1.0.0/github.com"}

    params = {
        ("1.0.0", "github.com"): [_PATCH_A],
        ("1.0.0", "gitlab.com"): [],
        ("2.0.0", "github.com"): [],
    }

    for (version, source), expected in params.items():
        res = Utils.matching_patches(patches, version, source)
        asserts.equals(env, expected, res)

    return unittest.end(env)

matching_patches__version_with_source_test = unittest.make(_matching_patches__version_with_source_impl)

def _matching_patches__wildcard_source_impl(ctx):
    env = unittest.begin(ctx)

    patches = {_PATCH_A: "1.0.0/*"}

    params = {
        ("1.0.0", "github.com"): [_PATCH_A],
        ("1.0.0", "gitlab.com"): [_PATCH_A],
        ("2.0.0", "github.com"): [],
    }

    for (version, source), expected in params.items():
        res = Utils.matching_patches(patches, version, source)
        asserts.equals(env, expected, res)

    return unittest.end(env)

matching_patches__wildcard_source_test = unittest.make(_matching_patches__wildcard_source_impl)

def _matching_patches__version_range_impl(ctx):
    env = unittest.begin(ctx)

    patches = {_PATCH_A: ">=1.0.0, <2.0.0"}

    params = {
        "0.9.0": [],
        "1.5.0": [_PATCH_A],
        "2.0.0": [],
    }

    for version, expected in params.items():
        res = Utils.matching_patches(patches, version, "github.com")
        asserts.equals(env, expected, res)

    return unittest.end(env)

matching_patches__version_range_test = unittest.make(_matching_patches__version_range_impl)

def _matching_patches__range_with_source_impl(ctx):
    env = unittest.begin(ctx)

    patches = {_PATCH_A: ">=1.0.0, <2.0.0/github.com"}

    params = {
        "github.com": [_PATCH_A],
        "gitlab.com": [],
    }

    for source, expected in params.items():
        res = Utils.matching_patches(patches, "1.5.0", source)
        asserts.equals(env, expected, res)

    return unittest.end(env)

matching_patches__range_with_source_test = unittest.make(_matching_patches__range_with_source_impl)

TEST_SUITE_NAME = "lib/utils"

TEST_SUITE_TESTS = {
    "get_dupes/dupes": get_dupes__dupes_test,
    "get_dupes/no_dupes": get_dupes__no_dupes_test,
    "matching_patches/exact_version": matching_patches__exact_version_test,
    "matching_patches/range_with_source": matching_patches__range_with_source_test,
    "matching_patches/version_range": matching_patches__version_range_test,
    "matching_patches/version_with_source": matching_patches__version_with_source_test,
    "matching_patches/wildcard": matching_patches__wildcard_test,
    "matching_patches/wildcard_source": matching_patches__wildcard_source_test,
    "replace_in_place/missing_key": replace_in_place__missing_key_test,
    "replace_in_place/valid_key": replace_in_place__valid_key_test,
}

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
