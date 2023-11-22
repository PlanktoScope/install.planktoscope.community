#!/usr/bin/env sh
# Note: This is an installation script to bootstrap installation of the
# PlanktoScope software on a Raspberry Pi. This is used to create the
# standard SD card images for the PlanktoScope project, and to create
# non-standard installations of the PlanktoScope software. Refer to
# https://docs-edge.planktoscope.community/setup/software/nonstandard-install/
# for more information.
#
# This installation script is maintained at:
# https://github.com/PlanktoScope/install.planktoscope.community
#
# Licensing information:
# Except where otherwise indicated, source code provided here is covered by
# the following information:
# Copyright Ethan Li and PlanktoScope project contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# You can use the source code provided here under the GNU General Public
# License 3.0 or any later version of the GNU General Public License.

set -eu

# Utilities for user interaction
# Note: the code in this section was copied from the install script at
# https://github.com/starship/starship's install script,
# which is licensed under ISC and is copyrighted by the Starship Contributors.

BOLD="$(tput bold 2>/dev/null || printf '')"
GREY="$(tput setaf 0 2>/dev/null || printf '')"
UNDERLINE="$(tput smul 2>/dev/null || printf '')"
RED="$(tput setaf 1 2>/dev/null || printf '')"
GREEN="$(tput setaf 2 2>/dev/null || printf '')"
YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
BLUE="$(tput setaf 4 2>/dev/null || printf '')"
MAGENTA="$(tput setaf 5 2>/dev/null || printf '')"
NO_COLOR="$(tput sgr0 2>/dev/null || printf '')"

info() {
  printf '%s\n' "${BOLD}${GREY}>${NO_COLOR} $*"
}

warn() {
  printf '%s\n' "${YELLOW}! $*${NO_COLOR}"
}

error() {
  printf '%s\n' "${RED}x $*${NO_COLOR}" >&2
}

completed() {
  printf '%s\n' "${GREEN}✓${NO_COLOR} $*"
}

confirm() {
  if [ -z "${FORCE-}" ]; then
    printf "%s " "${MAGENTA}?${NO_COLOR} $* ${BOLD}[y/N]${NO_COLOR}"
    set +e
    read -r yn </dev/tty
    rc=$?
    set -e
    if [ $rc -ne 0 ]; then
      error "Error reading from prompt (please re-run with the '--yes' option)"
      exit 1
    fi
    if [ "$yn" != "y" ] && [ "$yn" != "yes" ]; then
      error 'Aborting (please answer "yes" to continue)'
      exit 1
    fi
  fi
}

# Utilities for portability
# Note: the code in this section was copied from the install script at
# https://github.com/starship/starship's install script,
# which is licensed under ISC and is copyrighted by the Starship Contributors.

has() {
  command -v "$1" 1>/dev/null 2>&1
}

curl_is_snap() {
  curl_path="$(command -v curl)"
  case "$curl_path" in
    /snap/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Make sure user is not using zsh or non-POSIX-mode bash, which can cause issues
verify_shell_is_posix_or_exit() {
  if [ -n "${ZSH_VERSION+x}" ]; then
    error "Running installation script with \`zsh\` is known to cause errors."
    error "Please use \`sh\` instead."
    exit 1
  elif [ -n "${BASH_VERSION+x}" ] && [ -z "${POSIXLY_CORRECT+x}" ]; then
    error "Running installation script with non-POSIX \`bash\` may cause errors."
    error "Please use \`sh\` instead."
    exit 1
  else
    true  # No-op: no issues detected
  fi
}

get_tmpfile() {
  suffix="$1"
  if has mktemp; then
    printf "%s.%s" "$(mktemp)" "${suffix}"
  else
    # No really good options here--let's pick a default + hope
    printf "/tmp/starship.%s" "${suffix}"
  fi
}

# Test if a location is writeable by trying to write to it. Windows does not let
# you test writeability other than by writing: https://stackoverflow.com/q/1999988
test_writeable() {
  path="${1:-}/test.txt"
  if touch "${path}" 2>/dev/null; then
    rm "${path}"
    return 0
  else
    return 1
  fi
}

# Utilities for getting and extracting the software
# Note: the code in this section was copied from the install script at
# https://github.com/starship/starship's install script,
# which is licensed under ISC and is copyrighted by the Starship Contributors.

download() {
  file="$1"
  url="$2"

  if has curl && curl_is_snap; then
    warn "curl installed through snap cannot download the PlanktoScope setup scripts."
    warn "Searching for other HTTP download programs..."
  fi

  if has curl && ! curl_is_snap; then
    cmd="curl --fail --silent --location --output $file $url"
  elif has wget; then
    cmd="wget --quiet --output-document=$file $url"
  elif has fetch; then
    cmd="fetch --quiet --output=$file $url"
  else
    error "No HTTP download program (curl, wget, fetch) found, exiting…"
    return 1
  fi

  $cmd && return 0 || rc=$?

  error "Command failed (exit code $rc): ${BLUE}${cmd}${NO_COLOR}"
  printf "\n" >&2
  return $rc
}

unpack() {
  archive=$1
  bin_dir=$2
  sudo=${3-}

  case "$archive" in
    *.tar.gz)
      flags=$(test -n "${VERBOSE-}" && echo "-xzvof" || echo "-xzof")
      ${sudo} tar "${flags}" "${archive}" -C "${bin_dir}"
      return 0
      ;;
    *.zip)
      flags=$(test -z "${VERBOSE-}" && echo "-qqo" || echo "-o")
      UNZIP="${flags}" ${sudo} unzip "${archive}" -d "${bin_dir}"
      return 0
      ;;
  esac

  error "Unknown package extension."
  printf "\n"
  info "This was probably caused by a bug in this script--please file a bug report at"
  info "https://github.com/PlanktoScope/install.planktoscope.community/issues"
  return 1
}

# Handle command-line args

# Set default argument values
if [ -z "${VERSION-}" ]; then
  VERSION="stable"
fi
if [ -z "${VERSION_TYPE-}" ]; then
  VERSION_TYPE="branch"
fi
if [ -z "${HARDWARE-}" ]; then
  HARDWARE="pscopehat"
fi
if [ -z "${BASE_URL-}" ]; then
  BASE_URL="https://github.com/PlanktoScope/PlanktoScope/archive"
fi
if [ -z "${HOME_PATH-}" ]; then
  HOME_PATH="/home/pi"
fi
if [ -z "${FORCE-}" ]; then
  FORCE=""
fi
if [ -z "${VERBOSE-}" ]; then
  VERBOSE=""
fi

usage() {
  printf "%s\n" \
    "install.sh [options]" \
    "Download and install the specified version of the PlanktoScope software distro."

  printf "\n%s\n" "Options:"
  printf "  %s\n    %s\n    %s\n" \
    "-t, --version-type" \
    "Set the type of version to install (options: options: \"branch\", \"version-tag\", \"hash\")" \
    "[default: \"${VERSION_TYPE}\"]" \
    \
    "-v, --version" \
    "Set the version of the PlanktoScope software to install" \
    "[default: \"${VERSION}\"]" \
    \
    "-H, --hardware" \
    "Set the hardware configuration for the PlanktoScope software" \
    "[default: \"${HARDWARE}\"]" \
    \
    "-B, --base-url" \
    "Set the base URL used for downloading the PlanktoScope software setup scripts" \
    "[default: \"${BASE_URL}\"]" \
    \
    "-H, --home-path" \
    "Set the path which various components of the PlanktoScope software will be installed to" \
    "[default: \"${HOME_PATH}\"]" \
    \
    "-f, -y, --force, --yes" \
    "Skip the confirmation prompt during installation" \
    "[default: (don't skip)]" \
    \
    "-V, --verbose" \
    "Enable verbose output for the installer" \
    "[default: (don't be verbose)]" \
    \
    "-h, --help" \
    "Display this help message" \
    "[default: (don't display)]"

  printf "\n%s\n" "Examples:"
  printf "  %s\n    %s\n" \
    "install.sh -H pscopehat" \
    "Install the latest stable release for a PlanktoScope with the custom PlanktoScope HAT" \
    \
    "install.sh -v beta -H adafruithat" \
    "Install the latest beta prerelease or stable release for a PlanktoScope with the Adafruit HAT" \
    "install.sh -v master -H pscopehat" \
    "Install the latest development version for a Planktoscope with the custom PlanktoScope HAT" \
    "install.sh -t version-tag -v v2023.9.0-beta.1 -H adafruithat" \
    "Install the v2023.9.0-beta.1 prerelease for a PlanktoScope with the Adafruit HAT" \
    "install.sh -t hash -v 30ee726 -H adafruithat" \
    "Install the  for a PlanktoScope with the Adafruit HAT" \
    ""
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -t | --version-type)
      VERSION_TYPE="$2"
      shift 2
      ;;
    -t=* | --version-type=*)
      VERSION_TYPE="${1#*=}"
      shift 1
      ;;
    -v | --version)
      VERSION="$2"
      shift 2
      ;;
    -v=* | --version=*)
      VERSION="${1#*=}"
      shift 1
      ;;
    -H | --hardware)
      HARDWARE="$2"
      shift 2
      ;;
    -H=* | --hardware=*)
      HARDWARE="${1#*=}"
      shift 1
      ;;
    -b | --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    -b=* | --base-url=*)
      BASE_URL="${1#*=}"
      shift 1
      ;;
    -H | --home-path)
      HOME_PATH="$2"
      shift 2
      ;;
    -H=* | --home-path=*)
      HOME_PATH="${1#*=}"
      shift 1
      ;;
    -f | -y | --force | --yes)
      FORCE=1
      shift 1
      ;;
    -f=* | -y=* | --force=* | --yes=*)
      FORCE="${1#*=}"
      shift 1
      ;;
    -V | --verbose)
      VERBOSE=1
      shift 1
      ;;
    -V=* | --verbose=*)
      VERBOSE="${1#*=}"
      shift 1
      ;;
    -h | --help)https://github.com/PlanktoScope/PlanktoScope/archive/30ee726.tar.gz
      usage
      exit
      ;;
    *)
      error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

printf "  %s\n" "${UNDERLINE}Configuration${NO_COLOR}"
info "${BOLD}Version type${NO_COLOR}: ${GREEN}${VERSION_TYPE}${NO_COLOR}"
info "${BOLD}Version${NO_COLOR}:      ${GREEN}${VERSION}${NO_COLOR}"
info "${BOLD}Hardware${NO_COLOR}:     ${GREEN}${HARDWARE}${NO_COLOR}"
if [ -n "${VERBOSE-}" ]; then
  VERBOSE=v
  info "${BOLD}Verbose${NO_COLOR}:      yes"
else
  VERBOSE=
fi
printf '\n'

# Download the appropriate copy of the repository

URL=""
case "$VERSION_TYPE" in
  "version-tag")
    URL="${BASE_URL}/refs/tags/software/${VERSION}.tar.gz"
    ;;
  "branch")
    URL="${BASE_URL}/refs/heads/${VERSION}.tar.gz"
    ;;
  "hash")
    URL="${BASE_URL}/${VERSION}.tar.gz"
    ;;
  *)
    error "Unknown version type \"${VERSION_TYPE}\"."
    usage
    exit 1
    ;;
esac
info "Download URL: ${UNDERLINE}${BLUE}${URL}${NO_COLOR}"
confirm "Install the PlanktoScope software?"
if [ "${HOME_PATH}" != "/home/pi" ]; then
  warn "Currently, the PlanktoScope software only works if it's installed to /home/pi, but you have asked to install it to ${HOME_PATH}"
  confirm "Are you sure you want to install to ${HOME_PATH}?"
fi

#tar -xzf "${VERSION}.tar.gz"
#rm "${VERSION}.tar.gz"
#case "${VERSION_TYPE}" in
#  "version-tag")
#    mv "PlanktoScope-${VERSION#"v"}" ~/device-backend
#    ;;
#  "branch")
#    mv "PlanktoScope-$(sed 's/\//-/g' <<< ${VERSION})" ~/device-backend
#    ;;
#  "hash")
#    mv "PlanktoScope-${VERSION}" ~/device-backend
#    ;;
#  *)
#    echo "Unknown backend version type ${VERSION_TYPE}"
#    exit 1
#    ;;
#esac

# Write the version information to somewhere

# Run the setup scripts
