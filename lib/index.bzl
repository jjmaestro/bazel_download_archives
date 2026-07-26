"""
# repo JSON index

The repo JSON index is a JSON object that contains all of the metadata required
to download an archive.

In summary, the index is structured (and potentially templated) metadata that's
used to generate (materialize) the URLs from which to download the archives for
each `version`.

## Structure

The index JSON object has the following properties:
- `version` (`int`): the version of the JSON index object.
- `versions` (`dict[version, version_context] | list[version]`): maps `version`
  names to [`version` context]s. If a `list` of versions is provided, it will
  be expanded to a `dict` of `version`s mapped to empty `version` contexts.
- `sources` (`dict[source, source_context]`): maps `source` names to [URL
  `source` context]s.
- `matrix` (`list[axis]`, optional): expands each `version` into a *combination
  of archives* instead of a single one. See [`matrix`].
- `output` (`str`, optional): template that decides the subpath each `matrix`
  combination is extracted into. See [`output`: merging and partitioning].
- `metadata` (`dict[any, any]`): free-form "metadata map", useful to add
  information about the archive that we want to have available in the repo
  (e.g. requirements, version compatibility, external dependencies, etc).

The index JSON object is parsed, validated and converted to an `index`
`struct` with the following properties:
- `version` (`int`): the version of the index struct, matching the version of
  the JSON index object.
- `name` (`str`): the short repo name.
- `repos` (`dict[version, list[repo]]`): maps the archive `version` to the
  `repo` `struct`s. These `struct`s will be used by the `install` repository
  rule to download the versions of the archive.

Each `repo` `struct` has the following properties:
  - `name`: the short repo name
  - `version`: the `version` name
  - `source`: the `source` name
  - `context`: the [`materialized` repo context] which will have, at the very
    least, the `url` from which to download the archive.
  - `contexts`: the list of `struct(output, context)`, one per [`matrix`]
    combination, each with the combination's `materialized` repo `context` and
    its materialized `output` subpath. Without a `matrix` this is a
    single-element list holding `context` and an empty `output`.

## Contexts

### `materialized` repo context

The `materialized` context is built by:

- adding all the properties in the [`default` context], the [`version` context]
  and the [URL `source` context]. Note that *all* of the properties
  in the `version` and URL `source` contexts can be templated using string
  replacements.

- materializing one by one with the context available up to that point
- adding the materialized property to the materialization context so that its
  materialized value is available to the properties after it for string replacement.

Thus, for materialization purposes, **the order of the properties matters**:
**only properties previously defined can be used as string replacements**.

This way, there's a lot of flexibility to define almost any type of `source`
URL format.

### `default` context

The `default` context is a context that's automatically seeded with the values
of `repo_name`, `version` and `source`.

### `version` context

The `version` context object contains properties whose values **change with
each version**. These properties are required to generate (materialize) the
corresponding `source` properties.

The properties can have any name except the following reserved names:
`integrity_algo`, `integrity_hex_digest` and `integrity_sri` (see [Special
context properties]).

These property values can be specific to one source ("per-source") or can apply
to all sources ("global").

The per-source `version` context is a "fully expanded" `dict`-of-`dict`s that
map `version` properties to `source`s:

```json
{
  (...)
  "versions": {
    "1.1": {
      "ext": {
        "example.com": "tar.gz"
      }
    },
    "1.0": {
      "ext": {
        "example.com": "tgz"
      }
    }
  }
}
```

If certain properties apply to all sources, the "global" context provides a
more compact syntax, just a key-value `dict` where the values are not `dict`
i.e. they don't explicitly map to a `source`, e.g.

```json
{
  "version": 1,
  "sources": {
    "example.com": {
      "url": "https://{source}/{version}.{ext}"
    }
  },
  "versions": {
    "1.1": {
      "ext": "tar.gz",
    },
    "1.0": {
      "ext": "tgz",
    }
  }
}
```

where `versions` expands to the "fully expanded" per-source `version` context,
as before.

Finally, a special case of the "global" `version` context can be just a `list`
of versions where each `version` will be expanded to an empty `version`
context, e.g.:

```json
{
  "version": 1,
  "sources": {
    "example.com": {
      "url": "https://{source}/{version}.tgz"
    }
  },
  "versions": ["1.0"]
}
```

where `versions` expands to:

```json
{
  (...)
  "versions": {
    "1.0": {}
  }
}
```

Finally, note that *all* of the property values in the `version` context can be
templated using string replacements. See [`materialized` repo context] for more
details.

### URL `source` context

The URL `source` context object contains properties whose values **change with
each source**. These properties are required to generate (materialize) the only
mandatory `source` property: the `url` to download the archive.

The properties can have any name except the following reserved names:
`integrity_algo`, `integrity_hex_digest` and `integrity_sri` (see [Special
context properties]).

E.g. the simplest index JSON example we had before:

```json
{
  "version": 1,
  "sources": {
    "example.com": {
      "url": "https://{source}/{version}.tgz"
    }
  },
  "versions": ["1.0"]
}
```

will materialize the following `url`: `"https://example.com/1.0.tgz"`.

Note that *all* of the property values in the URL `source` context can be
templated using string replacements. See [`materialized` repo context] for more
details.


## `matrix`

Some archives are not published as *one* file per version but as a *set* of
files. E.g. a toolchain publishes one archive per (target triple, component)
and all of them together make up the toolchain.

The `matrix` describes that set as an ordered list of *axes*:

```json
{
  "version": 1,
  "sources": {
    "static.rust-lang.org": {
      "url": "https://{source}/dist/{component}-{version}-{triple}.tar.xz",
      "strip_prefix": "{component}-{version}-{triple}/{piece}"
    }
  },
  "matrix": [
    {
      "key": "triple",
      "values": ["x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu"]
    },
    {
      "key": "component",
      "values": {
        "cargo": {"piece": "cargo"},
        "rust-std": {"piece": "rust-std-{triple}"},
        "rustfmt": {"piece": "rustfmt-preview"}
      }
    }
  ],
  "output": "{triple}"
}
```

Each axis is an object with two mandatory properties:

- `key` (`str`): the name of the context property that the axis sets. The value
  selected for the axis is available for string replacement as `{<key>}`.
- `values` (`list[str] | dict[str, dict]`): the values of the axis. The `dict`
  form maps each value to *extra context properties* that apply only when that
  value is selected (`piece`, above, which is the sub-directory to strip
  because it differs per component).

The archive is downloaded once *per combination*, i.e. the cartesian product of
all the axes, in matrix order and with the last axis varying fastest. Without a
`matrix` there's exactly one combination with no properties, which is the
pre-`matrix` behavior.

### `matrix` combinations and the repo `context`

The properties of a combination are added to the [`materialized` repo context]
right after the [`default` context] and before the [`version` context] and the
[URL `source` context], so both of those can reference them (e.g. the `url` and
the `strip_prefix` above).

They are materialized in axis order, so an axis can reference the axes before
it: `rust-std`'s `piece` is `"rust-std-{triple}"` because `triple` is the first
axis.

### `matrix` integrity

With a `matrix` there is one archive, and thus one integrity, per combination,
so the [`version` context] nests the integrities by axis value, in matrix
order:

```json
{
  (...)
  "versions": {
    "1.97.1": {
      "x86_64-unknown-linux-gnu": {
        "cargo": "sha256-4b5Xkw2Cfk73/RSNy0jgUv/AqIsGpKKO9EhIOqvsG2E=",
        "rust-std": "sha256-HB5wSugBJrfeNPcuooJffQFzbewgcy5aiibz3Ek5s74="
      }
    }
  }
}
```

As with the non-`matrix` [`version` context], the leaf is either the integrity
itself ("global", the same archive in all sources) or a `dict` that maps each
`source` to its integrity ("per-source").

### `output`: merging and partitioning

`output` is a template, materialized with each combination's context, that
decides the subpath *under the archive's `<VERSION>/<SOURCE>` directory* into
which that combination is extracted.

Combinations that render the *same* `output` are extracted on top of each other
and *merge* into a single tree; combinations that render *different* `output`s
*partition* the tree. In the example above, `"output": "{triple}"` merges all
the components of a triple into one usable toolchain prefix while keeping the
two triples apart.

Every rendered `output` also gets its own `filegroup` in the generated repo, so
consumers can depend on one partition instead of on the whole tree.

When `output` is not set, all combinations extract into the same directory,
i.e. everything merges.

Finally, note that a `source` is only used if *all* of its combinations
download successfully. Otherwise, the next source is tried. This keeps a
partial mirror from leaving behind a half-materialized tree.

TODO: combinations are always downloaded eagerly, all of them, even in the
per-version lazy mode of the `download_archives` module extension. Consider a
hub-and-spoke layout with one download repo per combination so that e.g. only
the triple that's actually built gets downloaded.

### Special context properties

There are two context properties that are "special": `integrity` and `sha256`.

The `sha256` property is expected to have the `SHA256` hex digest of the
archive and the `integrity` property, the [Subresource Integrity (SRI)] of the
archive. However, for convenience, the `integrity` property also accepts hex
digests.

Both are optional and mutually exclusive, only one of them should be set / used
per version and source. If not present, a warning message will be printed
asking to add it to the index. This is important because the integrity of the
archives is crucial to the safety and reproducibility of the builds.

Note that if one of these properties is present, a special "expansion" will
always add *four* special properties to the context: `integrity_algo`,
`integrity_hex_digest`, `integrity_sri` and `integrity` corresponding to the
integrity algorithm, hex digest and SRI, plus `sha256` if the SRI or hex digest
is of a `SHA256` algorithm.

## Examples

### Example 1:

```json
{
  "version": 1,
  "sources": {
    "example.com": {
      "url": "https://{source}/{version}.tgz"
    }
  },
  "versions": ["1.0"]
}
```

In this example, the `materialized` context **before** it's actually
materialized will consist of the `default` context properties (`repo_name`,
`version` and `source`) plus the `url` property from the URL `source` context:
```starlark
{
    "repo_name": <REPO>,
    "version": "1.0",
    "source": "example.com",
    "url": "https://{source}/{version}.tgz",
}
```

Thus, the final `materialized` repo context will be:
```starlark
{
    "repo_name": <REPO>,
    "version": "1.0",
    "source": "example.com",
    "url": "https://example.com/1.0.tgz",
}
```

### Example 2:

```json
{
  "version": 1,
  "urls": {
    "mirror1": {
      "domain": "example.com",
      "tag": "v{version}",
      "filename": "foobar-{tag}",
      "strip_prefix": "{filename}",
      "url": "https://{domain}/{tag}/{filename}-{sha256}.tgz"
    },
    "mirror2": {
      "url": "https://{source}.mirrors.com/{repo_name}/{version}/{sha256}.tgz"
    }
  },
  "versions": {
    "1.1": {
      "sha256": {
        "mirror1": "fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9",
        "mirror2": "c3ab8ff13720e8ad9047dd39466b3c8974e592c2fa383d4a3960714caef0c4f2"
    },
    "1.0": {
      "sha256": "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"
    }
  }
}
```

In this example, the `materialized` repo contexts  **before** actually being
materialized will consist of:
```starlark

# version: 1.0, source: mirror1
{
    "repo_name": <REPO>,
    "version": "1.0",
    "source": "mirror1",

    # version context with special context properties expanded
    "integrity": "sha256-LCa0a2j/xo/5m0U8HTBBNBNCLXBkg7+g+YpeiGJm564=",
    "integrity_algo": "sha256",
    "integrity_sri": "sha256-LCa0a2j/xo/5m0U8HTBBNBNCLXBkg7+g+YpeiGJm564=",
    "integrity_hex_digest": "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae",
    "sha256": "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae",

    # source context
    "domain": "example.com",
    "tag": "v{version}",
    "filename": "foobar-{tag}",
    "strip_prefix": "{filename}",
    "url": "https://{domain}/{tag}/{filename}-{sha256}.tgz",
}

# version: 1.0, source: mirror2
{
    "repo_name": <REPO>,
    "version": "1.0",
    "source": "mirror2",

    # version context with special context properties expanded
    "integrity": "sha256-LCa0a2j/xo/5m0U8HTBBNBNCLXBkg7+g+YpeiGJm564=",
    "integrity_algo": "sha256",
    "integrity_sri": "sha256-LCa0a2j/xo/5m0U8HTBBNBNCLXBkg7+g+YpeiGJm564=",
    "integrity_hex_digest": "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae",
    "sha256": "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae",

    # source context
    "url": "https://{source}.mirrors.com/{repo_name}/{version}/{sha256}.tgz"
}

# version: 1.1, source: mirror1
{
    "repo_name": <REPO>,
    "version": "1.1",
    "source": "mirror1",

    # version context with special context properties expanded
    "integrity": "sha256-/N4rLtula/QIYB+3If6bXDONEO5CnqBPrlURto+/j7k=",
    "integrity_algo": "sha256",
    "integrity_sri": "sha256-/N4rLtula/QIYB+3If6bXDONEO5CnqBPrlURto+/j7k=",
    "integrity_hex_digest": "fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9",
    "sha256": "fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9",

    # source context
    "domain": "example.com",
    "tag": "v{version}",
    "filename": "foobar-{tag}",
    "strip_prefix": "{filename}",
    "url": "https://{domain}/{tag}/{filename}-{sha256}.tgz",
}

# version: 1.1, source: mirror2
{
    "repo_name": <REPO>,
    "version": "1.1",
    "source": "mirror2",

    # version context with special context properties expanded
    "integrity": "sha256-w6uP8Tcg6K2QR905Rms8iXTlksL6OD1KOWBxTK7wxPI=",
    "integrity_algo": "sha256",
    "integrity_sri": "sha256-w6uP8Tcg6K2QR905Rms8iXTlksL6OD1KOWBxTK7wxPI=",
    "integrity_hex_digest": "c3ab8ff13720e8ad9047dd39466b3c8974e592c2fa383d4a3960714caef0c4f2",
    "sha256": "c3ab8ff13720e8ad9047dd39466b3c8974e592c2fa383d4a3960714caef0c4f2",

    # source context
    "url": "https://{source}.mirrors.com/{repo_name}/{version}/{sha256}.tgz"
}
```

And the final `materialized` context for e.g. version `1.1` and `source`
`mirror1` will be:

```starlark
# version: 1.1, source: mirror1
{
    "repo_name": <REPO>,
    "version": "1.1",
    "source": "mirror1",

    # version context with special context properties expanded
    "integrity": "sha256-/N4rLtula/QIYB+3If6bXDONEO5CnqBPrlURto+/j7k=",
    "integrity_algo": "sha256",
    "integrity_sri": "sha256-/N4rLtula/QIYB+3If6bXDONEO5CnqBPrlURto+/j7k=",
    "integrity_hex_digest": "fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9",
    "sha256": "fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9",

    # source context
    "domain": "example.com",
    "tag": "v1.1",
    "filename": "foobar-v1.1",
    "strip_prefix": "foobar-v1.1",
    "url": "https://example.com/v1.1/foobar-v1.1-fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9.tgz",
}
```

[`materialized` repo context]: #materialized-repo-context
[`default` context]: #default-context
[`version` context]: #version-context
[URL `source` context]: #url-source-context
[`matrix`]: #matrix
[`output`: merging and partitioning]: #output-merging-and-partitioning
[Special context properties]: #special-context-properties
[Subresource Integrity (SRI)]: https://w3c.github.io/webappsec-subresource-integrity/
"""

load(":integrity.bzl", Integrity = "integrity")
load(":matrix.bzl", Matrix = "matrix")
load(":schema.bzl", Schema = "schema")
load(":utils.bzl", Utils = "utils")

def _materialize_context_v1(
        repo_name,
        version_name,
        version,
        source_name,
        source,
        matrix = [],
        combo = {}):
    # First, we build the context that we are going to use to materialize all
    # of the templated strings in the URL sources

    context = dict(
        repo_name = repo_name,
        version = version_name,
        source = source_name,
    )

    # A matrix combination's properties come next: they are known before the
    # source properties (they select WHICH archive a source points at), so the
    # source's `url` / `strip_prefix` can reference them. Their own values are
    # materialized below with everything else, in axis order, so a later axis
    # can reference an earlier one.

    context |= combo

    # Then we add all of the "versions" properties that match the source_name
    # and all of the source properties. With a matrix, the top-level keys of
    # the version context that are values of its first axis are the nested
    # integrities, not properties, so they are skipped here (see below).

    axis_values = Matrix.axis_values(matrix)

    context |= {
        property: v
        for property, values in version.items()
        if property not in axis_values
        for k, v in values.items()
        if k == source_name
    }

    # The integrity properties are special, it's processed into an Integrity
    # object so that we can always expand it and add to the context the
    # integrity algo, hex digest and SRI.

    if matrix:
        # With a matrix there's one integrity per combination, nested by axis
        # value, so it isn't a property of the version context and there's no
        # position of its own to expand into: it's appended here, after the
        # version properties and before the source ones, which is where the
        # non-matrix expansion lands too.
        integrity = Matrix.integrity(version, source_name, matrix, combo)
        integrity_property = None
    else:
        integrity_property = "sha256" if "sha256" in version else "integrity"
        integrity = version.get(integrity_property, {}).get(source_name, None)

    if integrity:
        integrity = Integrity.new(integrity)

        expansion = dict(
            integrity = integrity.sri,
            integrity_algo = integrity.algo,
            integrity_sri = integrity.sri,
            integrity_hex_digest = integrity.hex_digest,
        )

        if integrity.is_sha256:
            expansion["sha256"] = integrity.hex_digest

        if integrity_property:
            # NOTE:
            # These are INSERTED all in the position of the integrity property
            # because the order matters for materialization.
            context = Utils.replace_in_place(
                context,
                integrity_property,
                expansion,
            )
        else:
            context |= expansion

    context |= {
        property: v
        for property, v in source.items()
    }

    # Finally, we materialize the context. After materializing each property,
    # it's added to the context so subsequent materializations have it
    # available for string substitution.

    for key, value in list(combo.items()) + list(source.items()):
        if type(value) == "string":
            materialized = value.format(**context)
        elif type(value) in ("list", "tuple"):
            materialized = [v.format(**context) for v in value]
        elif type(value) == "dict":
            materialized = {k: v.format(**context) for k, v in value.items()}
        else:
            fail("$s: Unsupported value type: %s" % (key, type(value)))

        context[key] = materialized

    return context

def _select_keys(
        key,
        keys,
        selected,
        prefix = None,
        keep_first = True,
        reverse = False,
        _fail = fail):
    def _msg(msg, prefix = None):
        return "%s: %s" % (prefix, msg) if prefix else msg

    dupes = Utils.get_dupes(keys)
    if dupes:
        err = "dupes in index '{}': '{}'".format(key, dupes)
        return _fail(_msg(err, prefix))

    dupes = Utils.get_dupes(selected)
    if dupes:
        err = "dupes in selected: '{}'".format(key, dupes)
        return _fail(_msg(err, prefix))

    # When a selection has been given, we respect its ordering. But when
    # no selection is made, we sort the keys but keeping the first value
    # by default respect the first value as default:

    if selected:
        invalid = [s for s in selected if s not in keys]

        if invalid:
            err = "invalid '{}': {} ".format(key, invalid)
            err += "(valid '{}' are: {})".format(key, keys)
            return _fail(_msg(err, prefix))

        selection = selected
    elif keep_first:
        selection = [keys[0]] + sorted(keys[1:], reverse = reverse)
    else:
        selection = sorted(keys, reverse = reverse)

    return selection

def _from_json_v1(repo_name, index, versions, sources, _print = print, _fail = fail):
    versions = versions or []
    sources = sources or []

    error = Schema.validate_v1(repo_name, index, _print = _print, _fail = _fail)

    # testing
    if _fail != fail and error != None:
        return error

    selected_versions, selected_sources = [
        _select_keys(
            key = key,
            keys = index[key].keys(),
            selected = selected,
            prefix = repo_name,
            # always keep the first value as default except for versions which
            # are always reverse sorted
            keep_first = key != "versions",
            # versions are reverse sorted so it defaults to the highest version
            reverse = key == "versions",
        )
        for key, selected in [("versions", versions), ("sources", sources)]
    ]

    # A `matrix` turns one archive per (version, source) into a combination of
    # archives: every combination is downloaded, and `output` decides which
    # axes partition the extracted tree and which merge into it. Without a
    # `matrix` there is exactly one combination with no properties, which is
    # the pre-matrix behaviour.
    matrix = index.get("matrix", [])
    combos = Matrix.combos(matrix, _fail = _fail)
    output = index.get("output", "")

    def _contexts(version_name, source_name):
        contexts = []

        for combo in combos:
            context = _materialize_context_v1(
                repo_name,
                version_name,
                index["versions"][version_name],
                source_name,
                index["sources"][source_name],
                matrix = matrix,
                combo = combo,
            )
            contexts.append(struct(
                # Subpath under `<version>/<source>/`. Combinations that
                # render the same path merge into one tree.
                output = output.format(**context) if output else "",
                context = context,
            ))

        return contexts

    def _repo(version_name, source_name):
        contexts = _contexts(version_name, source_name)

        return struct(
            name = repo_name,
            version = version_name,
            source = source_name,
            # The first combination's context, so that consumers that only
            # need one representative context (URL reporting, strict integrity
            # checks) keep working unchanged.
            context = contexts[0].context,
            contexts = contexts,
        )

    repos = {
        version_name: [
            _repo(version_name, source_name)
            for source_name in selected_sources
        ]
        for version_name in selected_versions
    }

    return struct(
        version = 1,
        name = repo_name,
        repos = repos,
        metadata = index.get("metadata", {}),
    )

def _new(repo_name, index_json, versions = None, sources = None, _print = print, _fail = fail):
    index = json.decode(index_json)

    if index.get("version", None) != 1:
        return _fail("Invalid index version: %s" % index.get("version", None))

    index = _from_json_v1(repo_name, index, versions, sources, _print = _print, _fail = _fail)

    return index

index = struct(
    new = _new,
    __test__ = struct(
        _select_keys = _select_keys,
    ),
)
