<!-- GENERATED FILE - DO NOT EDIT.
     Source: shared/_AGENTS.md + project/_CONTRACT.md
     Regenerate: GUIDELINES/shared/tools/sync.sh
     Contract version: v3.8.1 -->


# AI Agent Guidelines (v3.8.1)

Core behavioral rules for AI agents working on this codebase.  
All agents MUST comply.
This document is intentionally concise; refer to linked documents for extended guidance.

## Contents

1. Critical Behavioral Rules (STRICT)
2. Instruction Precedence (STRICT)
3. Task Interpretation & Keywords
4. User‑Accessible Message Files (UAMF)
5. Action Plan (AP)
6. Commit Policy (STRICT)
7. Additional References
8. Document Governance

## 1. Critical Behavioral Rules (STRICT)

### 1.1 Gate Message Mechanism

- A **gate message** is an `<answer>` (or idempotent) message that concludes the current turn and requests explicit user
  confirmation.
- After sending a gate message, the agent MUST **stop** — no further actions, shell commands, or status updates are
  permitted until the user responds with a new `<issue_update>`.
- The gate message MUST follow the **Universal Gate Template**:
    - `Checkpoint`
    - `Overall Task`
    - `Last Action` - optionally extended with bullets of what was implemented,
      changed or fixed
    - `Pending action`
    - `CHANGELOG bullet` - the bullet the change ships with, verbatim; `N/A` where it ships none
    - `Proposed commit message` - wherever a signal at this gate would commit; otherwise `N/A`
    - `Files to be committed` - conditional: the paths, wherever a signal at this gate would commit
    - `Important notes` - conditional: what the user needs in order to decide and would not otherwise
      see; omitted when there is nothing
    - `Confirmation needed: EXEC/EXEC+/ROLLBACK`
    - Additional information according to specialized gate message (e.g. AP or commit)
- The gate MUST state, in the user's terms, **what `EXEC` will do** and **what
  `EXEC+` will continue to** afterwards. A signal the user cannot predict the
  effect of is not consent.
- Where the runtime offers a structured question tool (see
  `GUIDELINES/shared/tools/RUNTIME_TOOLS.md`), the gate SHOULD present the
  available signals through it as selectable options, with the recommended one
  first. The text template still applies: the tool carries the choice, not the
  reasoning.
- A gate message is the **only** valid way to request user confirmation. Echoing "waiting for input" via shell commands
  is a **violation** of this rule.
- A visual workflow diagram is available in `GUIDELINES/shared/GATE_WORKFLOW.md`.

### 1.2 Action Plan (AP) Requirement

- Every non‑trivial `[CODE]` task requires an Action Plan.
- Full AP format and versioning rules are defined in [§5](#5-action-plan-ap).
- Each AP iteration MUST be persisted as a [UAMF](#4-useraccessible-message-files-uamf) **before** any project writes.
- Unless the execution is directly authorized by an `EXEC`‑family keyword in the same user message, the AP MUST be
  presented as a **gate message** (see [§1.1](#11-gate-message-mechanism)).

### 1.3 Commit Confirmation Gate

- Before `git commit`, the agent MUST present a gate message containing the complete proposed commit message.
- Commit‑related execution signals (`EXEC`, `EXEC+`) and commit tools are detailed in [
  `GUIDELINES/shared/COMMIT.md`](GUIDELINES/shared/COMMIT.md).
- The gate message must follow the Universal Gate Template.

### 1.4 `undo_edit` Authorization (`ROLLBACK`)

- A rollback action (calling `undo_edit`) requires explicit user authorization.
- Authorization may be given via:
    - The keyword `ROLLBACK` in the user message, or
    - An `EXEC`‑family signal that clearly references the rollback.
- If authorization is absent, the agent MUST present a gate message requesting `ROLLBACK` or `EXEC` confirmation.

### 1.5 Safe File Edits

- **Do not delete and recreate files** when making large changes. Instead, write the new content to a temporary file and
  atomically replace the original (`mv` on Linux/macOS, `Move-Item` on Windows). This preserves local IDE history.
- Temporary files SHOULD be placed in `GUIDELINES/temp/`, which is scratch:
  it may be deleted wholesale at any time. User-visible artifacts belong in
  `GUIDELINES/messages/`, which is durable and never purged - the two are
  siblings so that reclaiming disk space cannot destroy the written record.
- Always prefer history‑preserving edit tools (e.g., `apply_patch`, in‑place edits) over raw shell writes.

## 2. Instruction Precedence (STRICT)

1. Runtime/system rules (conflicts noted explicitly).
2. Direct user instruction (current session).
3. This document (the shared agent contract).
4. Local conventions

**IMPORTANT:**

- Writing *new* [UAMF](#4-useraccessible-message-files-uamf) messages does NOT constitute a source-file edit.
- Same for writing to .aiassistant/temp to create temporary files during evaluation (e.g. a temporary test file)
- BOTH are explicitly ALLOWED also in PLANNING-ONLY mode.

### 2.1 Rule Map & Canonical Owners (STRICT)

| Need                                                                                      | Canonical location              |
|-------------------------------------------------------------------------------------------|---------------------------------|
| Gate lifecycle, pause behavior, mixed-signal gate handling, `ERR` recovery, gate template | `GUIDELINES/shared/GATE_WORKFLOW.md` |
| Commit gate and `EXEC+` variants in commit context, commit message format, commit tooling | `GUIDELINES/shared/COMMIT.md`        |
| Test depth and commands                                                                   | `GUIDELINES/shared/lang/<language>/TESTING.md`       |
| Quality pass over changed source files, of any language                                   | `GUIDELINES/shared/QUALITY.md` |
| Lint/style commands and policy                                                            | `GUIDELINES/shared/lang/<language>/LINTING.md`       |
| Document governance rules and canonical history ownership                                 | `GUIDELINES/shared/GOVERNANCE.md`     |
| Agent-host command/tool-name conventions (Windows-hosted vs WSL-based, per-agent specifics) | `GUIDELINES/shared/ENVIRONMENTS.md`  |
| AP requirements (`MUST`)                                                                  | this document §1.2 and §5      |

If overlap exists, follow the canonical owner document for that rule family.

## 3. Task Interpretation & Keywords

- **`ASK`** – Standalone: Send `<answer>` in [chat] mode. Combined with other keywords: include answer in new gate
  message (if task-relevant) or with the result of the gated action.
- **`PLAN`** – Produce/update AP, present it, send gate message.
- **`EXEC`** – Execute gated action(s). For `EXEC+`-family see [`GUIDELINES/shared/COMMIT.md`](GUIDELINES/shared/COMMIT.md).
- **`ROLLBACK`** – Authorize an `undo_edit` action (see [§1.4](#14-undo_edit-authorization-rollback)).
- **`ERR`** – Apply recovery protocol (detailed in `GUIDELINES/shared/GATE_WORKFLOW.md`).
- **`UAMF`** – Instructs agent to write a [UAMF](#4-useraccessible-message-files-uamf) message file.

Latest `<issue_update>` overrides earlier `<issue_description>`.

### 3.1 First Response Contract

- Non-trivial `[CODE]` task without inline `EXEC`: produce AP, persist AP UAMF, send gate.
- If the same user message includes clear execution authorization (`EXEC` family): execute only the authorized scope.
- Before `git commit`: always send a commit gate with full proposed commit message.

## 4. User‑Accessible Message Files (UAMF)

A UAMF is a stored artefact, written for the user to read, that follows strict
rules:

- Its name begins with a timestamp, `YYYY-MM-DD_HH-NN_`, then describes its
  subject.
- It is **never overwritten**. A revision is a new file carrying a new version
  in its name; the previous one stays where it is.

Where it is stored depends on how long it needs to live:

| Directory | Tracked | For |
|-----------|---------|-----|
| `GUIDELINES/messages/` | no  | the default: analyses, findings and records written for the user |
| `GUIDELINES/wip/`      | yes | the Action Plan driving the change in progress, and any analysis that change depends on |
| `GUIDELINES/temp/`     | no  | scratch that is not a UAMF at all |

Citation rules follow from that, and they are absolute:

- **`messages/` is never cited.** Not from a document, not from a commit
  message, not from another UAMF. It is untracked: it exists in one working copy
  and nobody else can follow the reference.
- **`wip/` may be cited from another `wip/` document** — an Action Plan naming
  the analysis it rests on — **and from a commit message**, which is immutable
  and dated, so it names something that existed then and that git can still
  produce.
- **Nothing that outlives the change may cite either.** If a conclusion is worth
  citing from a contract, a shared document or a README, it belongs *in* that
  document.

## 5. Action Plan (AP)

### 5.1 Format & Versioning

- Title: `AP {topic} v{Major}.{Minor}: {2-5 word description}`
    - `{topic}` is a 1-3 word PascalCase slug describing the AP's subject (e.g. `Bild`, `Mock`, `DecisionEngine`, `ECSFixers`).
    - It is **not** a workflow signal — `PLAN`, `EXEC`, `ASK`, `ROLLBACK`, and `ERR` are user-facing keywords from §3, not AP title components.
- Examples: `AP Bild v1.0: Extract decision functions`, `AP FilterFix v1.0: Fix type validation`.
- Increment version on every update.
- Retain cumulative `Change History` within the AP document (append‑only).

### 5.2 Required Sections

- **Discussion** (if any)
- **Analysis**
- **Implementation Plan** (step‑by‑step; include a **Verification** checkpoint after each logical block)
- **Proposed commit message** (for changes since the session start or last commit)
- **Change History** (all previous version entries)

### 5.3 Persistence (UAMF)

- Write each AP iteration as a [UAMF](#4-useraccessible-message-files-uamf) in
  `GUIDELINES/wip/` before modifying any project files, and commit it
  with the work it drives. A plan that exists only in one working copy cannot be
  reviewed, and a commit that cites it would be citing nothing.
- An AP is **retired** — deleted — by the commit that completes it. It remains
  reachable in history: `git log --all --full-history -- <path>` finds it.
- An AP may span many commits, of any tag, interrupted by other work. Retirement
  follows completion, not the shape of the commit series.
- The agent MUST NOT retire an AP on its own judgement. When it believes one is
  complete it **asks**, in the commit gate, and the user decides.

## 6. Commit Policy (STRICT)

- Summary MUST start with one of: `[TASK]`, `[FIX]`, `[SECURITY]`, `[CLEANUP]`, `[WIP]`, `[UPDATE]`, `[RELEASE]`.
- Empty second line.
- Detailed body explaining what and why.
- One functional change per commit.
- Commits touching shipped app code MUST add a `CHANGELOG.md` `[Unreleased]` entry; releases are cut via a
  dedicated `[RELEASE]` commit. See `GUIDELINES/shared/COMMIT.md` §4.3–4.4.
- **Prefer using commit tools** documented in `GUIDELINES/shared/COMMIT.md`.

## 7. Additional References

Paths below use two placeholders, substituted when this document is inlined
into a project's `AGENTS.md`: `GUIDELINES` is the project's agent directory and
`GUIDELINES/shared` is the shared guidelines submodule. Their values come from
`GUIDELINES/config.ini`.

- **This document, below** – project facts: paths, versions, exact test and lint commands. They are inlined here from the project's `project/_CONTRACT.md`.
- `GUIDELINES/shared/COMMIT.md` – commit workflow, gating, message and changelog policy.
- `GUIDELINES/shared/GATE_WORKFLOW.md` – gate lifecycle and `ERR` recovery protocol.
- `GUIDELINES/shared/ENVIRONMENTS.md` – agent-host command and tool-name conventions.
- `GUIDELINES/shared/GOVERNANCE.md` – document versioning and history rules.
- `GUIDELINES/shared/QUALITY.md` – the quality pass to run over every changed source file.
- `GUIDELINES/shared/lang/<language>/TESTING.md` and `LINTING.md` – language baselines.
- `GUIDELINES/shared/tools/README.md`, `GUIDELINES/shared/tools/RUNTIME_TOOLS.md` – helper scripts and runtime tools.
- `GUIDELINES/project/CI.md` – CI conventions, if the project has any.

## 8. Document Governance

- Version updated on every change (SemVer).
- Full document history is maintained in `GUIDELINES/shared/GOVERNANCE.md`.
- Drift-check: when a specialized rule document changes ownership semantics, update §2.1 in the same change.
- In `8.1 Current version`, keep only the latest row; move older entries to `GUIDELINES/shared/GOVERNANCE.md`, section 2.1.

### 8.1 Current version

| Version | Date       | Changed Sections | Change Type | Agent Impact                                    |
|---------|------------|------------------|-------------|-------------------------------------------------|
| v3.8.1 | 2026-08-28 | 7, 8.1 | patch | Cites the generated document rather than the `project/_CONTRACT.md` fragment. A fragment is inlined into a generated document and is not somewhere a reader can be sent: the facts are already in `/AGENTS.md`, which an agent has loaded, and the fragment may not have been generated from yet. |

---


# ZFS-on-Linux Kernel Builder — Project Contract (v1.2.0)

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

### 3.3 Versioning and releases

- The version manifest of §1 is `./build.sh info`, which reports what
  `SCRIPT_VERSION` at the top of `build.sh` says. That constant is where the
  version is edited.
- `COMMIT.md` §4.3 applies in full: a commit touching any shipped-code path of
  §1 writes or amends its `## [Unreleased]` bullet in the same commit.
  `CHANGELOG.md` starts at 1.1.0 and was reconstructed from the git history;
  everything from here on is written with the change it describes.
- `[FIX]`/`[SECURITY]` bump the patch digit, anything else the minor digit.

**One bump per release, not per commit.** The first commit after a release
bumps the digit; each commit from there to the release marks its own state with
a `-wipN` suffix — `1.6.1-wip1`, `-wip2`, `-wip3` — and the `[RELEASE]` drops
it. Without the suffix, every commit after the first reports a version string
naming a release it is not; with a bump per commit instead, the history fills
with versions no build ever ran and no release ever contained.

**A `[RELEASE]` that would promote bullets spanning more than one manifest
version is a question for the user, not a judgement call.** `## [Unreleased]`
can accumulate work done under several `SCRIPT_VERSION` values when an earlier
one was bumped but never released. Cutting the later version then buries the
earlier one's changes inside its section, and the earlier version — which may
already be public — never appears in the changelog at all. Ask which shape is
wanted before promoting; undoing it afterwards costs a history rewrite.

**The `[RELEASE]` commit's diff is the manifest and `CHANGELOG.md`** — and
`CHANGELOG.md` alone where the manifest already carries the number, because the
change that earned the version bumped it on the way past. `COMMIT.md` §4.4
describes two files; say in the body when it is one, and why.

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

- This document follows the shared governance rules in `GUIDELINES/shared/GOVERNANCE.md`.

## 5. Version History

| Version | Date       | Changed sections | Change type | Agent impact |
|---------|------------|------------------|-------------|--------------|
| v1.2.0  | 2026-08-29 | 3.3              | minor       | Three release rules that were learned the expensive way. One version bump per release, with `-wipN` marking each commit's unreleased state, instead of a bump per commit. A `[RELEASE]` promoting bullets that span more than one manifest version must ask rather than decide — v1.6.0's changes were folded into v1.6.1's section and it took a history rewrite to separate them. And a release commit touches one file, not §4.4's two, where the manifest was already bumped by the change itself. |
| v1.1.0  | 2026-08-29 | 3.5              | minor       | Logs no longer land in the repository root: `build.sh` v1.6.0 defaults `LOG_DIR` to `logs/`, and the root `.gitignore` is retired with it. An agent reading `git status` can now treat every untracked path as real, rather than assuming `*.log` noise is filtered. |
| v1.0.0  | 2026-08-29 | 3, 5             | minor       | §3 is filled in. Six things that were only discoverable by reading `build.sh` or by breaking something are now stated: the build is WSL-only, long, and partly finishable only from Windows; `3rdparty/` changes belong in `patches/` and need `--whitespace=fix`; `clean` destroys them; the version manifest is `SCRIPT_VERSION`, and `COMMIT.md` §4.3 applies in full; indentation is tabs under `set -euo pipefail`, now carried by a root `.editorconfig`; logs default to the repository root. |
