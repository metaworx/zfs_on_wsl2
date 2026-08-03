#!/bin/bash

# Fail on errors, undefined variables, or command piping errors
set -euo pipefail

SCRIPT_VERSION=1.4.4
SCRIPT_PATH=$(readlink -f $0)
SCRIPT_DIR=$(dirname $SCRIPT_PATH)

SUBMODULE_PATH=${SCRIPT_DIR}/3rdparty

WSL_KERNEL_SOURCE_DIR=${SUBMODULE_PATH}/WSL2-Linux-Kernel
ZFS_SOURCE_DIR=${SUBMODULE_PATH}/zfs
ZFS_AUTO_SNAPSHOT_DIR=${SUBMODULE_PATH}/zfs-auto-snapshot

PARALLEL_THREADS=$(/usr/bin/nproc --all)

# Logging variables
declare -g LOG_DIR=""
declare -g LOG_FILE="/dev/null"
declare -gi LOG_ENABLED=1

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
    local package="$1"
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'
}

# Generic function to install or upgrade a package
function install_or_upgrade {
    local package="$1"

    if command -v dpkg &>/dev/null; then
        # Debian/Ubuntu
        if apt_installed $package; then
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
    libunwind-dev
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
    sudo apt install -yq "${to_install[@]}"
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

	# Use the kernel’s own config tool to modify the .config file cleanly.
	# This avoids the “override: reassigning to symbol” warnings.
	if [ ! -x scripts/config ]; then
		echo "ERROR: scripts/config not found. Kernel source may be incomplete."
		exit 1
	fi

	# First, ensure that all dependencies are resolved
	make olddefconfig >/dev/null 2>&1

	# Disable KCSAN (kernel concurrency sanitizer)
	scripts/config --disable KCSAN
	# Enable SLS (straight-line speculation)
	scripts/config --enable SLS
	# Enable zero-call-used-regs
	scripts/config --enable ZERO_CALL_USED_REGS
	# Enable CPU mitigations (mitigations for Spectre, Meltdown, etc.)
	scripts/config --enable CPU_MITIGATIONS
	scripts/config --enable MITIGATION_RFDS
	scripts/config --enable MITIGATION_SPECTRE_BHI
	scripts/config --enable ARCH_CONFIGURES_CPU_MITIGATIONS
	# Enable NF_FLOW_TABLE_PROCFS
	scripts/config --enable NF_FLOW_TABLE_PROCFS
	# Enable ZFS (the main point)
	scripts/config --enable ZFS
	scripts/config --disable ZFS_DEBUG
	# Disable NFSD v2 (since v2 ACL is removed)
	scripts/config --disable NFSD_V2
	scripts/config --disable NFSD_V2_ACL
	# Remove NFSD v3 line (it's optional, but we leave it unchanged unless explicitly disabled)
	scripts/config --disable NFSD_V3
	# Set stack initialisation to NONE (this will automatically disable the ALL_PATTERN/ALL_ZERO variants)
	scripts/config --set-val INIT_STACK none
  # Direct-X
  scripts/config --enable CONFIG_DRM_HYPERV

  # Docker compatibility
  scripts/config --enable CONFIG_BRIDGE
  scripts/config --enable CONFIG_BRIDGE_NETFILTER
  scripts/config --enable CONFIG_BRIDGE_IGMP_SNOOPING
  scripts/config --enable CONFIG_BRIDGE_VLAN_FILTERING

  # Netfilter core
  scripts/config --enable CONFIG_NETFILTER
  scripts/config --enable CONFIG_NETFILTER_ADVANCED
  scripts/config --enable CONFIG_NF_CONNTRACK
  scripts/config --enable CONFIG_NF_NAT
  scripts/config --enable CONFIG_NF_TABLES
  scripts/config --enable CONFIG_NF_TABLES_IPV4
  scripts/config --enable CONFIG_NF_TABLES_IPV6
  scripts/config --enable CONFIG_NF_TABLES_ARP
  scripts/config --enable CONFIG_NETFILTER_XTABLES

  # IPv4 iptables
  scripts/config --enable CONFIG_IP_NF_IPTABLES
  scripts/config --enable CONFIG_IP_NF_FILTER
  scripts/config --enable CONFIG_IP_NF_NAT
  scripts/config --enable CONFIG_IP_NF_RAW
  scripts/config --enable CONFIG_IP_NF_MANGLE
  scripts/config --enable CONFIG_IP_NF_TARGET_MASQUERADE
  scripts/config --enable CONFIG_IP_NF_TARGET_REJECT

  # IPv6 iptables
  scripts/config --enable CONFIG_IP6_NF_IPTABLES
  scripts/config --enable CONFIG_IP6_NF_FILTER
  scripts/config --enable CONFIG_IP6_NF_NAT

  # Netfilter extensions Docker needs
  scripts/config --enable CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
  scripts/config --enable CONFIG_NETFILTER_XT_MATCH_CONNTRACK
  scripts/config --enable CONFIG_NETFILTER_XT_MATCH_COMMENT
  scripts/config --enable CONFIG_NETFILTER_XT_MATCH_MULTIPORT
  scripts/config --enable CONFIG_NETFILTER_XT_MATCH_IPRANGE
  scripts/config --enable CONFIG_NETFILTER_XT_MATCH_STATE
  scripts/config --enable CONFIG_NETFILTER_XT_MATCH_TCPMSS
  scripts/config --enable CONFIG_NETFILTER_XT_TARGET_MASQUERADE
  scripts/config --enable CONFIG_NETFILTER_XT_TARGET_TCPMSS
  scripts/config --enable CONFIG_NETFILTER_XT_TARGET_LOG

  # Nftables NAT chain support
  scripts/config --enable CONFIG_NFT_NAT
  scripts/config --enable CONFIG_NFT_MASQ
  scripts/config --enable CONFIG_NFT_CHAIN_NAT

  # Additional bridge support
  scripts/config --enable CONFIG_BRIDGE_NF_EBTABLES
  scripts/config --enable CONFIG_IP_NF_ARPTABLES

	# Force the changes to take effect and resolve any new dependencies
	make olddefconfig >/dev/null 2>&1

	echo "Kernel configuration updated via scripts/config."
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

function build_zfs_auto_snapshot {
    echo ""
    echo "Building zfs-auto-snapshot package (with corrected dependencies):"
    echo ""

    # Clone or update repository
    if [[ ! -d "$ZFS_AUTO_SNAPSHOT_DIR/.git" ]]; then
      	set -x
        git clone https://github.com/zfsonlinux/zfs-auto-snapshot.git "$ZFS_AUTO_SNAPSHOT_DIR"
      	set +x
    else
        (cd "$ZFS_AUTO_SNAPSHOT_DIR" && git pull)
    fi

   (
   cd "$ZFS_AUTO_SNAPSHOT_DIR"

    # Patch debian/control to depend on 'zfs' instead of 'zfsutils-linux'
    if [[ -f debian/control ]]; then
        sed -i 's/zfsutils-linux/zfs/g' debian/control
        echo "Patched debian/control: now depends on 'zfs'."
    else
        echo "ERROR: debian/control not found. Cannot patch dependencies."
        return 1
    fi

    # Build the package
    if ! command -v dpkg-buildpackage &>/dev/null; then
        echo "Installing build tools for debian package..."
        install_or_upgrade -y devscripts build-essential
    fi

    # Build with -us -uc to skip signing
    dpkg-buildpackage -us -uc -b

    echo "zfs-auto-snapshot .deb packages have been built."
    )
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
	check_wslu || return $?

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

  # Clean up any leftover custom development packages that may conflict
  echo "Checking for leftover old ZFS development packages..."
  for pkg in libzfs5-devel libzfs6-devel; do
      if apt_installed "$pkg"; then
          echo "Removing conflicting package: $pkg"
        	set -x
          sudo dpkg --remove --force-remove-reinstreq "$pkg" 2>/dev/null || true
        	set +x
      fi
  done

	cd "$SCRIPT_DIR"

	# Enable nullglob so non-matching globs expand to nothing
  shopt -s nullglob
	local -a args=( "$SCRIPT_DIR"/3rdparty/zfs/zfs_*_amd64.deb "$SCRIPT_DIR"/3rdparty/zfs/lib*.deb "$SCRIPT_DIR"/3rdparty/zfs-auto-snapshot/zfs-auto-snapshot*.deb )
  shopt -u nullglob

  if [[ ${#args[@]} -eq 0 ]]; then
      echo "ERROR: No .deb files found to install!"
      exit 1
  fi

	set -x
	sudo apt install "${args[@]}"
#  install_or_upgrade libzfs4linux
	set +x
}

function install_wslu {
    echo ""
    echo "Installing WSL Utilities:"
    echo ""

    # Check network before attempting install
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        echo "WARNING: No network connectivity. Cannot install wslu."
        echo "The 'install' command requires wslvar to locate Windows paths."
        echo "Please check your network connection and try again."
        return 1
    fi

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

}

function check_wslu {
    echo ""
    echo "Checking WSL Utilities:"
    echo ""

    # Detect WSL version
    local wsl_version=""
    if uname -r | grep -q "microsoft-standard-WSL2"; then
        wsl_version=2
    elif uname -r | grep -q "microsoft"; then
        wsl_version=1
    else
        echo "Not running under WSL. Skipping wslu setup."
        return 0
    fi

    # Check if wslvar is already available (from a previous install or native)
    if command -v wslvar &>/dev/null; then
        echo "wslvar already available at $(which wslvar)"

        # If it's the symlink to /init (WSL2+), it's built-in
        if [ "$(readlink -f $(which wslvar) 2>/dev/null)" = "/init" ]; then
            echo "wslvar is built into WSL (modern version). No installation needed."
            return 0
        fi

        return 0
    fi

    # wslvar not found – need to install wslu
    echo "wslvar not found. WSL Utilities may be missing."

    # On WSL2 with modern kernel (5.15+), wslu is optional but useful
    if [[ $wsl_version -eq 2 ]]; then
        echo "WSL2 detected. wslu provides 'wslvar' for Windows registry access."
        install_wslu || return $?
    else
        # WSL1 – definitely need wslu
        echo "WSL1 detected. wslu is required for Windows interop."
        install_wslu || return $?
    fi

    # Verify installation succeeded
    if command -v wslvar &>/dev/null; then
        echo "wslu installed successfully."
    else
        # Fallback if wslvar is missing
        function wslvar() {
            local var_name="$1"

            if [[ "$var_name" == "-s" ]]; then
                shift
                var_name="$1"
            fi

            local result

            result="$(win_env "$var_name")"
            # Try to read from /proc/self/environ (works for some variables)
            if [[ -n "$result"  ]]; then
                echo "$result"
            else
                echo "ERROR: Cannot resolve $var_name without wslvar" 1>&2
                return 1
            fi
        }

        if [[ "$(wslvar -s SystemDrive)" != "C:" ]]; then
            echo "ERROR: wslvar still not available after installation attempt."
            echo "Please install wslu manually: sudo apt install wslu"
            return 1
        fi

        export -f wslvar

        # In check_wslu, after wslvar check
        if ! command -v wslpath &>/dev/null; then
            echo "ERROR: wslpath not found. This WSL installation is too old."
            return 1
        fi

        return 0
    fi
}

# Helper: get Windows environment variable
win_env() {
    local p
    # < /dev/null is crucial, for cmd.exe not interfering with STDIN
    if ! p=$(cd /mnt/c && "/mnt/c/Windows/System32/cmd.exe" /c "echo %$1%" < /dev/null 2>/dev/null); then
      return $?
    fi

    p="${p%$'\r'}" # strip carriage return \r

    if [[ -z "$p" ]]; then
      return 1
    fi

    echo "$p"
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
	[[ -d "$ZFS_AUTO_SNAPSHOT_DIR/.git" ]] && build_zfs_auto_snapshot
}

function make_clean {
	echo ""
	echo "Cleaning source:"
	echo ""
	local dir
	for dir in "$WSL_KERNEL_SOURCE_DIR" "$ZFS_SOURCE_DIR" "$ZFS_AUTO_SNAPSHOT_DIR"; do
	  [ -d "$dir" ] || continue
	  echo "- $dir ..."
	  cd "$dir"
	  git reset --hard
	  git clean -fdx
  done
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

function log_header {
  local cmd="$1"

  if [[ $LOG_ENABLED -eq 1 ]]; then
    # Determine log file path
    if [[ -z "$LOG_FILE" || "$LOG_FILE" == "/dev/null" ]]; then
        local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
        if [[ -n "$LOG_DIR" ]]; then
            LOG_FILE="${LOG_DIR}/${timestamp}_${cmd}.log"
        else
            LOG_FILE="${SCRIPT_DIR}/${timestamp}_${cmd}.log"
        fi
    fi

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"

    echo "Logging to: $LOG_FILE"
  else
    LOG_FILE=/dev/null
  fi

  # Run the command with output captured by tee
  {
    echo "=== Command: $* ==="
    echo "=== Started at: $(date) ==="

    if [[ $LOG_ENABLED -eq 1 ]]; then
      echo "=== Log file: $LOG_FILE ==="
    fi

    echo ""
    print_info
    echo ""
  } | tee "$LOG_FILE"
}

function log_footer {
  {
    echo ""
    echo "=== Finished at: $(date) ==="
    echo "=== Exit code: $1 ==="
  } | tee -a "$LOG_FILE"

  [[ "$1" -ne 0 ]] && exit $1
}

function print_help {
	cat << EOT

$(print_version)

SYNTAX:

    ./build.sh [options] [ command [arguments] ]


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


LOGGING OPTIONS:

    --no-log        # Disable logging (output only to console)
    --log <file>    # Write log to specified file path
    --log-dir <path> # Write log to directory with auto-generated filename

    Log files are created automatically for commands: build, kernel-config, debs, env, install, update, wslu, pycheck
    Default log format: {ISO-date}_{command}.log in script directory


INFO:
EOT
}

# Parse global logging options before command
declare -a cmd_args=()
declare log_arg=""

# Parse logging arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-log)
            LOG_ENABLED=0
            shift
            ;;
        --log)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --log requires a file path argument"
                exit 1
            fi
            LOG_FILE="$2"
            LOG_ENABLED=1
            shift 2
            ;;
        --log-dir)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --log-dir requires a directory path argument"
                exit 1
            fi
            LOG_DIR="$2"
            LOG_ENABLED=1
            shift 2
            ;;
        *)
            cmd_args+=("$1")
            shift
            ;;
    esac
done

# Reset arguments for main processing
set -- "${cmd_args[@]}"

if (( $# == 0 )); then
	set -- "build"
fi
	while (( $# > 0 )); do
	case "$1" in

	clean)
		print_info
		shift
		make_clean
		;;

	build)
		log_header "$1"
		shift
    make_all 2>&1 | tee -a "$LOG_FILE"
    log_footer ${PIPESTATUS[0]}
		;;

	kernel-config)
		log_header "$1"
		shift
		prepare_kernel_config 2>&1 | tee -a "$LOG_FILE"
    log_footer ${PIPESTATUS[0]}
		;;

	debs)
		log_header "$1"
		shift
		install_debs 2>&1 | tee -a "$LOG_FILE"
    log_footer ${PIPESTATUS[0]}
		;;

	env)
		log_header "$1"
		shift
		install_build_env 2>&1 | tee -a "$LOG_FILE"
    log_footer ${PIPESTATUS[0]}
		;;

	info)
		shift
		print_info
		;;

	install)
		log_header "$@"
		shift
		install_kernel "$@" 2>&1 | tee -a "$LOG_FILE"
    log_footer ${PIPESTATUS[0]}
    break;
		;;

	update)
		log_header "$1"
		shift
		{
		  git pull && git submodule update --init --recursive --progress && {
		    ! [ -d "$ZFS_AUTO_SNAPSHOT_DIR"] || git -C "$ZFS_AUTO_SNAPSHOT_DIR" pull
		  }
    } 2>&1 | tee -a "$LOG_FILE"
    log_footer ${PIPESTATUS[0]}
		;;

  build-zfs-auto-snapshot)
		log_header "$1"
    shift
    build_zfs_auto_snapshot 2>&1 | tee -a "$LOG_FILE"
    log_footer ${PIPESTATUS[0]}
    ;;

	wslu)
		log_header "$1"
		shift
		install_wslu 2>&1 | tee -a "$LOG_FILE"
    log_footer ${PIPESTATUS[0]}
		;;

	pycheck)
		log_header "$1"
		shift
		check_python_paths 2>&1 | tee -a "$LOG_FILE"
    log_footer ${PIPESTATUS[0]}
		;;

	-h|--help|help)
		shift
		print_help
		print_info
		break
		;;

	-V|--version|version)
		shift
		print_version
		break
		;;

	*)
		echo "Unknown command '$1' ..."
		exit 1
		;;

	esac
	done
