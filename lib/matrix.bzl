"""index `matrix`: expansion into the combinations of archives of a version"""

def _axis_values(matrix):
    """Values of the first axis, i.e. the top-level keys of a `matrix` version.

    Args:
        matrix: The index `matrix`, a list of `{"key": ..., "values": ...}`.

    Returns:
        The list of values of the first axis, empty when there's no `matrix`.
    """
    if not matrix:
        return []

    values = matrix[0].get("values", [])

    return values.keys() if type(values) == "dict" else list(values)

def _combos(matrix, _fail = fail):
    """Expand a `matrix` into its ordered list of combinations.

    Each combination is a `dict` of context properties: one entry per axis
    mapping the axis `key` to the selected value, plus any extra properties
    that a `dict`-shaped axis attaches to that value. The extra properties are
    NOT materialized here: they are templates, materialized per source
    alongside the source properties so that they can reference the whole
    context.

    Args:
        matrix: The index `matrix`, a list of `{"key": ..., "values": ...}`.
        _fail: Fail function for errors.

    Returns:
        A list of `dict`s, one per combination, in matrix order (the last axis
        varies fastest). Without a `matrix`, a single empty combination.
    """
    combos = [{}]

    for axis in matrix:
        for key in ("key", "values"):
            if key not in axis:
                return _fail("matrix: axis missing mandatory key: '%s'" % key)

        key, values = axis["key"], axis["values"]

        if type(values) == "dict":
            # `{value: {property: template}}`: the value carries extra
            # properties of its own (e.g. a per-component `strip_prefix` tail)
            axis_entries = [
                dict(properties, **{key: value})
                for value, properties in values.items()
            ]
        elif type(values) in ("list", "tuple"):
            axis_entries = [{key: value} for value in values]
        else:
            msg = "matrix: axis '{}': 'values' must be a list or a dict, got: {}"
            return _fail(msg.format(key, type(values)))

        combos = [
            dict(combo, **entry)
            for combo in combos
            for entry in axis_entries
        ]

    return combos

def _integrity(version, source_name, matrix, combo):
    """Look up a combination's integrity by walking the `version` context.

    With a `matrix` there is one archive, and thus one integrity, per
    combination, so the integrities are nested by axis value, in matrix order,
    e.g. `versions[<version>][<triple>][<component>]`. The leaf is either the
    integrity itself ("global") or a `{source: integrity}` `dict`
    ("per-source").

    Args:
        version: The `version` context.
        source_name: The `source` name, to pick from a per-source leaf.
        matrix: The index `matrix`, a list of `{"key": ..., "values": ...}`.
        combo: One of the combinations of the `matrix`.

    Returns:
        The integrity of the combination's archive, `None` if it's missing.
    """
    node = version

    for axis in matrix:
        if type(node) != "dict":
            return None

        node = node.get(combo[axis["key"]], None)

        if node == None:
            return None

    if type(node) == "dict":
        node = node.get(source_name, None)

    return node

def _path(matrix, combo):
    """The combination's axis values, joined, to name it in error messages."""
    return "/".join([combo[axis["key"]] for axis in matrix])

matrix = struct(
    axis_values = _axis_values,
    combos = _combos,
    integrity = _integrity,
    path = _path,
)
