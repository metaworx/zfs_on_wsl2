#!/bin/bash

# Fail on errors, undefined variables, or command piping errors
set -euo pipefail

SCRIPT_VERSION=1.1.3
SCRIPT_PATH=$(readlink -f $0)
SCRIPT_DIR=$(dirname $SCRIPT_PATH)

SUBMODULE_PATH=${SCRIPT_DIR}/3rdparty

WSL_KERNEL_SOURCE_DIR=${SUBMODULE_PATH}/WSL2-Linux-Kernel
ZFS_SOURCE_DIR=${SUBMODULE_PATH}/zfs

PARALLEL_THREADS=$(/usr/bin/nproc --all)

# Helper variable to print the information form print_info() only once
declare -gi info_printed=0

function print_info {
	(( $info_printed == 0 )) || return 0

	info_printed=1

	echo ""
	print_version

	echo ""
	echo "Script location:"
	echo $SCRIPT_DIR

	echo ""
	echo "WSL2 Kernel source location:"
	echo $WSL_KERNEL_SOURCE_DIR

	echo ""
	echo "WSL2 Kernel version:"
	version_kernel

	echo ""
	echo "OpenZFS source location:"
	echo $ZFS_SOURCE_DIR
	echo ""

	echo "OpenZFS version:"
	version_zfs
	echo ""
}

function print_version {
	echo "zfs_on_linux/build.sh v$SCRIPT_VERSION"
}

# Helper: returns 0 (true) if package $1 is installed, 1 otherwise
function apt_installed {
  apt list -q "$1" --installed 2>/dev/null | grep -q -E "^$1/"
}

# Generic function to install or upgrade a package
function install_or_upgrade {
    local package="$1"

    if command -v dpkg &>/dev/null; then
        # Debian/Ubuntu
        if dpkg -l | grep -q "^ii.*$package"; then
            echo "$package already installed. Upgrading..."
            sudo apt upgrade -y "$package"
        else
            echo "$package not installed. Installing..."
            sudo apt install -y "$package"
        fi
    elif command -v rpm &>/dev/null; then
        # Fedora/RHEL
        if rpm -q "$package" &>/dev/null; then
            echo "$package already installed. Upgrading..."
            sudo dnf upgrade -y "$package"
        else
            echo "$package not installed. Installing..."
            sudo dnf install -y "$package"
        fi
    else
        echo "Unknown package manager. Cannot install $package"
        return 1
    fi
}

function pip_installed {
  pip show "$pkg" &>/dev/null
}

function check_python_paths {
    echo ""
    echo "Checking Python paths (sysconfig, distutils, Debian layout)..."
    echo ""

    local pycheck_script="${SCRIPT_DIR}/3rdparty/python_path_evaluation.sh"
    if [[ ! -x "$pycheck_script" ]]; then
        echo "ERROR: Python evaluation script not found or not executable: $pycheck_script"
        exit 1
    fi

    # Run the script – it will exit with non‑zero on critical failures
    "$pycheck_script"
    echo ""
    echo "Python environment looks good."
}

function install_build_env {
  echo ""
  echo "Setting up build environment:"
  echo ""

  # List of required packages
  local packages=(
    alien
    autoconf
    automake
    bc
    bison
    build-essential
    dkms
    dwarves
    fakeroot
    flex
    gawk
    libaio-dev
    libattr1-dev
    libblkid-dev
    libelf-dev
    libffi-dev
    libssl-dev
    libtirpc-dev
    libtool
    libudev-dev
    python3
    python3-cffi
    python3-dev
    python3-pip
    python3-setuptools
    uuid-dev
    zlib1g-dev
  )

  local to_install=()

  for pkg in "${packages[@]}"; do
    if ! apt_installed "$pkg"; then
      to_install+=("$pkg")
    fi
  done

  if [ ${#to_install[@]} -gt 0 ]; then
    sudo apt install -yqq "${to_install[@]}"
  else
    echo "All required packages are already installed."
  fi

  # ---- Python packages (pip) ----
  local pip_packages=("distlib" "packaging")
  local pip_to_install=()

  for pkg in "${pip_packages[@]}"; do
    # pip show exits 0 if the package is installed, 1 otherwise
    if ! pip_installed "$pkg"; then
      pip_to_install+=("$pkg")
    fi
  done

  if [ ${#pip_to_install[@]} -gt 0 ]; then
    pip install "${pip_to_install[@]}"
  else
    echo "All required pip packages are already installed."
  fi
}

function prepare_kernel {
	echo ""
	echo "Preparing kernel:"
	echo ""
	cd $WSL_KERNEL_SOURCE_DIR

	prepare_kernel_config

	make -j${PARALLEL_THREADS} prepare scripts
	make -j${PARALLEL_THREADS} prepare
}

function prepare_kernel_config {
	echo ""
	echo "Preparing kernel config: $WSL_KERNEL_SOURCE_DIR/.config"
	echo ""

	cd $WSL_KERNEL_SOURCE_DIR

	if [ ! -f "$WSL_KERNEL_SOURCE_DIR/.config" ]; then
		cp Microsoft/config-wsl .config
	fi

	# some hardening options in the Linux kernel are not yet preconfigured in the WSL kernel config, so we do it ourselves...
	# and some new settings

	## explanation of the sed command used:
	## sed -n '               # don't implicitly print input
	## 	1h                    # put line 1 in the hold space
	## 	1!H                   # for subsequent lines, append to hold space
	## 	${                    # on the last line
	## 		g                   # put the hold space in pattern space
	## 		s/a/b/              # replace a with b
	## 		s/c/d/              # replace c with d
	## 		p                   # print
	## 	}
	## '
	sed -n '1h;1!H;${
			g
			s/\(CONFIG_KCSAN=n\|# CONFIG_KCSAN is not set\|\(# end of Generic Kernel Debugging Instruments\)\)/# CONFIG_KCSAN is not set\n<!!>\2/
			s/\(CONFIG_SLS=y\|# CONFIG_SLS is not set\|\(\n#\n# Power management and ACPI options\)\)/CONFIG_SLS=y\n<!!>\2/
			s/\(CONFIG_ZERO_CALL_USED_REGS=y\|# CONFIG_ZERO_CALL_USED_REGS is not set\|\(# end of Memory initialization\)\)/CONFIG_ZERO_CALL_USED_REGS=y\n<!!>\2/

			s/\(CONFIG_CPU_MITIGATIONS=y\|CONFIG_SPECULATION_MITIGATIONS=y\|# CONFIG_CPU_MITIGATIONS is not set\|\(\n#\n# Power management and ACPI options\)\)/CONFIG_CPU_MITIGATIONS=y\n<!!>\2/
			s/\(CONFIG_MITIGATION_RFDS=y\|# CONFIG_MITIGATION_RFDS is not set\|\(\n#\n# Power management and ACPI options\)\)/CONFIG_MITIGATION_RFDS=y\n<!!>\2/
			s/\(CONFIG_MITIGATION_SPECTRE_BHI=y\|# CONFIG_MITIGATION_SPECTRE_BHI is not set\|\(\n#\n# Power management and ACPI options\)\)/CONFIG_MITIGATION_SPECTRE_BHI=y\n<!!>\2/

			s/\(CONFIG_ARCH_CONFIGURES_CPU_MITIGATIONS=y\|# CONFIG_ARCH_CONFIGURES_CPU_MITIGATIONS is not set\|\(\n#\n# General architecture-dependent options\)\)/CONFIG_ARCH_CONFIGURES_CPU_MITIGATIONS=y\n<!!>\2/

			s/\(CONFIG_NF_FLOW_TABLE_PROCFS=y\|# CONFIG_NF_FLOW_TABLE_PROCFS is not set\|\(\n#\n# Xtables combined modules\)\)/CONFIG_NF_FLOW_TABLE_PROCFS=y\n<!!>\2/

			s/xx\(CONFIG_FUNCTION_ALIGNMENT_4B=y\|# CONFIG_FUNCTION_ALIGNMENT_4B is not set\|\(# end of General architecture-dependent options\)\)/CONFIG_FUNCTION_ALIGNMENT_4B=y\n<!!>\2/
			s/xx\(CONFIG_FUNCTION_ALIGNMENT_16B=y\|# CONFIG_FUNCTION_ALIGNMENT_16B is not set\|\(# end of General architecture-dependent options\)\)/CONFIG_FUNCTION_ALIGNMENT_16B=y\n<!!>\2/

			s/\(CONFIG_ZFS=y\|# CONFIG_ZFS is not set\|\(\n#\n# Kernel hardening options\)\)/CONFIG_ZFS=y\n<!!>\2/

			s/\(CONFIG_NFSD_V2_ACL=y\|# CONFIG_NFSD_V2_ACL is not set\|# CONFIG_NFSD_V2 is not set\)/# CONFIG_NFSD_V2 is not set/
			s/\(CONFIG_NFSD_V3=y\|# CONFIG_NFSD_V3 is not set\)//

			s/\(CONFIG_INIT_STACK_NONE=y\|# CONFIG_INIT_STACK_NONE is not set\)/CONFIG_INIT_STACK_NONE=y/
			s/\(CONFIG_CC_HAS_AUTO_VAR_INIT_PATTERN=y\|# CONFIG_CC_HAS_AUTO_VAR_INIT_PATTERN is not set\|\(CONFIG_INIT_STACK_NONE=y\)\)/CONFIG_CC_HAS_AUTO_VAR_INIT_PATTERN=y\n<!!>\2/
			s/\(CONFIG_CC_HAS_AUTO_VAR_INIT_ZERO_BARE=y\|# CONFIG_CC_HAS_AUTO_VAR_INIT_ZERO_BARE is not set\|\(CONFIG_INIT_STACK_NONE=y\)\)/CONFIG_CC_HAS_AUTO_VAR_INIT_ZERO_BARE=y\n<!!>\2/
			s/\(CONFIG_CC_HAS_AUTO_VAR_INIT_ZERO=y\|# CONFIG_CC_HAS_AUTO_VAR_INIT_ZERO is not set\|\(CONFIG_INIT_STACK_NONE=y\)\)/CONFIG_CC_HAS_AUTO_VAR_INIT_ZERO=y\n<!!>\2/
			s/\(CONFIG_INIT_STACK_ALL_PATTERN=y\|# CONFIG_INIT_STACK_ALL_PATTERN is not set\|\(CONFIG_INIT_STACK_NONE=y\)\)/\2\n<!!># CONFIG_INIT_STACK_ALL_PATTERN is not set/
			s/\(CONFIG_INIT_STACK_ALL_ZERO=y\|# CONFIG_INIT_STACK_ALL_ZERO is not set\|\(CONFIG_INIT_STACK_NONE=y\)\)/\2\n<!!># CONFIG_INIT_STACK_ALL_ZERO is not set/

			s/<!!>\n\?//g
			p
		}' \
		.config > .config.$PPID

	echo "Applied changes:"
	diff .config .config.$PPID && echo "none." || true
	mv .config.$PPID .config
}

function prepare_zfs {
	echo ""
	echo "Configuring ZFS source:"
	echo ""
	cd $ZFS_SOURCE_DIR

	sh autogen.sh
	./configure --prefix=/ --libdir=/lib --includedir=/usr/include --datarootdir=/usr/share --enable-linux-builtin=yes --with-linux=$WSL_KERNEL_SOURCE_DIR --with-linux-obj=$WSL_KERNEL_SOURCE_DIR --enable-systemd
}

function copy_zfs_builtin {
	echo ""
	echo "Copying ZFS module to kernel source:"
	echo ""
	cd $ZFS_SOURCE_DIR
	./copy-builtin $WSL_KERNEL_SOURCE_DIR
}

function build_zfs {
	echo ""
	echo "Building ZFS:"
	echo ""
	cd $ZFS_SOURCE_DIR
	make -j${PARALLEL_THREADS}
	make deb-utils
}

function enable_zfs_in_kernel {
	echo ""
	echo "Enabling ZFS in kernel config:"
	echo ""
	cd $WSL_KERNEL_SOURCE_DIR
	echo "CONFIG_ZFS=y" >> .config
}

function build_zfs_enabled_kernel {
	echo ""
	echo "Building new WSL2 kernel:"
	echo ""
	cd $WSL_KERNEL_SOURCE_DIR
	make -j${PARALLEL_THREADS}
}

function install_kernel_modules {
	echo ""
	echo "Install modules and metadata to /usr/lib:"
	echo ""
	cd $WSL_KERNEL_SOURCE_DIR
	set -x
	sudo make modules_install
	set +x
}

function install_kernel {
	install_wslu

	echo ""
	echo "Installing kernel:"
	echo ""

	local "KERNEL_TARGET_DIR=${1:-/mnt/c/wsl2_zfs}"

	if contains "$KERNEL_TARGET_DIR" ":"; then
		KERNEL_TARGET_DIR=$(wslpath -u "$KERNEL_TARGET_DIR")
	fi

	local "SYSTEM_DRIVE=$(wslpath -u "$(wslvar -s SystemDrive)\\")"
	local "MOUNT_ROOT=${SYSTEM_DRIVE: 0 : -2 }"

	if ! starts_with "$KERNEL_TARGET_DIR" "$MOUNT_ROOT"; then
		KERNEL_TARGET_DIR=$SYSTEM_DRIVE$KERNEL_TARGET_DIR
	fi

	local "KERNEL_TARGET=$KERNEL_TARGET_DIR/$(kernel_filename ${2:-})"
	local "KERNEL_TARGET_WIN=$(wslpath -w "$KERNEL_TARGET")"
	local "WSL_CONFIG_WIN=$(wslvar USERPROFILE)\\.wslconfig"
	local "WSL_CONFIG=$(wslpath "$WSL_CONFIG_WIN")"

	echo "Kernel path (windows):     $KERNEL_TARGET_WIN"
	echo "Kernel path (linux):       $KERNEL_TARGET"
	echo "WSL config file (windows): $WSL_CONFIG_WIN"
	echo "WSL config file (linux):   $WSL_CONFIG"
	echo ""

	cd "$SCRIPT_DIR"
	mkdir -p "$KERNEL_TARGET_DIR"
	cp 3rdparty/WSL2-Linux-Kernel/arch/x86/boot/bzImage "$KERNEL_TARGET"

	local WSL_LINE=${KERNEL_TARGET_WIN//\\/\\\\\\\\}

	if [ ! -f "$WSL_CONFIG" ]; then
		cat > "$WSL_CONFIG" | <<<EOL
		[wsl2]
		kernel=$WSL_LINE
		localhostForwarding=true
		swap=0
		EOL

	else
		echo "Current WSL config:"
		echo "---------8<--------"
		cat "$WSL_CONFIG"
		echo "---------8<--------"
		echo ""

		if grep -qe "^kernel\s*=" "$WSL_CONFIG"; then
			# 1. replace current kernel path with new path
			# 2. remove pre-existing line with the same setting
			sed -i -e "s|^\s*kernel\s*=[^\n]*|# \0\nkernel=$WSL_LINE\r|i;s|^\s*#\s*kernel=\s*${WSL_LINE//\\\\\\\\/\\\\\\\\\\\?}\s*||g;/^$/d" "$WSL_CONFIG"
		else
			# simply add the kernel setting to the config file
			echo "kernel=$WSL_LINE\r" >> "$WSL_CONFIG"
		fi
	fi

	echo "New WSL config:"
	echo "---------8<--------"
	cat "$WSL_CONFIG"
	echo "---------8<--------"
	echo ""

	exit
}

function install_debs {
	echo ""
	echo "Installing command line tools:"
	echo ""

	cd "$SCRIPT_DIR"
	set -x
	sudo apt install 3rdparty/zfs/zfs_*_amd64.deb 3rdparty/zfs/lib*.deb libzfs4linux
	set +x
}

function install_wslu {
    echo ""
    echo "Installing WSL Utilities:"
    echo ""

    # Detect distribution and version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$ID"
        VERSION="$VERSION_ID"
    else
        echo "Cannot detect distribution. Skipping wslu installation."
        return 1
    fi

    # Check for supported systems
    case "$DISTRO" in
        ubuntu)
            case "$VERSION" in
                20.04|22.04)
                    echo "Ubuntu $VERSION detected. Using PPA for wslu (deprecated but available)."
                    set +e
                    add-apt-repository -L | grep -q wslutilities/wslu
                    if (( $? != 0 )); then
                      set -xe
                      sudo add-apt-repository -y ppa:wslutilities/wslu
                    else
                      set -xe
                    fi
                    sudo apt update
                    set +x
                    install_or_upgrade wslu
                    ;;
                24.04|24.10|25.04)
                    echo "Ubuntu $VERSION detected. PPA is not available. Attempting to install from universe repository."
                    if apt-cache show wslu &>/dev/null; then
                        sudo apt update
                        install_or_upgrade wslu
                    else
                        echo "wslu package not found in repositories for Ubuntu $VERSION."
                        echo "Skipping wslu installation. This is not a critical dependency."
                        return 0
                    fi
                    ;;
                *)
                    echo "Unsupported Ubuntu version ($VERSION). Skipping wslu installation."
                    return 0
                    ;;
            esac
            ;;
        debian)
            echo "Debian detected. Installing wslu from official repositories."
            sudo apt update
            install_or_upgrade wslu
            ;;
        fedora)
            echo "Fedora detected. Installing wslu from official repositories."
            install_or_upgrade wslu
            ;;
        *)
            echo "Unsupported distribution ($DISTRO). Skipping wslu installation."
            return 0
            ;;
    esac

    echo "wslu installation completed (if available for your system)."
}

function make_all {
	install_build_env
	check_python_paths
	prepare_kernel
	prepare_zfs
	copy_zfs_builtin
	build_zfs
	enable_zfs_in_kernel
	build_zfs_enabled_kernel
	install_kernel_modules
}

function make_clean {
	echo ""
	echo "Cleaning source:"
	echo ""
	cd "$WSL_KERNEL_SOURCE_DIR"
	git reset --hard
	git clean -fdx
	make clean
	cd "$ZFS_SOURCE_DIR"
	git reset --hard
	git clean -fdx
}

function version_kernel {
	if [ -r 3rdparty/WSL2-Linux-Kernel/.config ]; then
		grep "Kernel Configuration" 3rdparty/WSL2-Linux-Kernel/.config | cut -d" " -f3
	elif [ -r 3rdparty/WSL2-Linux-Kernel/Microsoft/config-wsl ]; then
		grep "Kernel Configuration" 3rdparty/WSL2-Linux-Kernel/Microsoft/config-wsl | cut -d" " -f3
	else
		echo "N/A"
	fi
}

function version_zfs {
	if [ -r 3rdparty/zfs/META ]; then
		grep Version: 3rdparty/zfs/META | cut -f2 -d: | xargs
	elif [ -r 3rdparty/zfs/zfs.release ]; then
		cat 3rdparty/zfs/zfs.release
	else
		echo "N/A"
	fi
}

function kernel_filename {
	local "KERNEL_VERSION=kernel-$(version_kernel)_zfs-$(version_zfs)"

	if [[ "${1:-}" ]]; then
		echo "${KERNEL_VERSION}_${1}.bin"
	else
		echo "${KERNEL_VERSION}.bin"
	fi
}

function contains {
	case "$1" in
		*"$2"*) return 0;;
		*) return 1;;
	esac
}

function starts_with {
	case "$1" in
		"$2"*) return 0;;
		*) return 1;;
	esac
}

function print_help {
	cat << EOT

$(print_version)

SYNTAX:

    ./build.sh [ command [arguments] ]


COMMANDS:

    update          # Update source code

    clean           # Clean up source code

    build           # Build kernel from source

    kernel-config   # Prepare the kernel config

    install [ {KERNEL_TARGET_DIR} [ {KERNEL_SUFFIX} ] ]
                    #
                    # Install kernel to WSL2
                    #
                    # Optional arguments:
                    #
                    # - KERNEL_TARGET_DIR indicates the directory where the Kernel is stored on Windows
                    #
                    #       Default:  "C:\wsl2_zfs"
                    #       Note:     Can be given as a Windows path, or WSL path.
                    #
                    # - KERNEL_SUFFIX specifies a suffix to be added to the resulting kernel-name:
                    #       "$(kernel_filename SUFFIX)".
                    #
                    #       Default:  no suffix.
                    #       Note:     This parameter requires KERNEL_TARGET_DIR to be set.
                    #                 However, you can use "" if you still want to use the default value.

    debs            # Install zfs command-line binaries to current distro

    wslu            # Install/upgrade WSL Utilities command-line binaries to current distro

    env             # Install building environment

    pycheck         # Check Python paths without doing a full build

    help            # Show this help

    info            # Show information about directories and source versions

    version         # Show the script's version


INFO:
EOT
}


if (( $# == 0 )); then
	make_all
else
	while (( $# > 0 )); do
	case "$1" in

	clean)
		print_info
		shift
		make_clean
		;;

	build|"")
		print_info
		shift
		make_all
		;;

	kernel-config|"")
		print_info
		shift
		prepare_kernel_config
		;;

	debs)
		print_info
		shift
		install_debs
		;;

	env)
		print_info
		shift
		install_build_env
		;;

	info)
		shift
		print_info
		;;

	install)
		print_info
		shift
		install_kernel "$@"
		shift
		;;

	update)
		print_info
		shift
		git pull
		git submodule update --init --recursive --progress
		;;

	wslu)
		shift
		install_wslu
		;;

	pycheck)
		print_info
		shift
		check_python_paths
		;;

	-h|--help|help)
		shift
		print_help
		print_info
		;;

	-V|--version|version)
		shift
		print_version
		;;

	*)
		echo "Unknown command '$1' ..."
		exit 1
		;;

	esac
	done
fi

