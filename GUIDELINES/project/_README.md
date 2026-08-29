> **Fragment** — inlined by `tools/sync.sh`; not a standalone document.

# {{project_name}} (v1.5.0)

Script to build the kernel from source.

## Working on it

```bash
git clone --recurse-submodules https://github.com/metaworx/zfs_on_wsl2.git
```

Work happens on `main`; `upstream/master` preserves the state inherited from the
upstream project and is not a merge target. `--recurse-submodules` populates the
kernel and OpenZFS sources under `3rdparty/` and the shared guidelines under
`{{shared_root}}` — an existing checkout catches up with
`git submodule update --init --recursive`.

```bash
cd zfs_on_wsl2
./build.sh info      # what is checked out, and at which versions
./build.sh env       # install the build dependencies, once
./build.sh           # build
```

## The rules that apply here

The conventions below are not AI configuration: they are how this project is
written, and an agent is simply another party required to follow them.

- The contract that follows is generated into `/AGENTS.md` as well, so people
  and agents are held to the same text.
- The shared conventions live in `{{shared_root}}` — commit policy, quality
  pass, per-language testing, linting and code style.
- `{{shared_root}}/README.md` explains the gate protocol: what an agent asks
  before it changes anything, and what `EXEC` and its relatives authorise.

Both generated documents come from the fragments in `{{guidelines_root}}`.
Editing a generated file is wasted work — change the fragment and re-run
`{{shared_root}}/tools/sync.sh`.

## Version History

| Version | Date       | Changed sections | Change type | Agent impact |
|---------|------------|------------------|-------------|--------------|
| v1.5.0  | 2026-08-29 | All              | major       | First version. |
