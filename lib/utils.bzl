"""utils.bzl"""

load("@version_utils//spec:spec.bzl", Spec = "spec")
load("@version_utils//version:version.bzl", Version = "version")

def _get_dupes(list_):
    set_ = {}
    dupes = []

    for value in list_:
        if value in set_:
            dupes.append(value)
        set_[value] = True
    return dupes

def _replace_in_place(d, k_replace, replacement, _fail = fail):
    """
    Replace a dict key with one or more k-v.
    """
    if k_replace not in d:
        return _fail("Key to replace not found: {}".format(k_replace))

    if not replacement:
        return _fail("Replacement empty, to delete a key use .pop()")

    res = {}

    for k, v in d.items():
        if k != k_replace:
            res[k] = v
            continue

        for kr, vr in replacement.items():
            res[kr] = vr

    return res

def _matching_patches(
        patches,
        version,
        source,
        spec_syntax = Spec.SYNTAX.SIMPLE,
        version_scheme = Version.SCHEME.SEMVER):
    """Return the patch keys from `patches` that match the given version/source."""

    def _should_apply(pattern_spec):
        if "/" in pattern_spec:
            cspec, csource = pattern_spec.split("/", 1)
        else:
            cspec, csource = pattern_spec, "*"

        spec = Spec.new(cspec, syntax = spec_syntax, version_scheme = version_scheme)

        return spec.match(version) and (csource == "*" or csource == source)

    return [
        patch
        for patch, pattern_spec in patches.items()
        if _should_apply(pattern_spec)
    ]

utils = struct(
    get_dupes = _get_dupes,
    replace_in_place = _replace_in_place,
    matching_patches = _matching_patches,
)
