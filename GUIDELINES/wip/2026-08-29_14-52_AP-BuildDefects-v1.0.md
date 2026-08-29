# AP BuildDefects v1.0: Fix four build.sh defects

Written 2026-08-29 14:52 CEST, on `main`, from the instruction in
`messages/` dated 14:25.

## Discussion

### What I verified, rather than took on trust

The instruction says to confirm its line numbers. All five hold on `main`
at `87fc7d6`:

| Claim | Line | Verified |
|-------|------|----------|
| `<<<EOL` | 553 | yes |
| `echo "kernel=$WSL_LINE\r"` | 573 | yes |
| `cd 3rdparty/WSL2-Linux-Kernel && make kernelversion` | 823 | yes |
| `-r 3rdparty/zfs/META` | 828 | yes |
| `[ -d "$ZFS_AUTO_SNAPSHOT_DIR"]` | 1075 | yes |

Behaviour, reproduced rather than reasoned about:

- `bash -n build.sh` passes; `shellcheck build.sh` aborts at line 554 with
  SC1035/SC1073/SC1020/SC1072 and never analyses the file. Confirmed.
- Defect 3 in isolation: `! [ -d "/tmp"] || echo PULL` prints
  ``[: missing `]'``, does not run the right-hand side, and exits **0**.
  Confirmed exactly as described.
- Defect 4: `cd /tmp && /home/mdr/projects/zfs_on_wsl2/build.sh info` dies with
  `cd: 3rdparty/WSL2-Linux-Kernel: No such file or directory` at line 823.
  Confirmed.

### Three corrections to the instruction

1. **SC2153 is at line 536, not 632.** Line 632 is blank. The assignment is
   `local "KERNEL_TARGET_WIN=$(wslpath -w "$KERNEL_TARGET")"`. The substance of
   the note is right; only the line is wrong.
2. **The post-fix lint count is 42, not 43** — 34 × SC2086, not 35. Measured on
   a scratch copy with defects 1 and 3 fixed: 34 × SC2086, 1 each of SC2181,
   SC2155, SC2153, SC2046, SC2034, SC2028, SC2004, SC1091. SC2153 is present,
   so the false-positive warning stands.
3. **Its closing observation is stale.** `## [Unreleased]` is not empty and the
   v1.6.0 logging work does have an entry — that gap was closed by a history
   rewrite after the instruction was written. The commits it names as `a6ea27c`
   and `e564564` are now `9d6ba09` and `87fc7d6`.

### The line-ending decision, which the instruction leaves open

Defect 2 requires picking one convention for `.wslconfig` and saying which.
**Decision: CRLF, consistently, in all three branches.**

The evidence is the machine's own file. `/mnt/c/Users/mdr/.wslconfig` is
uniformly CRLF and currently boots the custom kernel, so CRLF is the
demonstrated-working convention here. Writing LF-only lines into it — which is
what the `else` branch would do if `\r` were simply dropped — produces a mixed
file, which is strictly worse than either convention.

This makes me **deviate from the instruction's suggested replacement** for
defect 1. A `<<-EOL` heredoc cannot emit CRLF without post-processing, so the
create branch becomes a single `printf` instead:

    printf '[wsl2]\r\nkernel=%s\r\nlocalhostForwarding=true\r\nswap=0\r\n' "$WSL_LINE" > "$WSL_CONFIG"

`$WSL_LINE` goes through `%s`, never the format string, so its doubled
backslashes are not reinterpreted. The heredoc would have been fine for LF; it
is the wrong instrument once CRLF is the answer, and it leaves all three
branches agreeing instead of two out of three.

### Scope: the 42 remaining lint findings stay

Agreed with the instruction, for its stated reason: they are spread across the
whole file, 34 of them are `SC2086` at `cd $SOME_DIR` and `$0` sites, and a
sweep would collide with `build-patches` on rebase. Left as debt, to be swept
as a `[CLEANUP]` commit once that branch has landed. This AP does not add
`# shellcheck disable=SC2153` either — it belongs with the sweep that makes a
clean run meaningful.

## Analysis

All four are defects in released versions, in code paths that fail only in
conditions the author never hit:

- **1 and 2** are in `install_kernel`, in the `.wslconfig` writing path. Defect
  1 fires only when the file does not exist, which is exactly the fresh-machine
  case a clone-less installer targets, and never for anyone who already has one.
- **3** is invisible by construction: the leading `!` both inverts `[`'s
  failure and exempts the command from `set -e`, so `update` reports success
  while skipping the pull.
- **4** only fails when the script is invoked by absolute path from elsewhere,
  which is how a wrapper or a systemd unit would call it — and how the planned
  installer would.

They share a cause worth stating: `shellcheck` is this project's blocking
linter (shared shell `LINTING.md` §1) and has never once parsed this file.
Defects 1 and 3 are the parse errors; the other two are among what was hidden
behind them.

## Implementation Plan

Three commits, one functional change each, in this order. Each bumps the patch
digit per contract §3.3 and carries its own `### Fixed` bullet in
`## [Unreleased]` per `COMMIT.md` §4.3.

### Step 1 — `[FIX] v1.6.1`, defects 1 and 2

Same function, same writing path, and the line-ending decision spans both.

- Replace lines 552-558's broken construct with the `printf` above.
- Replace line 573's `echo "kernel=$WSL_LINE\r"` with
  `printf 'kernel=%s\r\n' "$WSL_LINE"`.
- Leave the `sed -i` branch alone: it already inserts a real `\r`.
- `SCRIPT_VERSION` → 1.6.1; `CHANGELOG.md` bullet.

**Verification**

- `bash -n build.sh` passes.
- `shellcheck build.sh` still aborts — defect 3 is the other parse error, so a
  clean parse is not expected until step 2. Confirm the *reported* errors are
  now only the line-1075 ones.
- Against a scratch `WSL_CONFIG`, never the real one: run the create branch and
  confirm the file holds exactly four INI lines, each ending `\r\n`, with
  nothing executed as a command; then run the append branch against a file
  without a `kernel=` line and confirm one `kernel=…\r\n` line is added and
  `cat -A` shows `^M$`, not `\r$`.

### Step 2 — `[FIX] v1.6.2`, defect 3

- Line 1075: `"$ZFS_AUTO_SNAPSHOT_DIR"]` → `"$ZFS_AUTO_SNAPSHOT_DIR" ]`.
- `SCRIPT_VERSION` → 1.6.2; `CHANGELOG.md` bullet.

**Verification**

- `bash -n build.sh` passes.
- `shellcheck build.sh` now **parses**: expect 42 findings, 0 errors. This is
  the first time the file has ever been analysed.
- Do **not** run `./build.sh update` — it re-checks-out the submodules and
  would discard the patch applied in the other session's tree. Verify the
  construct in isolation instead: `! [ -d "$PWD" ] || echo RAN` prints `RAN`.

### Step 3 — `[FIX] v1.6.3`, defect 4

- Line 823: `cd 3rdparty/WSL2-Linux-Kernel` → `cd "$WSL_KERNEL_SOURCE_DIR"`.
- Lines 828-832: the three `3rdparty/zfs/…` paths → `"$ZFS_SOURCE_DIR"/…`.
- `SCRIPT_VERSION` → 1.6.3; `CHANGELOG.md` bullet.

**Verification**

- `bash -n build.sh` passes; `shellcheck build.sh` still 0 errors, and the
  finding count does not rise (the new quoting should remove two SC2086 sites,
  not add any).
- `cd /tmp && /home/mdr/projects/zfs_on_wsl2/build.sh info` reports real kernel
  and OpenZFS versions instead of dying — the check that was failing before.
- `./build.sh info` from the checkout root still reports the same versions.

## Proposed commit message

Step 1, as the first of three:

    [FIX] v1.6.1 install_kernel could not create a .wslconfig

    "cat > "$WSL_CONFIG" | <<<EOL" is not a heredoc. Bash reads it as cat
    writing to the file, piped into a null command taking the here-string
    EOL, and then executes the four following lines as commands: [wsl2]
    runs the [ builtin and fails on the missing space, kernel=... becomes
    an assignment, and EOL is not a command. Under set -e install_kernel
    aborts there, so installing has never worked on a machine without an
    existing .wslconfig - and always worked on one with it, which is why
    this survived.

    The replacement is a printf rather than the obvious heredoc, because
    of the second defect in the same function: the branch that appends to
    an existing config wrote "kernel=$WSL_LINE\r" through echo, which
    without -e emits a literal backslash and r. The neighbouring sed
    branch inserts a real carriage return. Three branches, three
    conventions.

    CRLF wins, because it is what actually works: the .wslconfig on this
    machine is uniformly CRLF and boots the custom kernel. Dropping \r
    would append LF lines into a CRLF file and leave it mixed. A heredoc
    cannot emit CRLF without post-processing, so both branches now use
    printf and all three agree.

    Neither defect is reachable by shellcheck: the first is a parse error
    that aborts the run before the file is analysed.

## Change History

| Version | Date | Change |
|---------|------|--------|
| v1.0 | 2026-08-29 | First version. Four defects verified against `main` at `87fc7d6`; three corrections to the instruction recorded; CRLF chosen for `.wslconfig` with the reasoning; lint sweep deferred. |
