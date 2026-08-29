<!-- GENERATED FILE - DO NOT EDIT.
     Source: project/_README.md + project/_CONTRACT.md + shared/_README.md
     Regenerate: GUIDELINES/shared/tools/sync.sh
     Contract version: v1.5.0 -->


# ZFS-on-Linux Kernel Builder (v1.5.0)

Script to build the kernel from source.

## Working on it

```bash
git clone --recurse-submodules https://github.com/metaworx/zfs_on_wsl2.git
```

Work happens on `main`; `upstream/master` preserves the state inherited from the
upstream project and is not a merge target. `--recurse-submodules` populates the
kernel and OpenZFS sources under `3rdparty/` and the shared guidelines under
`GUIDELINES/shared` — an existing checkout catches up with
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
- The shared conventions live in `GUIDELINES/shared` — commit policy, quality
  pass, per-language testing, linting and code style.
- `GUIDELINES/shared/README.md` explains the gate protocol: what an agent asks
  before it changes anything, and what `EXEC` and its relatives authorise.

Both generated documents come from the fragments in `GUIDELINES`.
Editing a generated file is wasted work — change the fragment and re-run
`GUIDELINES/shared/tools/sync.sh`.

## Version History

| Version | Date       | Changed sections | Change type | Agent impact |
|---------|------------|------------------|-------------|--------------|
| v1.5.0  | 2026-08-29 | All              | major       | First version. |

---


# ZFS-on-Linux Kernel Builder — Project Contract (v1.0.0)

## 1. Project Facts

> No absolute paths here. An agent is already inside the checkout, so the
> repository root is `git rev-parse --show-toplevel`; a checkout can live
> anywhere and this file is committed. Machine-specific values belong in
> `GUIDELINES/config.local.ini`, which is not tracked.

| Fact                  | Value                                                                                                                         |
|-----------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Project name          | ZFS-on-Linux Kernel Builder                                                                                                              |
| Language(s)           | declared as `project.languages` in `GUIDELINES/config.ini`, kept honest by `GUIDELINES/shared/tools/detect-languages.sh --check` |
| Source directories    | patches/                                                                                                                      |
| Shipped-code paths    | build.sh, README.md, patches/, 3rdparty/WSL2-Linux-Kernel, 3rdparty/zfs, 3rdparty/python_path_evaluation.sh (rule: COMMIT.md 4.3) |
| Version manifest      | `./build.sh info`                                                                                                             |

## 2. Primary References

- `/AGENTS.md` — runtime behavior contract, gating flow, action-plan workflow.
- `GUIDELINES/shared/lang/<language>/TESTING.md` and `LINTING.md` — language
  baselines for each language in `LANGUAGES`; this file's facts table overrides
  their example commands.
- `GUIDELINES/shared/COMMIT.md` — commit workflow, gating, message policy.
- `GUIDELINES/shared/ENVIRONMENTS.md` — host/agent command conventions.
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
  `pycheck` write `{ISO-date}_{command}.log`, by default **into the repository
  root**, where the root `.gitignore` keeps them out of git. Pass
  `--log-dir <path>` to collect them elsewhere, or `--no-log` where the output
  is not worth keeping.

### 3.6 Branches

- Work happens on `main`. `upstream/master` preserves the state inherited from
  `multiheaded/zfs_on_wsl2`: it is not maintained, and never a merge target.

## 4. Document Governance

- This document follows the shared governance rules in `GUIDELINES/shared/GOVERNANCE.md`.

## 5. Version History

| Version | Date       | Changed sections | Change type | Agent impact |
|---------|------------|------------------|-------------|--------------|
| v1.0.0  | 2026-08-29 | 3, 5             | minor       | §3 is filled in. Six things that were only discoverable by reading `build.sh` or by breaking something are now stated: the build is WSL-only, long, and partly finishable only from Windows; `3rdparty/` changes belong in `patches/` and need `--whitespace=fix`; `clean` destroys them; the version manifest is `SCRIPT_VERSION`, and `COMMIT.md` §4.3 applies in full; indentation is tabs under `set -euo pipefail`, now carried by a root `.editorconfig`; logs default to the repository root. |

---


# Working with the agent (v1.5.0)

This is the human half of the contract. The agent's rules live in
`/AGENTS.md`; this explains what the agent will do to you, what the words it
sends you mean, and what it needs back.

## Contents

1. The short version
2. Gate messages
3. Execution signals
4. Action Plans
5. UAMF — where the agent's writing goes
6. Recovering from a bad turn
7. What the agent must never do without you
8. If this directory looks empty

## 1. The short version

The agent does not change your repository and then tell you. For anything
non-trivial it **stops and asks first**, in a fixed format called a *gate
message*, and waits. You reply with one word — usually `EXEC` — and it proceeds.

Two moments always stop: before a non-trivial code change (you approve the plan)
and before every `git commit` (you approve the message). Everything else is
ordinary work.

## 2. Gate messages

A gate message is the agent's request for permission. It always carries the same
fields, so you can skim it:

- **Checkpoint** — that this is a stop, not a status update
- **Overall Task** — what you asked for, as the agent understood it
- **Last Action** — what it just did, sometimes as bullets where that was
  several things
- **Pending action** — exactly what it wants to do next
- **CHANGELOG bullet** — the line the change will add to the changelog
- **Proposed commit message** — the exact message, wherever a signal would commit
- **Files to be committed** — what would go into that commit
- **Important notes** — anything you need in order to decide and would not
  otherwise see: a bug fixed on the way, something to check before you answer,
  a step that went differently than planned
- **Confirmation needed** — which signal it is waiting for, and what each one does

After sending one the agent must be silent until you answer. If you see it send
a gate and then keep working, that is a violation of its own contract, and worth
saying so.

Read the **Pending action** first. If it does not match what you wanted, say so
in plain words rather than sending a signal — the agent revises and re-gates.

## 3. Execution signals

One word, at the start or anywhere in your reply:

| Signal      | Means |
|-------------|-------|
| `EXEC`      | Do the gated action. Only that. |
| `EXEC+`     | Do it, then carry on with the next planned step. |
| `ROLLBACK`  | Undo the last edit. Required — the agent may not undo unasked. |
| `ERR`       | That went wrong; stop and diagnose before trying again. |
| `PLAN`      | Produce or revise the plan; do not execute yet. |
| `ASK`       | Answer my question; do not treat it as an instruction to act. |

The gate always tells you what `EXEC` will do and where `EXEC+` will go next.
If it doesn't, that is a defect in the gate, not something for you to infer.

`EXEC++` and `EXEC+++` are retired — say it in words instead.

You can also just answer in prose. "Yes, but rename the second one first" is a
perfectly good reply; the signals exist for speed, not ceremony.

## 4. Action Plans

For anything beyond a trivial edit the agent writes an **Action Plan** before
touching code: what it found, what it intends to do step by step, and the commit
message it expects to propose. You see a summary in the gate; the full plan is
written to a file (see §5) so it survives the conversation.

Plans are versioned — `AP Bild v1.2` — and each revision is a new file, never an
overwrite. If you reject a plan, the next one is v1.3 and the reasoning that led
there is still on disk.

## 5. UAMF — where the agent's writing goes

A **User-Accessible Message File** is anything the agent wrote for you to read
rather than for the machine to run: action plans, analyses, migration notes. They
land in `GUIDELINES/messages/` with a timestamp in the name, and they are
**never overwritten** — a revision is always a new file.

This matters when a session ends badly. The conversation may be gone; the
reasoning is still there.

## 6. Recovering from a bad turn

Send `ERR`. The agent stops and replies with a compact recovery block: what it
believes happened, what state things are in, and what it proposes. Send `ERR`
twice in a row and it escalates — it stops proposing and asks you to direct it.

`ROLLBACK` is separate and stronger: it authorises undoing the last edit. The
agent cannot do this on its own initiative, by design, so if something needs
reverting you have to say so.

## 7. What the agent must never do without you

- Commit — every commit is gated, with the full message shown first
- Undo your work — `ROLLBACK` only
- Overwrite a UAMF — revisions are new files
- Delete and recreate a file to make a large edit — it edits in place, so your
  IDE's local history survives
- Push, or anything else that leaves your machine, unless you asked

If any of these happens without your say-so, the agent has broken its contract.
Tell it; the rule it violated is in `/AGENTS.md` and it can name the section.

## 8. If this directory looks empty

Everything under `GUIDELINES/shared` lives in a git submodule, which a plain clone
leaves unpopulated. The document you are reading is committed in the project, so
it survives that — but every link into `GUIDELINES/shared` will be dead until:

```bash
git submodule update --init GUIDELINES/shared
```

Cloning with `--recurse-submodules` does it up front. If the same checkout is
used from both Windows and WSL, this saves a recurring annoyance:

```bash
git -C GUIDELINES/shared config core.fileMode false
```

## 9. Document Governance

- This document follows the shared governance rules in
  `GUIDELINES/shared/GOVERNANCE.md`.

## 10. Version History

| Version | Date       | Changed sections | Change type | Agent impact |
|---------|------------|------------------|-------------|--------------|
| v1.5.0  | 2026-08-27 | 2                            | minor        | `Last Action` may arrive as bullets. A gate at the end of several steps used to report only the last one, leaving the rest to be reconstructed from the diff. |
| v1.4.0  | 2026-08-27 | 2                            | minor        | A gate lists two more fields where they apply: the files a commit would contain, and anything you need in order to decide that you would not otherwise see - a bug fixed on the way, something to check first, a step that went differently than planned. |
| v1.3.0  | 2026-08-27 | 2                            | minor        | A gate lists two more fields: the changelog bullet the change will add, and the commit message wherever a signal would commit. Both were already required of the agent; neither was named among the fields you can expect to see. |
| v1.2.0  | 2026-08-27 | 3                            | minor        | `EXEC++` and `EXEC+++` are retired - say it in words instead. The gate now states what `EXEC` does and where `EXEC+` continues to, so the reader is told rather than left to infer. |
| v1.1.0  | 2026-08-27 | 8, 9, 10                     | minor        | Adds the one thing a fresh clone needs and nothing anywhere said: the shared documents are a submodule, and every link into them is dead until it is initialised. Sections renumbered. |
| v1.0.0  | 2026-08-26 | All              | major       | First version. Explains the gate protocol, execution signals, action plans and UAMF from the user's side; nothing previously described the protocol to the person receiving a gate message. |
