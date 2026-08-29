> **Fragment** — inlined by `tools/sync.sh`; not a standalone document.

# {{project_name}} — Project Contract (v1.1.0)

## 1. Project Facts

> No absolute paths here. An agent is already inside the checkout, so the
> repository root is `git rev-parse --show-toplevel`; a checkout can live
> anywhere and this file is committed. Machine-specific values belong in
> `{{guidelines_root}}/config.local.ini`, which is not tracked.

| Fact                  | Value                                                                                                                         |
|-----------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Project name          | {{project_name}}                                                                                                              |
| Language(s)           | declared as `project.languages` in `{{guidelines_root}}/config.ini`, kept honest by `{{shared_root}}/tools/detect-languages.sh --check` |
| Source directories    | patches/                                                                                                                      |
| Shipped-code paths    | build.sh, README.md, patches/, 3rdparty/WSL2-Linux-Kernel, 3rdparty/zfs, 3rdparty/python_path_evaluation.sh (rule: COMMIT.md 4.3) |
| Version manifest      | `./build.sh info`                                                                                                             |

## 2. Primary References

- `/AGENTS.md` — runtime behavior contract, gating flow, action-plan workflow.
- `{{shared_root}}/lang/<language>/TESTING.md` and `LINTING.md` — language
  baselines for each language in `LANGUAGES`; this file's facts table overrides
  their example commands.
- `{{shared_root}}/COMMIT.md` — commit workflow, gating, message policy.
- `{{shared_root}}/ENVIRONMENTS.md` — host/agent command conventions.
- `CONTRIBUTING.md` — repository-specific contributor conventions.

## 3. Project-Specific Conventions

### 3.1 Where this runs

- Everything happens **inside WSL2**. `build.sh` calls `sudo` for `apt`/`dnf`,
  `dpkg` and `make modules_install`, and `install` writes the kernel to a
  Windows path (`/mnt/c/wsl2_zfs` by default) and edits the Windows-side
  `.wslconfig` it locates with `wslvar USERPROFILE`. A new kernel only takes
  effect after `wsl --shutdown` from an elevated PowerShell — an agent cannot
  finish that step from inside the distro.
- A full `./build.sh` build takes tens of minutes and needs the whole machine
  (`make -j$(nproc --all)`). Never start one to "check something"; read
  `./build.sh info` instead, which prints the checked-out kernel and OpenZFS
  versions without building.

### 3.2 The `3rdparty/` submodules are not ours to commit

- `3rdparty/WSL2-Linux-Kernel` and `3rdparty/zfs` are submodules pinned to
  upstream tags. Changes to their sources are **never committed inside the
  submodule**; they live as patch files in `patches/` and are applied to the
  work tree.
- `git apply` refuses these patches over whitespace warnings and rolls back
  silently. Apply them as:

  ```bash
  git -C 3rdparty/zfs apply --whitespace=fix ../../patches/0001-*.patch
  ```

- `build.sh` does **not** apply `patches/` — that is a manual step, and one that
  is easy to forget after an update.
- `./build.sh clean` runs `git reset --hard && git clean -fdx` in each
  `3rdparty/` directory. It destroys any applied patch and any local edit there
  without asking. Confirm with the user before running it.

### 3.3 Versioning

- The version manifest of §1 is `./build.sh info`, which reports what
  `SCRIPT_VERSION` at the top of `build.sh` says. That constant is where the
  version is edited: a commit that changes behaviour bumps it, and the summary
  carries the new number — `[FIX] v1.5.0 Kernel config options where NOT
  applied`.
- `COMMIT.md` §4.3 applies in full: a commit touching any shipped-code path of
  §1 writes or amends its `## [Unreleased]` bullet in the same commit.
  `CHANGELOG.md` starts at 1.1.0 and was reconstructed from the git history;
  everything from here on is written with the change it describes.
- `[FIX]`/`[SECURITY]` bump the patch digit, anything else the minor digit.

### 3.4 Shell conventions

- Indentation is **tabs**. `build.sh` was normalised to tabs deliberately, so a
  space-indented hunk shows up as noise in every later diff. A handful of
  space-indented lines survive the normalisation; match the surrounding file,
  and do not reindent unrelated lines to fix them.
- `.editorconfig` at the repository root carries this, plus LF endings and the
  two exceptions that matter: markdown keeps its trailing whitespace (two spaces
  are a hard line break) and `*.patch` is left byte-exact, since trimming it
  breaks `git apply`.
- `build.sh` runs under `set -euo pipefail`. A command whose non-zero exit is
  expected must say so (`|| true`), or it aborts the whole run.

### 3.5 Logs

- `build`, `kernel-config`, `debs`, `env`, `install`, `update`, `wslu` and
  `pycheck` write `{ISO-date}_{command}.log` into `logs/`, which ignores its own
  `*.log` and is created on demand. `--log-dir <path>` collects them elsewhere,
  `--log <file>` names one outright, and `--no-log` writes none. There is no
  root `.gitignore` any more: nothing outside `logs/` is expected to be
  untracked-but-ignored, so anything that shows up in `git status` is something
  to deal with rather than to filter out.

### 3.6 Branches

- Work happens on `main`. `upstream/master` preserves the state inherited from
  `multiheaded/zfs_on_wsl2`: it is not maintained, and never a merge target.

## 4. Document Governance

- This document follows the shared governance rules in `{{shared_root}}/GOVERNANCE.md`.

## 5. Version History

| Version | Date       | Changed sections | Change type | Agent impact |
|---------|------------|------------------|-------------|--------------|
| v1.1.0  | 2026-08-29 | 3.5              | minor       | Logs no longer land in the repository root: `build.sh` v1.6.0 defaults `LOG_DIR` to `logs/`, and the root `.gitignore` is retired with it. An agent reading `git status` can now treat every untracked path as real, rather than assuming `*.log` noise is filtered. |
| v1.0.0  | 2026-08-29 | 3, 5             | minor       | §3 is filled in. Six things that were only discoverable by reading `build.sh` or by breaking something are now stated: the build is WSL-only, long, and partly finishable only from Windows; `3rdparty/` changes belong in `patches/` and need `--whitespace=fix`; `clean` destroys them; the version manifest is `SCRIPT_VERSION`, and `COMMIT.md` §4.3 applies in full; indentation is tabs under `set -euo pipefail`, now carried by a root `.editorconfig`; logs default to the repository root. |
