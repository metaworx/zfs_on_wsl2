# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The version is `SCRIPT_VERSION` in `build.sh`, which `./build.sh info` reports.

Everything below was reconstructed from the git history. The project has never
cut a release tag, so each version is dated by the last commit that shipped
under it, not by a release. Versions 1.1.2 and 1.4.3 are absent because they
never existed in the tree. Kernel and OpenZFS version bumps are recorded because
they are what a given build actually produces.

## [Unreleased]

## [1.5.0] - 2026-08-07

### Fixed

- Kernel configuration options were not all applied. Missing dependencies meant
  some `CONFIG_*` settings were silently dropped, and Docker networking did not
  work as a result. The required options are now verified after configuration
  and the build fails if any of them did not take.

## [1.4.5] - 2026-08-03

### Fixed

- The WSL kernel version is read from `make kernelversion` rather than parsed
  out of the source tree.
- NAT modules are built into the kernel instead of built as modules, which
  Docker networking needs.

## [1.4.4] - 2026-08-03

### Changed

- `ZFS_DEBUG` is disabled, following its behaviour change in the new OpenZFS
  version.
- Indentation across `build.sh` was unified to tabs.

### Fixed

- `CONFIG_NFT_COMPAT` is enabled, which iptables-nft compatibility needs.

## [1.4.2] - 2026-08-01

### Added

- DirectX support in the kernel configuration (`DRM_HYPERV`).

### Changed

- Kernel updated to `linux-msft-wsl-6.18.40.1`, OpenZFS to `zfs-2.4.3`.

## [1.4.1] - 2026-05-18

### Changed

- WSL Utilities are updated only by the `install` command, rather than on every
  run.
- `README.md` carries the script's help text.

## [1.4.0] - 2026-05-18

### Added

- Kernel configuration for Docker: the netfilter, bridge and nftables options
  its networking depends on.

## [1.3.0] - 2026-05-14

### Added

- `build-zfs-auto-snapshot` command, which builds the `zfs-auto-snapshot`
  package.

## [1.2.3] - 2026-05-14

### Fixed

- WSL Utilities binary replacement during `wslu` installation.

### Changed

- `*.log` files are ignored by git.

## [1.2.2] - 2026-05-14

### Fixed

- Kernel configuration was edited with a `sed` block that worked line by line
  and produced duplicate-symbol warnings. It now goes through the kernel's own
  `scripts/config`, with `make olddefconfig` before and after so dependencies
  resolve.

## [1.2.1] - 2026-05-14

### Added

- `libunwind-dev` to the build environment.

## [1.2.0] - 2026-05-14

### Added

- Logging. `build`, `kernel-config`, `debs`, `env`, `install`, `update`, `wslu`
  and `pycheck` write a timestamped log file; `--log <file>`, `--log-dir <path>`
  and `--no-log` control where it goes and whether it is written at all.

## [1.1.3] - 2026-05-13

### Changed

- WSL Utilities installation handles the package's deprecation on current
  Ubuntu releases.

## [1.1.1] - 2026-05-13

### Added

- ZFS support in the kernel configuration.

### Changed

- OpenZFS updated through 2.2.8, 2.3.3 and 2.4.2; kernel updated to
  `v6.18.26.1`. pyzfs is disabled from 2.2.8 onward.
- The Python library directory is evaluated the way `ax_python_devel.m4` does
  it, so `pyzfs` builds against the right paths.

### Fixed

- ZFS version display, kernel installation, and WSL Utilities installation.

## [1.1.0] - 2025-06-21

### Added

- Commands and command-line arguments: `help`, `clean`, `update`, `debs`,
  `wslu` and `install`. The script's body was reorganised into functions to
  support them.
- The pip packages `distlib` and `packaging` are installed with the build
  environment.

### Changed

- The script stops on error instead of continuing.
- Kernel configuration is edited with `sed` rather than a patch file, which no
  longer matched after the source layout changed.
- Kernel updated through 5.15.90.1, 5.15.90.4 and 5.15.167.4; OpenZFS through
  2.1.9, 2.1.12 and 2.1.16.

### Fixed

- `config-wsl.patch` matched a symlink rather than the real path.

## Before 1.1.0

`build.sh` carried no version before 2023-02-27. What preceded it: the original
build script and its instructions, inherited from
[multiheaded/zfs_on_wsl2](https://github.com/multiheaded/zfs_on_wsl2), and this
fork's early work on it - kernel 5.15.83.1 with OpenZFS 2.1.7, submodule
progress output, and the install documentation. See the git history from
`35c429c` to `53b2ed0`.
