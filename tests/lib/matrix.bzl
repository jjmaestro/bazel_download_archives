"matrix.bzl unit tests"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lib:matrix.bzl", Matrix = "matrix")
load("//tests:mock.bzl", Mock = "mock")
load("//tests:suite.bzl", _test_suite = "test_suite")

_TRIPLE_AXIS = {
    "key": "triple",
    "values": ["x86_64", "aarch64"],
}

_COMPONENT_AXIS = {
    "key": "component",
    "values": {
        "cargo": {"piece": "cargo"},
        "rust-std": {"piece": "rust-std-{triple}"},
    },
}

_MATRIX = [_TRIPLE_AXIS, _COMPONENT_AXIS]

def _axis_values__no_matrix_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, [], Matrix.axis_values([]))

    return unittest.end(env)

axis_values__no_matrix_test = unittest.make(_axis_values__no_matrix_impl)

def _axis_values__first_axis_only_impl(ctx):
    env = unittest.begin(ctx)

    # only the FIRST axis: those are the top-level keys of a matrix version
    # context, the ones that are integrities and not version properties
    asserts.equals(env, ["x86_64", "aarch64"], Matrix.axis_values(_MATRIX))

    return unittest.end(env)

axis_values__first_axis_only_test = unittest.make(
    _axis_values__first_axis_only_impl,
)

def _axis_values__dict_values_impl(ctx):
    env = unittest.begin(ctx)

    values = Matrix.axis_values([_COMPONENT_AXIS])
    asserts.equals(env, ["cargo", "rust-std"], values)

    return unittest.end(env)

axis_values__dict_values_test = unittest.make(_axis_values__dict_values_impl)

def _combos__no_matrix_impl(ctx):
    env = unittest.begin(ctx)

    # no matrix is one combination with no properties, i.e. exactly one
    # archive per (version, source), the pre-matrix behavior
    asserts.equals(env, [{}], Matrix.combos([]))

    return unittest.end(env)

combos__no_matrix_test = unittest.make(_combos__no_matrix_impl)

def _combos__list_values_impl(ctx):
    env = unittest.begin(ctx)

    expected = [
        {"triple": "x86_64"},
        {"triple": "aarch64"},
    ]
    asserts.equals(env, expected, Matrix.combos([_TRIPLE_AXIS]))

    return unittest.end(env)

combos__list_values_test = unittest.make(_combos__list_values_impl)

def _combos__dict_values_impl(ctx):
    env = unittest.begin(ctx)

    # the dict form attaches extra properties to the selected value and, as
    # they are templates, they are NOT materialized here
    expected = [
        {"component": "cargo", "piece": "cargo"},
        {"component": "rust-std", "piece": "rust-std-{triple}"},
    ]
    asserts.equals(env, expected, Matrix.combos([_COMPONENT_AXIS]))

    return unittest.end(env)

combos__dict_values_test = unittest.make(_combos__dict_values_impl)

def _combos__cross_product_order_impl(ctx):
    env = unittest.begin(ctx)

    # the cross product is in matrix order, with the LAST axis varying fastest
    expected = [
        {"component": "cargo", "piece": "cargo", "triple": "x86_64"},
        {"component": "rust-std", "piece": "rust-std-{triple}", "triple": "x86_64"},
        {"component": "cargo", "piece": "cargo", "triple": "aarch64"},
        {"component": "rust-std", "piece": "rust-std-{triple}", "triple": "aarch64"},
    ]
    asserts.equals(env, expected, Matrix.combos(_MATRIX))

    return unittest.end(env)

combos__cross_product_order_test = unittest.make(
    _combos__cross_product_order_impl,
)

def _combos__missing_axis_key_impl(ctx):
    env = unittest.begin(ctx)

    params = (
        ([{"values": ["x86_64"]}], "'key'"),
        ([{"key": "triple"}], "'values'"),
    )

    for matrix, expected in params:
        res = Matrix.combos(matrix, _fail = Mock.fail)
        asserts.true(env, res.startswith("matrix: axis missing mandatory key:"))
        asserts.true(env, res.endswith(expected))

    return unittest.end(env)

combos__missing_axis_key_test = unittest.make(_combos__missing_axis_key_impl)

def _combos__invalid_axis_values_impl(ctx):
    env = unittest.begin(ctx)

    matrix = [{"key": "triple", "values": "x86_64"}]

    res = Matrix.combos(matrix, _fail = Mock.fail)
    asserts.true(env, "'values' must be a list or a dict" in res)

    return unittest.end(env)

combos__invalid_axis_values_test = unittest.make(
    _combos__invalid_axis_values_impl,
)

_VERSION = {
    "x86_64": {
        "cargo": "sha256-AAA",
        "rust-std": {
            "mirror1": "sha256-BBB",
            "mirror2": "sha256-CCC",
        },
    },
}

def _integrity__global_leaf_impl(ctx):
    env = unittest.begin(ctx)

    combo = {"component": "cargo", "triple": "x86_64"}

    res = Matrix.integrity(_VERSION, "mirror1", _MATRIX, combo)
    asserts.equals(env, "sha256-AAA", res)

    return unittest.end(env)

integrity__global_leaf_test = unittest.make(_integrity__global_leaf_impl)

def _integrity__per_source_leaf_impl(ctx):
    env = unittest.begin(ctx)

    combo = {"component": "rust-std", "triple": "x86_64"}

    params = {"mirror1": "sha256-BBB", "mirror2": "sha256-CCC"}

    for source_name, expected in params.items():
        res = Matrix.integrity(_VERSION, source_name, _MATRIX, combo)
        asserts.equals(env, expected, res)

    return unittest.end(env)

integrity__per_source_leaf_test = unittest.make(_integrity__per_source_leaf_impl)

def _integrity__missing_impl(ctx):
    env = unittest.begin(ctx)

    params = (
        # a whole axis value is missing
        {"component": "cargo", "triple": "aarch64"},
        # the leaf of the last axis is missing
        {"component": "rustfmt", "triple": "x86_64"},
    )

    for combo in params:
        res = Matrix.integrity(_VERSION, "mirror1", _MATRIX, combo)
        asserts.equals(env, None, res)

    # the source of a per-source leaf is missing
    combo = {"component": "rust-std", "triple": "x86_64"}
    res = Matrix.integrity(_VERSION, "mirror3", _MATRIX, combo)
    asserts.equals(env, None, res)

    return unittest.end(env)

integrity__missing_test = unittest.make(_integrity__missing_impl)

def _path__axis_values_impl(ctx):
    env = unittest.begin(ctx)

    combo = {"component": "cargo", "piece": "cargo", "triple": "x86_64"}

    # only the axis values, in matrix order
    asserts.equals(env, "x86_64/cargo", Matrix.path(_MATRIX, combo))

    return unittest.end(env)

path__axis_values_test = unittest.make(_path__axis_values_impl)

TEST_SUITE_NAME = "lib/matrix"

TEST_SUITE_TESTS = {
    "axis_values/dict_values": axis_values__dict_values_test,
    "axis_values/first_axis_only": axis_values__first_axis_only_test,
    "axis_values/no_matrix": axis_values__no_matrix_test,
    "combos/cross_product_order": combos__cross_product_order_test,
    "combos/dict_values": combos__dict_values_test,
    "combos/invalid_axis_values": combos__invalid_axis_values_test,
    "combos/list_values": combos__list_values_test,
    "combos/missing_axis_key": combos__missing_axis_key_test,
    "combos/no_matrix": combos__no_matrix_test,
    "integrity/global_leaf": integrity__global_leaf_test,
    "integrity/missing": integrity__missing_test,
    "integrity/per_source_leaf": integrity__per_source_leaf_test,
    "path/axis_values": path__axis_values_test,
}

test_suite = lambda: _test_suite(TEST_SUITE_NAME, TEST_SUITE_TESTS)
