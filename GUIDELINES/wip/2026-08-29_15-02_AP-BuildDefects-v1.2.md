# AP BuildDefects v1.2: Fix four build.sh defects

Written 2026-08-29 15:02 CEST, on `main`, from the instruction in
`messages/` dated 14:25. Revision of v1.1 (14:58): `SCRIPT_VERSION` carries a
`-wipN` pre-release suffix, one per commit. Everything else stands.

## Discussion

### What changed in v1.2

`SCRIPT_VERSION` becomes `1.6.1-wip1`, `1.6.1-wip2`, `1.6.1-wip3` across the
three commits, and the `[RELEASE]` that eventually cuts 1.6.1 drops the suffix.

This answers the objection v1.1 was working around. One bump and three commits
means two of the three ship a version string that claims to be 1.6.1 while
being something else; a `-wipN` suffix says out loud that the state is
unreleased, and still resolves to the single 1.6.1 the release will carry. It
is valid SemVer pre-release syntax, and it sorts before `1.6.1` rather than
after, which is the correct ordering for what it denotes.

Safe to do: `SCRIPT_VERSION` is read in exactly one place, `print_version` at
line 59, which echoes it. Nothing parses it, and `kernel_filename` derives
build artefact names from the kernel and OpenZFS versions, not from this.

### What changed in v1.1

v1.0 proposed a patch bump per commit — 1.6.1, 1.6.2, 1.6.3 — reading contract
§3.3's "the bump rides with the change" literally. The user's ruling:

> only bump one patch on the first edit

So: **three `[FIX]` commits, one bump** — refined in v1.2 to one bump plus a
`-wipN` counter. All three ship as 1.6.1 whenever a release is cut.

This is the better reading. Three bumps would publish 1.6.1 and 1.6.2 as
versions no build ever ran and no release ever contained — numbers that exist
only inside a single afternoon's git history. §3.3's rule exists so a behaviour
change is never released under an unchanged version; one bump ahead of the
release satisfies that. `## [Unreleased]` accumulates the three bullets, and a
later `[RELEASE]` promotes them together.

The contract's §3.3 currently states the per-commit reading. It should say
this instead, but not in these commits — it is a documentation change, and
folding it in would widen a narrow diff the `build-patches` rebase depends on.
Noted for afterwards.

### What I verified, rather than took on trust

All five line numbers hold on `main` at `87fc7d6`:

| Claim | Line | Verified |
|-------|------|----------|
| `<<<EOL` | 553 | yes |
| `echo "kernel=$WSL_LINE\r"` | 573 | yes |
| `cd 3rdparty/WSL2-Linux-Kernel && make kernelversion` | 823 | yes |
| `-r 3rdparty/zfs/META` | 828 | yes |
| `[ -d "$ZFS_AUTO_SNAPSHOT_DIR"]` | 1075 | yes |

Behaviour, reproduced rather than reasoned about:

- `bash -n build.sh` passes; `shellcheck build.sh` aborts at line 554 with
  SC1035/SC1073/SC1020/SC1072 and never analyses the file.
- Defect 3 in isolation: `! [ -d "/tmp"] || echo PULL` prints
  ``[: missing `]'``, does not run the right-hand side, and exits **0**.
- Defect 4: `cd /tmp && /home/mdr/projects/zfs_on_wsl2/build.sh info` dies with
  `cd: 3rdparty/WSL2-Linux-Kernel: No such file or directory` at line 823.

### Three corrections to the instruction

1. **SC2153 is at line 536, not 632.** Line 632 is blank. The assignment is
   `local "KERNEL_TARGET_WIN=$(wslpath -w "$KERNEL_TARGET")"`.
2. **The post-fix lint count is 42, not 43** — 34 × SC2086, not 35. Measured on
   a scratch copy with defects 1 and 3 fixed: 34 × SC2086, 1 each of SC2181,
   SC2155, SC2153, SC2046, SC2034, SC2028, SC2004, SC1091. SC2153 is present,
   so the false-positive warning stands.
3. **Its closing observation is stale.** `## [Unreleased]` is not empty and the
   v1.6.0 logging work does have an entry — closed by a history rewrite after
   the instruction was written. `a6ea27c` and `e564564` are now `9d6ba09` and
   `87fc7d6`.

### The line-ending decision, which the instruction leaves open

**Decision: CRLF, consistently, in all three branches.**

The evidence is the machine's own file. `/mnt/c/Users/mdr/.wslconfig` is
uniformly CRLF and currently boots the custom kernel, so CRLF is the
demonstrated-working convention here. Dropping `\r` would append LF lines into a
CRLF file and leave it mixed, which is worse than either convention alone.

This **deviates from the instruction's suggested replacement** for defect 1. A
`<<-EOL` heredoc cannot emit CRLF without post-processing, so the create branch
becomes a single `printf`:

    printf '[wsl2]\r\nkernel=%s\r\nlocalhostForwarding=true\r\nswap=0\r\n' "$WSL_LINE" > "$WSL_CONFIG"

`$WSL_LINE` goes through `%s`, never the format string, so its doubled
backslashes are not reinterpreted. The heredoc is the right instrument for LF
and the wrong one for CRLF.

### Scope: the 42 remaining lint findings stay

Agreed with the instruction, for its stated reason: 34 of them are `SC2086` at
`cd $SOME_DIR` and `$0` sites spread across the file, and a sweep would collide
with `build-patches` on rebase. Deferred to a `[CLEANUP]` commit once that
branch lands, together with the `# shellcheck disable=SC2153` that only makes
sense alongside a clean run.

## Analysis

All four are defects in released versions, in paths that fail only under
conditions the author never hit:

- **1 and 2** are in `install_kernel`'s `.wslconfig` writing path. Defect 1
  fires only when the file does not exist — the fresh-machine case a clone-less
  installer targets, and never the case for anyone who already has one.
- **3** is invisible by construction: the leading `!` both inverts `[`'s failure
  and exempts the command from `set -e`, so `update` reports success while
  skipping the pull.
- **4** fails only when the script is invoked by absolute path from elsewhere —
  how a wrapper, a systemd unit, or the planned installer would call it.

They share a cause worth stating: `shellcheck` is this project's blocking linter
(shared shell `LINTING.md` §1) and has never once parsed this file. Defects 1
and 3 are the parse errors; the other two are among what hid behind them.

## Implementation Plan

Three commits, one functional change each, in this order. Each carries its own
`### Fixed` bullet in `## [Unreleased]` per `COMMIT.md` §4.3. The patch digit is bumped once, in
step 1; each step then marks its own unreleased state with `-wipN`.

### Step 1 — `[FIX] v1.6.1`, defects 1 and 2

Same function, same writing path, and the line-ending decision spans both.

- Replace lines 552-558's broken construct with the `printf` above.
- Replace line 573's `echo "kernel=$WSL_LINE\r"` with
  `printf 'kernel=%s\r\n' "$WSL_LINE"`.
- Leave the `sed -i` branch alone: it already inserts a real `\r`.
- `SCRIPT_VERSION` → `1.6.1-wip1`; `CHANGELOG.md` bullet.

**Verification**

- `bash -n build.sh` passes.
- `shellcheck build.sh` still aborts — defect 3 is the other parse error, so a
  clean parse is not expected until step 2. Confirm the reported errors are now
  only the line-1075 ones.
- Against a scratch `WSL_CONFIG`, never the real one: run the create branch and
  confirm the file holds exactly four INI lines, each ending `\r\n`, with
  nothing executed as a command; then run the append branch against a file with
  no `kernel=` line and confirm `cat -A` shows `^M$`, not a literal `\r`.

### Step 2 — `[FIX]`, defect 3

- Line 1075: `"$ZFS_AUTO_SNAPSHOT_DIR"]` → `"$ZFS_AUTO_SNAPSHOT_DIR" ]`.
- `SCRIPT_VERSION` → `1.6.1-wip2`; `CHANGELOG.md` bullet.

**Verification**

- `bash -n build.sh` passes.
- `shellcheck build.sh` now **parses**: expect 42 findings, 0 errors — the
  first time the file has ever been analysed.
- Do **not** run `./build.sh update`: it re-checks-out the submodules and would
  discard the patch applied in the other session's tree. Verify the construct in
  isolation: `! [ -d "$PWD" ] || echo RAN` prints `RAN`.

### Step 3 — `[FIX]`, defect 4

- Line 823: `cd 3rdparty/WSL2-Linux-Kernel` → `cd "$WSL_KERNEL_SOURCE_DIR"`.
- Lines 828-832: the three `3rdparty/zfs/…` paths → `"$ZFS_SOURCE_DIR"/…`.
- `SCRIPT_VERSION` → `1.6.1-wip3`; `CHANGELOG.md` bullet.

**Verification**

- `bash -n build.sh` passes; `shellcheck build.sh` still 0 errors, and the
  finding count does not rise — the new quoting should remove two SC2086 sites,
  not add any.
- `cd /tmp && /home/mdr/projects/zfs_on_wsl2/build.sh info` reports real kernel
  and OpenZFS versions instead of dying.
- `./build.sh info` from the checkout root still reports the same versions.

## Proposed commit message

Step 1, as the first of three:

    [FIX] v1.6.1-wip1 install_kernel could not create a .wslconfig

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
| v1.2 | 2026-08-29 | `SCRIPT_VERSION` carries `-wip1`/`-wip2`/`-wip3` across the three commits, dropped by the `[RELEASE]` that cuts 1.6.1. Two of three commits would otherwise ship a version string claiming to be a release they are not. Verified nothing parses the constant. |
| v1.1 | 2026-08-29 | One patch bump on the first commit instead of one per commit, per the user's ruling. Reasoning recorded: three bumps would publish versions no build ever ran. Notes that contract §3.3 states the per-commit reading and should be corrected after these commits, not inside them. |
| v1.0 | 2026-08-29 | First version. Four defects verified against `main` at `87fc7d6`; three corrections to the instruction recorded; CRLF chosen for `.wslconfig` with the reasoning; lint sweep deferred. |
