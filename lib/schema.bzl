"repo JSON index schema"

load(":integrity.bzl", Integrity = "integrity")
load(":matrix.bzl", Matrix = "matrix")

_INDEX_SCHEMA_KEYS = dict(
    v1 = dict(
        index = dict(
            mandatory = ["version", "sources", "versions"],
            optional = ["matrix", "metadata", "output"],
        ),
        sources = dict(
            mandatory = ["url"],
            optional = None,
        ),
    ),
)

_INTEGRITY_PROPERTIES = ("integrity", "sha256")
_RESERVED_PROPERTIES = ("integrity_algo", "integrity_hex_digest", "integrity_sri")

def _get_schema_keys(version, key):
    default = {"all_keys": [], "mandatory": [], "optional": []}

    schema_keys = default | _INDEX_SCHEMA_KEYS[version].get(key, {})

    if schema_keys["mandatory"]:
        schema_keys["all_keys"] += schema_keys["mandatory"]

    if schema_keys["optional"]:
        schema_keys["all_keys"] += schema_keys["optional"]

    return struct(**schema_keys)

# buildifier: disable=return-value
def _validate_section(schema_keys, section_path, index_obj, _fail = fail):
    missing, invalid = [], []

    if type(index_obj) in ("list", "tuple", "dict"):
        missing = [k for k in schema_keys.mandatory if k not in index_obj]

        # A key is consider invalid when it's not in mandatory and not in
        # optional, only if there are explicit optional keys.
        is_invalid = lambda k: (
            k not in schema_keys.mandatory and
            schema_keys.optional != None and
            k not in schema_keys.optional
        )

        invalid = [k for k in index_obj if is_invalid(k)]

    if missing:
        msg = "{}: missing mandatory keys: '{}'"
        return _fail(msg.format(section_path, missing))

    if invalid:
        msg = "{}: invalid keys: '{}'"
        return _fail(msg.format(section_path, invalid))

# buildifier: disable=return-value
def _validate_keys(repo_name, index, index_version, _fail = fail):
    schema_keys = _get_schema_keys(index_version, "index")

    if not schema_keys.all_keys:
        return

    section = "index"
    path = "/".join([repo_name, section])

    error = _validate_section(schema_keys, path, index, _fail = _fail)

    # testing
    if _fail != fail and error != None:
        return error

    for section in schema_keys.all_keys:  # version, sources, versions, metadata
        schema_keys_s = _get_schema_keys(index_version, section)

        if not schema_keys_s.all_keys:
            continue

        for subsection_name, subsection in index[section].items():
            path = "/".join([repo_name, section, subsection_name])

            error = _validate_section(schema_keys_s, path, subsection, _fail = _fail)

            # testing
            if _fail != fail and error != None:
                return error

def _expand_versions(versions, sources):
    # First, if there's a list of versions, expand each version_name into an
    # empty version context
    if type(versions) == "list":
        versions = {version_name: {} for version_name in versions}

    if type(versions) != "dict":
        fail("versions must be a dict")

    # Then, for all version contexts, expand global version properties to all
    # sources. Note that version properties that already have a dict are not
    # expanded.
    return {
        version_name: {
            k: v if type(v) == "dict" else {source: v for source in sources}
            for k, v in version.items()
        }
        for version_name, version in versions.items()
    }

# buildifier: disable=return-value
def _validate_integrities(repo_name, versions, sources, _print = print, _fail = fail):
    for version_name, version in versions.items():
        if all([p in version for p in _INTEGRITY_PROPERTIES]):
            property_sources = [
                source
                for property in _INTEGRITY_PROPERTIES
                for source in version[property]
            ]

            if sorted(property_sources) != sources:
                # Bazel expects either 'sha256' or 'integrity' but not both
                msg = "{}/{}: use either 'sha256' or 'integrity' but not both"
                return _fail(msg.format(repo_name, version_name))

        integrities = {}

        for property in version:
            for source_name, value in version[property].items():
                if property not in _INTEGRITY_PROPERTIES:
                    continue

                if not Integrity.is_valid(value):
                    msg = "{}/{}: invalid '{}': %r" % value
                    return _fail(msg.format(repo_name, version_name, property))

                integrities[source_name] = True

        if len(integrities) != len(sources):
            missing = [src for src in sources if src not in integrities]
            msg = "{}/{}: WARNING: missing integrity/sha256 for URL sources: {}"

            _print(msg.format(repo_name, version_name, missing))

# buildifier: disable=return-value
def _validate_matrix_integrities(
        repo_name,
        versions,
        sources,
        matrix,
        _print = print,
        _fail = fail):
    """Validate the integrities nested by the `matrix` in every version."""
    combos = Matrix.combos(matrix, _fail = _fail)

    # testing
    if _fail != fail and type(combos) != "list":
        return combos

    for version_name, version in versions.items():
        missing = []

        for combo in combos:
            for source_name in sources:
                integrity = Matrix.integrity(
                    version,
                    source_name,
                    matrix,
                    combo,
                )

                path = "/".join([Matrix.path(matrix, combo), source_name])

                if not integrity:
                    missing.append(path)
                    continue

                if not Integrity.is_valid(integrity):
                    msg = "{}/{}/{}: invalid integrity: %r" % integrity
                    return _fail(msg.format(repo_name, version_name, path))

        if missing:
            msg = "{}/{}: WARNING: missing integrity/sha256 for: {}"
            _print(msg.format(repo_name, version_name, missing))

# buildifier: disable=return-value
def _validate_v1(repo_name, index, _print = print, _fail = fail):
    error = _validate_keys(repo_name, index, "v1", _fail = _fail)

    # testing
    if _fail != fail and error != None:
        return error

    if index["version"] != 1:
        msg = "{}: Invalid index version: {}"
        return _fail(msg.format(repo_name, index["version"]))

    # The index must contain at least one version
    if not index["versions"]:
        msg = "{}: Invalid index, empty 'versions'"
        return _fail(msg.format(repo_name))

    # Then, we expand the properties in versions
    index["versions"] = _expand_versions(index["versions"], index["sources"].keys())

    # Then, validate the expanded version properties for each URL source. We
    # still need to do this because the dict values are not expanded and there
    # could be mistakes in the sources (duplicates, missing values or invalid
    # sources)
    index_sources = sorted(index["sources"])

    for source_name in index_sources:
        if "/" in source_name:
            msg = "{}: invalid source name: '{}'"
            return _fail(msg.format(repo_name, source_name))

    # With a `matrix`, the top-level keys of the version context that are
    # values of its first axis are not version properties: they are the roots
    # of the integrities nested by the matrix, validated separately below.
    matrix = index.get("matrix", [])
    axis_values = Matrix.axis_values(matrix)

    for version_name, version in index["versions"].items():
        # TODO: consider only allowing semantic versions
        if "/" in version_name:
            msg = "{}: invalid version name: '{}'"
            return _fail(msg.format(repo_name, version_name))

        for property in version:
            # integrity validation is slightly different
            if property in _INTEGRITY_PROPERTIES or property in axis_values:
                continue

            if property in _RESERVED_PROPERTIES:
                msg = "{}/{}: invalid version property (reserved): {}"
                return _fail(msg.format(repo_name, version_name, property))

            property_sources = sorted(version[property].keys())

            if property_sources != index_sources:
                msg = "{}/{}/{}: invalid version sources"
                return _fail(msg.format(repo_name, version_name, property))

            for source_name in property_sources:
                if "/" in source_name:
                    msg = "{}/{}: invalid source name: '{}'"
                    return _fail(msg.format(repo_name, version_name, source_name))

    # Finally, validate the integrities
    if matrix:
        error = _validate_matrix_integrities(
            repo_name,
            index["versions"],
            index["sources"],
            matrix,
            _print = _print,
            _fail = _fail,
        )
    else:
        error = _validate_integrities(
            repo_name,
            index["versions"],
            index["sources"],
            _print = _print,
            _fail = _fail,
        )

    # testing
    if _fail != fail and error != None:
        return error

schema = struct(
    validate_v1 = _validate_v1,
    __test__ = struct(
        _RESERVED_PROPERTIES = _RESERVED_PROPERTIES,
        _expand_versions = _expand_versions,
    ),
)
