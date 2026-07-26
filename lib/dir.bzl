"""
# `dir_tree`

Copies an extracted archive into a tree artifact, keyed on what the archive is
rather than only on the directory holding it.

## Why

An extracted archive is a directory, and a build that wants a source tree wants
it as one: autotools, cmake and cargo all take a directory rather than a file
list, and a directory is the only form that carries the symlinks, the empty
directories, and any subtree a nested `BUILD` file would cut a glob short at.

What taking a directory costs is that Bazel does not hash its contents, and says
so of every such input:

```text
WARNING: input '' of <TARGET> is a directory;
dependency checking of directories is unsound
```

An action reading one is not re-run when the tree changes, and this repository
rule re-downloading and re-patching does not help, because nothing downstream
can observe that it did. The failure mode is a patch that is silently ignored:
adding one to a version already built changes the extracted tree and nothing
else, so the build goes on compiling the tree it staged first.

So `dir_tree` copies the directory and declares beside it, as `key`, the files
that decide what the directory holds: the repo `lock.json`, whose `url` and
`integrity` are the archive it was unpacked from, and the patches then applied
to it, taken by content rather than by label since editing a patch is the
ordinary way to work on one. A change to either re-keys the copy.

None of which makes a directory dependency sound, and this does not pretend to:
an edit reaching the extracted tree by some other route still goes unnoticed. It
closes the routes this repository rule itself takes.

The copy is the `copy_directory` toolchain binary with `--hardlink`, the tree
being copied again only when the repo has re-extracted it wholesale, so there is
nothing to gain by copying bytes.
"""

_TOOLCHAIN = "@aspect_bazel_lib//lib:copy_directory_toolchain_type"

def _dir_tree_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name)

    args = ctx.actions.args()
    args.add_all([ctx.file.src, out], expand_directories = False)
    args.add("--hardlink")

    ctx.actions.run(
        # `src` is what the action reads; `key` is what it is keyed on. Bazel
        # does not require an input to be read, and `key` cannot be expressed
        # any other way: an attribute the action never passes to a tool or
        # reads as a file does not reach its key at all.
        inputs = [ctx.file.src] + ctx.files.key,
        outputs = [out],
        executable = ctx.toolchains[_TOOLCHAIN].copy_directory_info.bin,
        arguments = [args],
        # As `copy_directory` sets it, for bazel-lib #1146.
        env = {"GODEBUG": "winsymlink=0"},
        mnemonic = "DirTree",
        progress_message = "Copying archive directory %{label}",
        toolchain = _TOOLCHAIN,
    )

    # `files` is what `$(rlocationpath[s] ...)` names and what an action reads.
    # Runfiles are separate, and a consumer stages `default_runfiles`: left
    # implicit, Bazel collects those from this rule's attributes and so stages
    # `src`, the extracted directory, at the very path this tree sits under,
    # where it shadows it. Declaring them replaces that collection rather than
    # adding to it, which is what keeps the two apart.
    return [DefaultInfo(
        files = depset([out]),
        runfiles = ctx.runfiles(files = [out]),
    )]

dir_tree = rule(
    doc = """
    Copy an extracted archive directory into a tree artifact, keyed on the
    files that decide what the directory holds.
    """,
    implementation = _dir_tree_impl,
    provides = [DefaultInfo],
    attrs = {
        "key": attr.label_list(
            doc = "Files whose contents decide what `src` holds: the repo " +
                  "`lock.json` and the patches applied to the archive.",
            allow_files = True,
        ),
        "src": attr.label(
            doc = "The extracted archive directory, i.e. `:dir_path`.",
            mandatory = True,
            allow_single_file = True,
        ),
    },
    toolchains = [_TOOLCHAIN],
)
