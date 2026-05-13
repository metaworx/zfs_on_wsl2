#!/usr/bin/env bash
set -euo pipefail

function is() {
  [ $1 -eq 0 ]
}

function hasSysconfig() {
  is $PYTHON_HAS_SYSCONFIG
}

function hasDistutils() {
  is $PYTHON_HAS_DISTUTILS
}

function hasDebSystem() {
  is $PYTHON_HAS_DEB_SYSTEM
}

function python_run() {
  local code="$1"
  local DEB_PYTHON_INSTALL_LAYOUT=${2-}

  if [[ "${DEB_PYTHON_INSTALL_LAYOUT-}" == "1" ]]; then
    DEB_PYTHON_INSTALL_LAYOUT=deb
  fi

  if [ -z "${DEB_PYTHON_INSTALL_LAYOUT-}" ]; then
    env -u DEB_PYTHON_INSTALL_LAYOUT python3 -Esc "$code"
  else
    env "DEB_PYTHON_INSTALL_LAYOUT=$DEB_PYTHON_INSTALL_LAYOUT" python3 -Esc "$code"
  fi
}

function python_deb_system() {

  if ! hasSysconfig; then
    return 1;
  fi

  local check="import sysconfig; print(sysconfig.get_default_scheme())"
  local without="$(python_run "$check")"
  local with="$(python_run "$check" 1)"

  test "$with" != "$without"
}

function python_path() {
	local path_name="$1"
	local path_code="$2"

	local path_result=$(python_run "$path_code" 2>/dev/null )
	printf "%-54s = %-45s = %s\n" "$path_name" "$path_result" "$(test -n "$path_result" && ls -l "$path_result" >/dev/null 2>&1 && echo "ok" || echo "n/a")"

  if hasDebSystem; then
    path_result=$(python_run "$path_code" 1 2>/dev/null )
    printf "%-54s = %-45s = %s\n" "${path_name}*" "$path_result" "$(test -n "$path_result" && ls -l "$path_result" >/dev/null 2>&1 && echo "ok" || echo "n/a")"
  fi
}

function true_or_false() {
    local _test=$1
    local ifTrue="$2"
    local ifFalse="$3"
    local caption="${4-}"
    local format="${5-"%-54s = %s\\n"}"

    if is $_test; then
      local value="$ifTrue"
    else
      local value="$ifFalse"
    fi

    if [ -z "$caption" ]; then
      echo "$value"
    else
      printf "$format" "$caption" "$value"
    fi
}

echo "Test Script Version: 2.0"
echo ""

command -v python3 >/dev/null 2>&1 || { echo "python3 not found"; exit 1; }

python_run "import sysconfig" 2>&1
PYTHON_HAS_SYSCONFIG=$?
true_or_false $PYTHON_HAS_SYSCONFIG "installed" "n/a" "syconfig"

python_run "from distutils import sysconfig" 2>&1
PYTHON_HAS_DISTUTILS=$?
true_or_false $PYTHON_HAS_DISTUTILS "installed" "n/a" "distutils"

python_deb_system
PYTHON_HAS_DEB_SYSTEM=$?
true_or_false $PYTHON_HAS_DEB_SYSTEM "available" "n/a" "deb_system"

test -z "${DEB_PYTHON_INSTALL_LAYOUT-}"
true_or_false $? "[not set]" "${DEB_PYTHON_INSTALL_LAYOUT-}" "DEB_PYTHON_INSTALL_LAYOUT"

printf "%-54s = %s\\n" "python bin" "$(which python3)"

PYTHON_DEFAULTS="
import sys

print()

for i in ['prefix', 'base_prefix', 'base_exec_prefix']:
  print('%-54s %s' % ('sys.%s:' % i, getattr(sys, i) if hasattr(sys, i) else 'n/a'))
#print('%-54s %s' % ('sys.base_prefix:', sys.base_prefix))
#print('%-54s %s' % ('sys.base_exec_prefix:', sys.base_exec_prefix))
"

echo ""
echo "## Python System Values:"
python_run "$PYTHON_DEFAULTS"



PYTHON_DEFAULTS="
import sysconfig

print()
scheme = sysconfig.get_default_scheme()
print('%-54s %s' % ('default scheme:', scheme))
for path in ['prefix', 'home', 'user']:
  print('%-54s %s' % (f'preferred scheme for {path}:', sysconfig.get_preferred_scheme(path)))
print()
for path in sysconfig.get_path_names():
  print('%-54s %s' % ('%s.%s' % (scheme, path), sysconfig.get_path(path, scheme)))
"

echo ""
true_or_false $PYTHON_HAS_DEB_SYSTEM "## Defaults (DEB_PYTHON_INSTALL_LAYOUT unset):" "## Defaults:"
python_run "$PYTHON_DEFAULTS"

if hasDebSystem; then
  echo ""
  echo "## Defaults (DEB_PYTHON_INSTALL_LAYOUT=deb):"
  python_run "$PYTHON_DEFAULTS" 1
fi

echo ""
echo "## Path evaluation (relevant to the build of pyzfs)"
echo ""

if hasSysconfig; then
  python_path 'sysconfig.get_path.purelib'              "import sysconfig; print(sysconfig.get_path('purelib'))"
  python_path 'sysconfig.get_path.purelib.posix_prefix' "import sysconfig; print(sysconfig.get_path('purelib', 'posix_prefix'))"
  python_path 'sysconfig.get_path.purelib.posix_local'  "import sysconfig; print(sysconfig.get_path('purelib', 'posix_local'))"

  python_path 'sysconfig.get_path.purelib.ax_python_devel' "
import sysconfig;
if hasattr(sysconfig, 'get_default_scheme'):
    scheme = sysconfig.get_default_scheme()
else:
    scheme = sysconfig._get_default_scheme()
if scheme == 'posix_local':
    # Debian's default scheme installs to /usr/local/ but we want to find headers in /usr/
    scheme = 'posix_prefix'
prefix = '\$prefix'
if prefix == 'NONE':
    prefix = '\$ac_default_prefix'
sitedir = sysconfig.get_path('purelib', scheme, vars={'base': prefix})
print(sitedir);"

  python_path 'sysconfig.get_path.platlib'              "import sysconfig; print(sysconfig.get_path('platlib'))"
  python_path 'sysconfig.get_path.platlib.posix_prefix' "import sysconfig; print(sysconfig.get_path('platlib', 'posix_prefix'))"
  python_path 'sysconfig.get_path.platlib.posix_local'  "import sysconfig; print(sysconfig.get_path('platlib', 'posix_local'))"

python_path 'sysconfig.get_path.platlib.ax_python_devel' "
import sysconfig;
if hasattr(sysconfig, 'get_default_scheme'):
    scheme = sysconfig.get_default_scheme()
else:
    scheme = sysconfig._get_default_scheme()
if scheme == 'posix_local':
    # Debian's default scheme installs to /usr/local/ but we want to find headers in /usr/
    scheme = 'posix_prefix'
prefix = '\$prefix'
if prefix == 'NONE':
    prefix = '\$ac_default_prefix'
sitedir = sysconfig.get_path('platlib', scheme, vars={'platbase': prefix})
print(sitedir);"

  python_path 'sysconfig.get_path.include'                            "import sysconfig;                print(sysconfig.get_path('include'))"
fi

if hasDistutils; then
  python_path 'distutils.sysconfig.get_python_inc'                    "from distutils import sysconfig; print(sysconfig.get_python_inc())"
  python_path 'distutils.sysconfig.get_python_inc(plat_specific=1)'   "from distutils import sysconfig; print(sysconfig.get_python_inc(plat_specific=1))"
  python_path 'distutils.sysconfig.get_python_lib(0,0)'               "from distutils import sysconfig; print(sysconfig.get_python_lib(0,0));"
  python_path 'distutils.sysconfig.get_python_lib(1,0)'               "from distutils import sysconfig; print(sysconfig.get_python_lib(1,0));"
  python_path 'distutils.sysconfig.get_python_lib()'                  "from distutils.sysconfig import get_python_lib; print(get_python_lib());"
fi

hasDebSystem && echo "*) with DEB_PYTHON_INSTALL_LAYOUT=deb_system"


#exit;

which hostnamectl >/dev/null 2>&1 && ( echo ""; echo "hostnamectl:"; hostnamectl | grep -E "Operating System|Kernel" )
which lsb-release >/dev/null 2>&1 && ( echo ""; echo "lsb-release:";  lsb-release -a )
which lsb_release >/dev/null 2>&1 && ( echo ""; echo "lsb_release:";  lsb_release -a )
for i in $(ls /etc/*-release); do echo ""; echo "$i:"; cat $i; done

echo ""
echo "APT packages:"
which dpkg >/dev/null 2>&1 && ( dpkg --get-selections | grep -vE deinstall\$ | grep -E ^python3 ) || echo "n/a"

echo ""
echo "DNF packages:"
which dnf >/dev/null 2>&1 && ( dnf list --installed | grep -E ^python3 ) || echo "n/a"

echo ""
echo "PIP packages:"
which pip >/dev/null 2>&1 && ( pip freeze | grep dist ) || echo "n/a"

echo ""
echo "All paths:"

python3 -Esc "
import sysconfig
print('Please note, the following paths don\'t need to make sense, as some are not meant to be run on this system!')
for scheme in sysconfig.get_scheme_names():
  for path in sysconfig.get_path_names():
    print('%-54s %s' % ('%s.%s' % (scheme, path), sysconfig.get_path(path, scheme)))
"

echo ""

# After all checks, exit with failure if sysconfig or distutils missing
if ! hasSysconfig || ! hasDistutils; then
    echo "ERROR: Python sysconfig or distutils not available – ZFS build will fail"
    exit 1
fi

exit 0
