"index.bzl unit tests"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lib:index.bzl", Index = "index")
load("//tests:mock.bzl", Mock = "mock")
load("//tests:suite.bzl", _test_suite = "test_suite")

def _select_keys__dupes_in_index_key_impl(ctx):
    env = unittest.begin(ctx)

    keys, selected = [1, 1, 2, 3], [1, 2, 3]

    res = Index.__test__._select_keys("key_name", keys, selected, _fail = Mock.fail)
    asserts.true(env, "dupes in index 'key_name':" in res)

    return unittest.end(env)

select_keys__dupes_in_index_key_test = unittest.make(_select_keys__dupes_in_index_key_impl)

def _select_keys__dupes_in_keys_to_select_impl(ctx):
    env = unittest.begin(ctx)

    keys, selected = [1, 2, 3], [1, 2, 2, 3]

    res = Index.__test__._select_keys("key_name", keys, selected, _fail = Mock.fail)
    asserts.true(env, "dupes in selected:" in res)

    return unittest.end(env)

select_keys__dupes_in_keys_to_select_test = unittest.make(_select_keys__dupes_in_keys_to_select_impl)

def _select_keys__invalid_selection_impl(ctx):
    env = unittest.begin(ctx)

    all_values = ["2.0", "1.0", "4.0", "3.0"]

    invalid_selection = [1]

    res = Index.__test__._select_keys(
        "key_name",
        all_values,
        invalid_selection,
        _fail = Mock.fail,
    )
    asserts.true(env, res.startswith("invalid 'key_name':"))

    return unittest.end(env)

select_keys__invalid_selection_test = unittest.make(_select_keys__invalid_selection_impl)

def _select_keys__empty_selection_impl(ctx):
    env = unittest.begin(ctx)

    all_values = ["2.0", "1.0", "4.0", "3.0"]

    params = (
        # keep_first, reverse, expected
        (False, True, ["4.0", "3.0", "2.0", "1.0"]),
        (False, False, ["1.0", "2.0", "3.0", "4.0"]),
        (True, True, ["2.0", "4.0", "3.0", "1.0"]),
        (True, False, ["2.0", "1.0", "3.0", "4.0"]),
    )

    empty_selection = []

    for keep_first, reverse, expected in params:
        res = Index.__test__._select_keys(
            "key_name",
            all_values,
            empty_selection,
            keep_first = keep_first,
            reverse = reverse,
        )
        asserts.equals(env, expected, res)

    return unittest.end(env)

select_keys__empty_selection_test = unittest.make(_select_keys__empty_selection_impl)

def _select_keys__valid_selection_impl(ctx):
    env = unittest.begin(ctx)

    all_values = ["2.0", "1.0", "4.0", "3.0"]

    params = (
        # keep_first, reverse, expected
        (False, True, ["4.0", "3.0", "2.0", "1.0"]),
        (False, False, ["1.0", "2.0", "3.0", "4.0"]),
        (True, True, ["2.0", "4.0", "3.0", "1.0"]),
        (True, False, ["2.0", "1.0", "3.0", "4.0"]),
    )

    valid_selection = ["2.0", "1.0", "4.0"]

    for keep_first, reverse, _ in params:
        res = Index.__test__._select_keys(
            "key_name",
            all_values,
            valid_selection,
            keep_first = keep_first,
            reverse = reverse,
        )
        expected = valid_selection
        asserts.equals(env, expected, res)

    return unittest.end(env)

select_keys__valid_selection_test = unittest.make(_select_keys__valid_selection_impl)

def _new__invalid_version_impl(ctx):
    env = unittest.begin(ctx)

    index_json = """{ "version": 999 }"""

    err = Index.new("repo_name", index_json, _fail = Mock.fail)
    asserts.true(env, err.startswith("Invalid index version"))

    return unittest.end(env)

new__invalid_version_test = unittest.make(_new__invalid_version_impl)

def _new__v1_empty_versions_impl(ctx):
    env = unittest.begin(ctx)

    index_json = """
    {
      "version": 1,
      "sources": {
        "example.com": {
          "url": "https://{source}/foo.tar.gz"
        }
      },
      "versions": {
      }
    }
    """

    err = Index.new("repo_name", index_json, _print = Mock.print([]), _fail = Mock.fail)
    asserts.equals(env, "repo_name: Invalid index, empty 'versions'", err)

    return unittest.end(env)

new__v1_empty_versions_test = unittest.make(_new__v1_empty_versions_impl)

def _new__v1_valid_simplest_impl(ctx):
    env = unittest.begin(ctx)

    # This is the simplest valid index.json, one version and one URL without
    # any string substitutions:

    expected_url = "https://example.com/1.0/foo.tgz"

    index_json = """
    {
      "version": 1,
      "sources": {
        "src1": {
          "url": %r
        }
      },
      "versions": ["1.0"]
    }
    """ % expected_url

    prints = []

    index = Index.new("repo_name", index_json, _print = Mock.print(prints))
    asserts.equals(env, 1, len(index.repos))
    asserts.equals(env, 1, len(index.repos["1.0"]))

    asserts.equals(env, 1, len(prints))
    asserts.true(env, "1.0: WARNING: missing integrity/sha256" in prints[0])

    asserts.equals(env, expected_url, index.repos["1.0"][0].context["url"])

    return unittest.end(env)

new__v1_valid_simplest_test = unittest.make(_new__v1_valid_simplest_impl)

def _new__v1_valid_simple_impl(ctx):
    env = unittest.begin(ctx)

    # This is another very simple valid index.json with the simplest string
    # substitutions:

    index_json = """
    {
      "version": 1,
      "sources": {
        "example.com": {
          "url": "https://{source}/{version}/foo.tgz"
        }
      },
      "versions": ["1.0"]
    }
    """

    prints = []

    index = Index.new("repo_name", index_json, _print = Mock.print(prints))
    asserts.equals(env, 1, len(index.repos))
    asserts.equals(env, 1, len(index.repos["1.0"]))

    asserts.equals(env, 1, len(prints))
    asserts.true(env, "1.0: WARNING: missing integrity/sha256" in prints[0])

    expected_url = "https://example.com/1.0/foo.tgz"
    asserts.equals(env, expected_url, index.repos["1.0"][0].context["url"])

    return unittest.end(env)

new__v1_valid_simple_test = unittest.make(_new__v1_valid_simple_impl)

def _new__v1_valid_integrity_impl(ctx):
    env = unittest.begin(ctx)

    integrity_sri = "sha256-3q2zP96tsz/erbM/3q2zP96tsz/erbM/3q2zP96tsz8="
    sha256 = "deadb33fdeadb33fdeadb33fdeadb33fdeadb33fdeadb33fdeadb33fdeadb33f"

    for property, value in [("integrity", integrity_sri), ("sha256", sha256)]:
        index_json = """
        {
          "version": 1,
          "sources": {
            "mirror1": {
              "filename": "{%s}",
              "url": "https://{source}.example.com/{version}/{filename}.tar.gz"
            }
          },
          "versions": {
            "1.1": {
              %r: %r
            }
          }
        }
        """ % (property, property, value)

        expected_url = "https://mirror1.example.com/1.1/{}.tar.gz".format(value)

        index = Index.new("repo_name", index_json)
        asserts.equals(env, 1, index.version)
        asserts.equals(env, 1, len(index.repos))

        repo = index.repos["1.1"][0]

        asserts.equals(env, expected_url, repo.context["url"])
        asserts.equals(env, integrity_sri, repo.context["integrity"])
        asserts.equals(env, sha256, repo.context["integrity_hex_digest"])
        asserts.equals(env, sha256, repo.context["sha256"])

    return unittest.end(env)

new__v1_valid_integrity_test = unittest.make(_new__v1_valid_integrity_impl)

def _new__v1_valid_complex_impl(ctx):
    env = unittest.begin(ctx)

    # Finally, here's a complex index.json with both integrity SRI and sha256,
    # different types of version contexts and metadata:

    integrity_sri = "sha256-3q2zP96tsz/erbM/3q2zP96tsz/erbM/3q2zP96tsz8="
    sha256 = "deadb33fdeadb33fdeadb33fdeadb33fdeadb33fdeadb33fdeadb33fdeadb33f"

    index_json = """
    {
      "version": 1,
      "sources": {
        "mirror1": {
          "filename": "foobar-{tag}",
          "strip_prefix": "{filename}",
          "url": "https://{source}.example.com/{version}/{filename}.tar.gz"
        }
      },
      "versions": {
        "1.1": {
          "tag": "v1.1",
          "integrity": %r,
          "foo": {
            "mirror1": %r
          }
        },
        "1.0": {
          "tag": "v1.0"
        }
      },
      "metadata": {
        "versions": {
          "exclude": {
            "1.0": "> 1.5.1"
          }
        }
      }
    }
    """ % (integrity_sri, sha256)

    prints = []

    index = Index.new("repo_name", index_json, _print = Mock.print(prints))
    asserts.equals(env, 1, index.version)
    asserts.equals(env, 2, len(index.repos))

    asserts.true(env, "versions" in index.metadata)

    asserts.equals(env, 1, len(prints))
    asserts.true(env, "1.0: WARNING: missing integrity/sha256" in prints[0])

    repo = index.repos["1.1"][0]

    expected_url = "https://mirror1.example.com/1.1/foobar-v1.1.tar.gz"
    asserts.equals(env, expected_url, repo.context["url"])
    asserts.equals(env, integrity_sri, repo.context["integrity"])
    asserts.equals(env, sha256, repo.context["integrity_hex_digest"])
    asserts.equals(env, sha256, repo.context["sha256"])

    return unittest.end(env)

new__v1_valid_complex_test = unittest.make(_new__v1_valid_complex_impl)

def _new__v1_valid_multiple_sources_impl(ctx):
    env = unittest.begin(ctx)

    integrity_sri = "sha256-3q2zP96tsz/erbM/3q2zP96tsz/erbM/3q2zP96tsz8="
    source_1 = "github.com"
    source_2 = "gitlab.com"

    index_json = """
    {
      "version": 1,
      "sources": {
        %r: {
          "url": "https://{source}/{version}.tar.gz"
        },
        %r: {
          "url": "https://{source}/{version}.tar.gz"
        }
      },
      "versions": {
        "1.0": {
          "integrity": %r
        }
      }
    }
    """ % (source_1, source_2, integrity_sri)

    index = Index.new("repo_name", index_json)

    asserts.equals(env, 2, len(index.repos["1.0"]))

    urls = [repo.context["url"] for repo in index.repos["1.0"]]
    asserts.true(env, "https://%s/1.0.tar.gz" % source_1 in urls)
    asserts.true(env, "https://%s/1.0.tar.gz" % source_2 in urls)

    return unittest.end(env)

new__v1_valid_multiple_sources_test = unittest.make(_new__v1_valid_multiple_sources_impl)

TEST_SUITE_NAME = "lib/index"

TEST_SUITE_TESTS = {
    "new/invalid_version": new__invalid_version_test,
    "new/v1/empty_versions": new__v1_empty_versions_test,
    "new/v1/valid/complex": new__v1_valid_complex_test,
    "new/v1/valid/integrity": new__v1_valid_integrity_test,
    "new/v1/valid/multiple_sources": new__v1_valid_multiple_sources_test,
    "new/v1/valid/simple": new__v1_valid_simple_test,
    "new/v1/valid/simplest": new__v1_valid_simplest_test,
    "_select_keys/dupes_in_index_key": select_keys__dupes_in_index_key_test,
    "_select_keys/dupes_in_keys_to_select": select_keys__dupes_in_keys_to_select_test,
    "_select_keys/empty_selection": select_keys__empty_selection_test,
    "_select_keys/invalid_selection": select_keys__invalid_selection_test,
    "_select_keys/valid_selection": select_keys__valid_selection_test,
}

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
