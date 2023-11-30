#!/usr/bin/env sh
# Note: This is an installation script to bootstrap installation of the
# PlanktoScope software distro on a Raspberry Pi. This is used to create
# the standard SD card images for the PlanktoScope project, and to create
# non-standard installations of the PlanktoScope software distro. Refer to
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
# Note: the code in this section was copied and adapted from
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
  if [ -z "${FORCE}" ]; then
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

has() {
  command -v "$1" 1>/dev/null 2>&1
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

get_tmpdir() {
  if has mktemp; then
    printf "%s" "$(mktemp --directory)"
  else
    # No really good options here--let's pick a default + hope
    printf "/tmp/planktoscope-%s" "$(date +%s)" "${suffix}"
  fi
}



# Utilities for interacting with Git repositories

resolve_commit() {
  mirror_dir="$1"
  query_type="$2"
  tag_prefix="$3"
  version_query="$4"
  if [ "${query_type}" = "tag" ]; then
    version_query="${tag_prefix}${version_query}"
  fi
  cmd="git -C ${mirror_dir} rev-list -n 1 ${version_query}"
  $cmd && return 0 || rc=$?

  error "Command failed (exit code $rc): ${BLUE}${cmd}${NO_COLOR}"
  printf "\n" >&2
  return $rc
}

resolve_tag() {
  mirror_dir="$1"
  tag_prefix="$2"
  commit_hash="$3"
  git -C "${mirror_dir}" describe --tags --exact-match --match "${TAG_PREFIX}*" "${commit_hash}" \
    2> /dev/null || printf ""
}

resolve_pseudoversion() {
  mirror_dir="$1"
  tag_prefix="$2"
  commit_hash="$3"
  git -C "${mirror_dir}" describe --tags --match "${TAG_PREFIX}*" --abbrev=7 "${commit_hash}" \
    2> /dev/null || printf ""
}

clone() {
  repo="$1"
  local_dir="$2"
  extra_flags="$3"
  verbosity=$(test -n "${VERBOSE-}" && echo "--verbose" || echo "--quiet")
  cmd="git clone ${extra_flags} ${verbosity} --filter=blob:none ${repo} ${local_dir}"
  $cmd && return 0 || rc=$?

  error "Command failed (exit code $rc): ${BLUE}${cmd}${NO_COLOR}"
  printf "\n" >&2
  return $rc
}

checkout() {
  local_dir="$1"
  commit_hash="$2"
  # Note: We only need progress information in verbose mode, but for some reason the
  # --no-progress flag seems to have no effect. For now, it's fine to have progress
  # information in non-verbose mode, since the repository is a giant download (~80 MiB).
  verbosity=$(test -n "${VERBOSE-}" && echo "--quiet" || echo "--quiet")
  cmd="git -C ${local_dir} checkout ${verbosity} ${commit_hash}"
  $cmd && return 0 || rc=$?

  error "Command failed (exit code $rc): ${BLUE}${cmd}${NO_COLOR}"
  printf "\n" >&2
  return $rc
}



# Main function

with_empty_placeholder() {
  if [ -z "$1" ]; then
    printf "(none)"
  else
    printf "%s" "$1"
  fi
}

install_git() {
  info "Installing Git..."
  # Note: this gives us no control over the version of Git installed. It would be better if we
  # could download a static binary which provides the Git commands we use, but there is no
  # obvious reputable source for this.
  if has apt-get; then # Debian/Ubuntu
    sudo apt-get -y update
    sudo apt-get -y install git
    printf "\n"
    return 0
  fi
  if has apk; then # Alpine Linux
    sudo apk add git
    printf "\n"
    return 0
  fi
  error "We don't know how to install Git on your system. Please install it and re-run this script."
}

# All code with side-effects is wrapped in a main function
# called at the bottom of the file, so that a truncated partial
# download doesn't cause execution of half a script.
main() {
  # Print configuration information

  pretty_repo=$(printf "%s" "${REPO}" | sed "s~^.*://~~")

  printf "  %s\n" "${UNDERLINE}Configuration${NO_COLOR}"
  info "${BOLD}Repo${NO_COLOR}:          ${GREEN}${pretty_repo}${NO_COLOR}"
  info "${BOLD}Version query${NO_COLOR}: ${GREEN}${VERSION_QUERY}${NO_COLOR}"
  info "${BOLD}Query type${NO_COLOR}:    ${GREEN}${QUERY_TYPE}${NO_COLOR}"
  info "${BOLD}Hardware${NO_COLOR}:      ${GREEN}${HARDWARE}${NO_COLOR}"
  if [ -n "${VERBOSE-}" ]; then
    VERBOSE=v
    info "${BOLD}Tag prefix${NO_COLOR}:    $(with_empty_placeholder "${TAG_PREFIX}")"
    info "${BOLD}Entrypoint${NO_COLOR}:    $(with_empty_placeholder "${SETUP_ENTRYPOINT}")"
    info "${BOLD}Verbose${NO_COLOR}:       yes"
  else
    VERBOSE=
  fi
  printf '\n'

  # Resolve versioning information

  if ! has git; then
    confirm "Your system doesn't have Git, but it is needed by the installer. Install Git?"
    install_git
  fi
  mirror_dir="$(get_tmpdir)"
  if [ -n "${VERBOSE-}" ]; then
    info "Downloading a minimal copy of the repository to resolve version information..."
  fi

  normalized_repo="${REPO}"
  if printf "%s" "${REPO}" | grep -q '@'; then
    # Repo was specified with SCP-like syntax for SSH protocol
    :
  elif printf "%s" "${REPO}" | grep -q '://'; then
    # Repo was specified with a protocol identifier
    :
  else
    normalized_repo="https://${REPO}"
  fi

  clone "${normalized_repo}" "${mirror_dir}" "--mirror"
  commit_hash="$(resolve_commit "${mirror_dir}" "${QUERY_TYPE}" "${TAG_PREFIX}" "${VERSION_QUERY}")"
  short_commit_hash="$(printf "%s" "${commit_hash}" | cut -c 1-7)"
  tag="$(resolve_tag "${mirror_dir}" "${TAG_PREFIX}" "${commit_hash}")"
  version_string="$(resolve_pseudoversion "${mirror_dir}" "${TAG_PREFIX}" "${commit_hash}" \
    | sed "s~^${TAG_PREFIX}~~")"
  rm -rf "${mirror_dir}"
  if [ -n "${VERBOSE-}" ]; then
    printf "\n"
  fi

  printf "  %s\n" "${UNDERLINE}Versioning${NO_COLOR}"
  info "${BOLD}Git Commit${NO_COLOR}:    ${short_commit_hash}"
  info "${BOLD}Git Tag${NO_COLOR}:       $(with_empty_placeholder "${tag}")"
  info "${BOLD}Version${NO_COLOR}:       ${version_string}"
  printf '\n'

  # Download the appropriate copy of the repository

  confirm "Download the PlanktoScope software distro setup scripts from ${normalized_repo}?"
  setup_dir="$(get_tmpdir)"

  info "Downloading the PlanktoScope distro setup scripts, please wait..."
  clone "${normalized_repo}" "${setup_dir}" "--no-checkout"
  checkout "${setup_dir}" "${commit_hash}"

  printf "\n"

  # Record versioning information

  local_etc_dir="${HOME}/.local/etc/pkscope-distro"
  info "Recording versioning information to ${local_etc_dir}..."
  if [ -d "${local_etc_dir}" ]; then
    warn "The ${local_etc_dir} directory already exists, so it will be erased."
    confirm "Are you sure you want to continue?"
    rm -rf "${local_etc_dir}"
  fi
  mkdir -p "${local_etc_dir}"

  installer_file_header="# This file was auto-generated by https://install.planktoscope.community/distro.sh!"
  installer_config_file="${local_etc_dir}/installer-config.yml"
  printf "%s\n" "${installer_file_header}" > "${installer_config_file}"
  printf "%s: \"%s\"\n" \
    "repo" "${pretty_repo}" \
    "version-query" "${VERSION_QUERY}" \
    "query-type" "${QUERY_TYPE}" \
    "hardware" "${HARDWARE}" \
    "tag-prefix" "${TAG_PREFIX}" \
    "setup-entrypoint" "${SETUP_ENTRYPOINT}" \
    >> "${installer_config_file}"

  installer_versioning_file="${local_etc_dir}/installer-versioning.yml"
  printf "%s\n" "${installer_file_header}" > "${installer_versioning_file}"
  printf "%s: \"%s\"\n" \
    "repo" "${pretty_repo}" \
    "commit" "${commit_hash}" \
    "tag" "${tag}" \
    "version" "${version_string}" \
    >> "${installer_versioning_file}"

  printf "\n"

  # Run the setup scripts

  confirm "Run the distro setup script at ${setup_dir}/${SETUP_ENTRYPOINT}?"
  info "Running the distro setup script, please wait..."
  printf "\n"
  "${setup_dir}/${SETUP_ENTRYPOINT}" "${HARDWARE}"
  rm -rf "${setup_dir}"

  printf "\n"
  completed "Finished running the install.planktoscope.community/distro.sh install script!"
}

usage() {
  printf "%s\n" \
    "distro.sh [options]" \
    "Download and install the PlanktoScope software distro."

  printf "\n%s\n" "Options:"
  printf "  %s\n    %s\n    %s\n" \
    "-r, --repo" \
    "Set the Git repo used for downloading the PlanktoScope distro setup scripts; defaults to HTTPS protocol" \
    "[default: ${DEFAULT_REPO}]" \
    \
    "-v, --version-query" \
    "Set the version of the PlanktoScope distro to install" \
    "[default: ${DEFAULT_VERSION_QUERY}]" \
    \
    "-t, --query-type" \
    "Set the type of version to install (options: branch, tag, hash)" \
    "[default: ${DEFAULT_QUERY_TYPE}]" \
    \
    "-H, --hardware" \
    "Set the hardware configuration for the PlanktoScope distro" \
    "[default: ${DEFAULT_HARDWARE}]" \
    \
    "--tag-prefix" \
    "Set the prefix for Git version tags when resolving version queries and tags" \
    "[default: ${DEFAULT_TAG_PREFIX}]" \
    \
    "--setup-entrypoint" \
    "Set the repository's setup script which will be invoked as part of the installation process" \
    "[default: ${DEFAULT_SETUP_ENTRYPOINT}]" \
    \
    "-f, -y, --force, --yes" \
    "Skip the confirmation prompt during installation" \
    "[don't skip by default]" \
    \
    "-V, --verbose" \
    "Enable verbose output for the installer" \
    "[don't be verbose by default]" \
    \
    "-h, --help" \
    "Display this help message" \
    "[don't display by default]"

  printf "\n%s\n" "Examples:"
  printf "  %s\n    %s\n" \
    "distro.sh -H pscopehat" \
    "Install the latest stable release for a PlanktoScope with the custom PlanktoScope HAT" \
    \
    "distro.sh ${GREEN}-v beta${NO_COLOR} -H adafruithat" \
    "Install the latest beta prerelease or stable release for a PlanktoScope with the Adafruit HAT" \
    "distro.sh ${GREEN}-v master${NO_COLOR} -H pscopehat" \
    "Install the latest development version for a Planktoscope with the custom PlanktoScope HAT" \
    "distro.sh ${GREEN}-t tag -v v2023.9.0-beta.1${NO_COLOR} -H adafruithat" \
    "Install the v2023.9.0-beta.1 prerelease for a PlanktoScope with the Adafruit HAT" \
    "distro.sh ${GREEN}-t hash -v bca19bf${NO_COLOR} -H pscopehat" \
    "Install the bca19bf commit for a PlanktoScope with the custom PlanktoScope HAT" \
    ""
}



# Imperative section

# Non-POSIX shells can break due to semantic differences.
verify_shell_is_posix_or_exit

# Set default values for the command-line arguments
DEFAULT_REPO="github.com/PlanktoScope/PlanktoScope"
if [ -z "${REPO-}" ]; then
  REPO="${DEFAULT_REPO}"
fi
DEFAULT_VERSION_QUERY="stable"
if [ -z "${VERSION_QUERY-}" ]; then
  VERSION_QUERY="${DEFAULT_VERSION_QUERY}"
fi
DEFAULT_QUERY_TYPE="branch"
if [ -z "${QUERY_TYPE-}" ]; then
  QUERY_TYPE="${DEFAULT_QUERY_TYPE}"
fi
DEFAULT_HARDWARE="pscopehat"
if [ -z "${HARDWARE-}" ]; then
  HARDWARE="${DEFAULT_HARDWARE}"
fi
DEFAULT_TAG_PREFIX="software/"
if [ -z "${TAG_PREFIX-}" ]; then
  TAG_PREFIX="${DEFAULT_TAG_PREFIX}"
fi
DEFAULT_SETUP_ENTRYPOINT="software/distro/setup/setup.sh"
if [ -z "${SETUP_ENTRYPOINT-}" ]; then
  SETUP_ENTRYPOINT="${DEFAULT_SETUP_ENTRYPOINT}"
fi
if [ -z "${FORCE-}" ]; then
  FORCE=""
fi
if [ -z "${VERBOSE-}" ]; then
  VERBOSE=""
fi

# Parse the command-line arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -r | --repo)
      REPO="$2"
      shift 2
      ;;
    -r=* | --repo=*)
      REPO="${1#*=}"
      shift 1
      ;;
    -v | --version-query)
      VERSION_QUERY="$2"
      shift 2
      ;;
    -v=* | --version-query=*)
      VERSION_QUERY="${1#*=}"
      shift 1
      ;;
    -t | --query-type)
      QUERY_TYPE="$2"
      shift 2
      ;;
    -t=* | --query-type=*)
      QUERY_TYPE="${1#*=}"
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
    --tag-prefix)
      TAG_PREFIX="$2"
      shift 2
      ;;
    --tag-prefix=*)
      TAG_PREFIX="${1#*=}"
      shift 1
      ;;
    --setup-entrypoint)
      SETUP_ENTRYPOINT="$2"
      shift 2
      ;;
    --setup-entrypoint=*)
      SETUP_ENTRYPOINT="${1#*=}"
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
    -h | --help)
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

# Ensure a valid query type
case "${QUERY_TYPE}" in
  branch | tag | hash)
    ;;
  *)
    error "Unknown query type: ${QUERY_TYPE}"
    usage
    exit 1
    ;;
esac

main
