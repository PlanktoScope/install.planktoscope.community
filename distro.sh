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
    printf "/tmp/planktoscope-%s.%s" "$(date +%s)" "${suffix}"
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

check_home_dir() {
  home_dir="${1%/}"

  if [ ! -d "${home_dir}" ]; then
    error "Installation location ${home_dir} does not appear to be a directory"
    info "Make sure the location exists and is a directory, then try again."
    usage
    exit 1
  fi

  if ! test_writeable "${home_dir}"; then
    error "You are not able to modify directory ${home_dir}!"
    info "Switch to a user which can modify that directory, then try again."
    exit 1
  fi
}



# Utilities for getting and extracting the software
# Note: the code in this section was copied and adapted from
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
    verbosity=$(test -n "${VERBOSE-}" && echo "" || echo "--silent --show-error")
    cmd="curl --fail ${verbosity} --location --output $file $url"
  elif has wget; then
    verbosity=$(test -n "${VERBOSE-}" && echo "" || echo "--no-verbose")
    cmd="wget ${verbosity} --output-document=$file $url"
  else
    error "No HTTP download program (curl, wget) found, exiting..."
    return 1
  fi

  $cmd && return 0 || rc=$?

  error "Command failed (exit code $rc): ${BLUE}${cmd}${NO_COLOR}"
  printf "\n" >&2
  return $rc
}

unpack() {
  archive="$1"
  home_dir="$2"

  case "${archive}" in
    *.tar.gz)
      # Listing of individual files being extracted is too verbose for us
      #flags=$(test -n "${VERBOSE-}" && echo "-xzvof" || echo "-xzof")
      flags="-xzof"
      tar "${flags}" "${archive}" -C "${home_dir}"
      return 0
      ;;
    *.zip)
      # Listing of individual files being extracted is too verbose for us
      flags=$(test -z "${VERBOSE-}" && echo "-qo" || echo "-o")
      UNZIP="${flags}" unzip "${archive}" -d "${home_dir}"
      return 0
      ;;
  esac

  error "Unknown package extension."
  printf "\n"
  info "This was probably caused by a bug in this script--please file a bug report at"
  info "https://github.com/PlanktoScope/install.planktoscope.community/issues"
  return 1
}



# Utilities for downloading a temporary copy of jq
# Note: some code in this section was copied and adapted from
# https://github.com/starship/starship's install script,
# which is licensed under ISC and is copyrighted by the Starship Contributors.

# Currently supporting:
#   - windows (Git Bash)
#   - macos
#   - linux
detect_jq_platform() {
  platform="$(uname -s | tr '[:upper:]' '[:lower:]')"

  case "${platform}" in
    msys_nt*) platform="windows" ;;
    cygwin_nt*) platform="windows";;
    # mingw is Git-Bash
    mingw*) platform="windows" ;;
    darwin) platform="macos" ;;
  esac

  printf '%s' "${platform}"
}

# Currently supporting:
#   - amd64
#   - i386
#   - armel
#   - armhf
#   - arm64
detect_jq_arch() {
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

  case "${arch}" in
    x86_64) arch="amd64" ;;
    i686) arch="i386" ;;
    armv6) arch="armel" ;;
    armv7) arch="armhf" ;;
    aarch64) arch="arm64" ;;
  esac

  # `uname -m` in some cases mis-reports 32-bit OS as 64-bit, so double check
  if [ "${arch}" = "amd64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then
    arch=i386
  elif [ "${arch}" = "arm64" ] && [ "$(getconf LONG_BIT)" -eq 32 ]; then
    arch=armhf
  fi

  printf '%s' "${arch}"
}

detect_jq_target() {
  target="$platform-$arch"

  printf '%s' "${target}"
}

download_jq() {
  version="1.7"
  download_base_url="https://github.com/jqlang/jq/releases/download"
  platform="$(detect_jq_platform)"
  arch="$(detect_jq_arch)"
  download_url="${download_base_url}/jq-${version}/jq-${platform}-${arch}"
  binary="$(get_tmpfile "bin")"
  download "${binary}" "${download_url}"
  chmod a+x "${binary}"
  printf "%s" "${binary}"
}



# Utilities for querying the GitHub API to resolve version information

query() {
  url="$1"
  if has curl; then
    cmd="curl --fail --silent $url"
  elif has wget; then
    cmd="wget --quiet -O - $url"
  else
    "No HTTP download program (curl, wget) found, exiting..."
  fi

  $cmd && return 0 || rc=$?

  error "Command failed (exit code $rc): ${BLUE}${cmd}${NO_COLOR}"
  printf "\n" >&2
  return $rc
}

query_ref() {
  api_base_url="$1"
  ref="$2" # ref can be a branch name, a shortened hash, or a full hash
  url="${api_base_url}/commits/${ref}"
  query "${url}" && return 0 || rc=$?

  error "Couldn't find Git commit for query \"${ref}\""
  printf "\n" >&2
  return $rc
}

get_hash_of_commit() {
  jq="$1"
  commit="$2"
  jq -er ".sha" <<< "${commit}" && return 0 || rc=$?

  error "Couldn't find Git commit hash for commit"
  printf "\n" >&2
  return $rc
}

get_timestamp_of_commit() {
  jq="$1"
  commit="$2"
  jq -er ".commit.committer.date" <<< "${commit}" && return 0 || rc=$?

  error "Couldn't find Git commit timestamp for commit"
  printf "\n" >&2
  return $rc
}

resolve_tag_as_hash() {
  jq="$1"
  tags="$2"
  tag="$3"
  jq -er ".[] | select(.name==\"${tag}\") | .commit.sha" <<< "${tags}" \
    && return 0 || rc=$?

  error "Couldn't find Git tag \"${tag}\""
  printf "\n" >&2
  return $rc
}

sort_versions() {
  # This performs ascending sort of semantic versions: the highest version goes to the end
  sed '/-/! s~$~_~' | \
    sort -V | \
    sed 's~_$~~'
}

get_tag_of_hash() {
  jq="$1"
  tags="$2"
  commit_hash="$3"
  jq -r ".[] | select(.commit.sha==\"${commit_hash}\") | .name" <<< "${tags}" \
    | sort_versions \
    | tail -n 1
}

get_tags() {
  api_base_url="$1"
  url="${api_base_url}/tags"
  query "${url}"
}

get_base_version() {
  # FIXME: implement this!
  # Note: in order to determine the base version we'll have to do a breadth-first search
  # of all ancestral commits to determine which ones are tagged. This is way too complex
  # to do in bash! Instead, we should just use logic already implemented in Forklift to
  # accomplish this.
  printf "v0.0.0"
}

assemble_pseudoversion() {
  # This produces a pseudoversion according to https://go.dev/ref/mod#pseudo-versions
  base_version="$1"
  commit_timestamp="$2"
  commit_hash="$3"
  if [ -z "${base_version}" -o "${base_version}" == "v0.0.0" ]; then
    base_version="v0.0.0-"
  elif grep -q '-' <<< "${base_version}"; then
    base_version="${base_version}.0."
  elif grep -q '^v\([[:digit:]]\+.\)\{2,2\}[[:digit:]]\+$' <<< "${base_version}"; then
    # Note: this only matches base versions of form v1.2.3, but also allowing a tag prefix
    # (e.g. v1.2.3)
    major_minor="$(sed 's~\(v\([[:digit:]]\+.\)\{2,2\}\).*~\1~' <<< "${base_version}")"
    patch="$(sed 's~^v\([[:digit:]]\+.\)\{2,2\}~~' <<< "${base_version}")"
    patch="$((patch+1))"
    base_version="${major_minor}${patch}-0."
  else
    base_version="v0.0.0-"
  fi
  printf "%s%s-%s" \
    "${base_version}" \
    "$(sed "s~[-T:Z]~~g" <<< "${commit_timestamp}")" \
    "$(cut -c 1-14 <<< "${commit_hash}")"
}


# Main function

with_empty_placeholder() {
  if [ -z "$1" ]; then
    printf "(none)"
  else
    printf "%s" "$1"
  fi
}

# All code with side-effects is wrapped in a main function
# called at the bottom of the file, so that a truncated partial
# download doesn't cause execution of half a script.
main() {
  # Print configuration information

  printf "  %s\n" "${UNDERLINE}Configuration${NO_COLOR}"
  info "${BOLD}Repo${NO_COLOR}:          ${GREEN}github.com/${REPO}${NO_COLOR}"
  info "${BOLD}Version query${NO_COLOR}: ${GREEN}${VERSION_QUERY}${NO_COLOR}"
  info "${BOLD}Query type${NO_COLOR}:    ${GREEN}${QUERY_TYPE}${NO_COLOR}"
  info "${BOLD}Hardware${NO_COLOR}:      ${GREEN}${HARDWARE}${NO_COLOR}"
  if [ -n "${VERBOSE-}" ]; then
    VERBOSE=v
    info "${BOLD}Verbose${NO_COLOR}:      yes"
  else
    VERBOSE=
  fi
  printf '\n'

  # Ensure we have jq to resolve versioning information

  if has jq; then
    jq="jq"
  else
    if [ -n "${VERBOSE-}" ]; then
      info "Downloading a temporary tool to parse responses from GitHub's API, to resolve version information..."
    fi
    jq="$(download_jq)"
    if [ -n "${VERBOSE-}" ]; then
      printf "\n"
    fi
  fi

  # Resolve versioning information
  # FIXME: instead of using jq to query the GitHub API, it would be cleaner, more correct,
  # more efficient, and more generalizable to use Forklift's internal functionality for
  # downloading a Git repo and resolving version queries and determining pseudoversions.
  # Since the forklift binary is large, we could provide that functionality in a separate
  # binary, and maybe call it "forkgit" or something.

  api_base_url="https://api.github.com/repos/${REPO}"
  tags="$(get_tags "${api_base_url}")"
  if [ "${QUERY_TYPE}" == "tag" ]; then
    commit_hash="$(resolve_tag_as_hash "${jq}" "${tags}" "${TAG_PREFIX}${VERSION_QUERY}")"
    commit="$(query_ref "${api_base_url}" "${commit_hash}")"
  else
    commit="$(query_ref "${api_base_url}" "${VERSION_QUERY}")"
    commit_hash="$(get_hash_of_commit "${jq}" "${commit}")"
  fi
  short_commit_hash="$(cut -c 1-7 <<< "${commit_hash}")"
  commit_timestamp="$(get_timestamp_of_commit "${jq}" "${commit}")"
  tag="$(get_tag_of_hash "${jq}" "${tags}" "${commit_hash}")"
  if grep -q "^${TAG_PREFIX}" <<< "${tag}"; then
    version_type="version"
    tag_version="$(sed "s~^${TAG_PREFIX}~~" <<< "${tag}")"
    version_string="${tag_version}"
  else
    version_type="pseudoversion"
    tag_version="$(get_base_version)"
    version_string="$(assemble_pseudoversion "${tag_version}" "${commit_timestamp}" "${commit_hash}")"
  fi

  printf "  %s\n" "${UNDERLINE}Versioning${NO_COLOR}"
  info "${BOLD}Git Commit${NO_COLOR}:    ${short_commit_hash}"
  info "${BOLD}Commit Time${NO_COLOR}:   $(sed -e "s~T~ ~" -e "s~Z~ UTC~" <<< ${commit_timestamp})"
  info "${BOLD}Git Tag${NO_COLOR}:       $(with_empty_placeholder "${tag}")"
  info "${BOLD}Version Type${NO_COLOR}:  ${version_type}"
  info "${BOLD}Tag Version${NO_COLOR}:   ${tag_version}"
  info "${BOLD}Version${NO_COLOR}:       ${version_string}"
  printf '\n'

  # Download the appropriate copy of the repository

  download_url="https://github.com/${REPO}/archive/${short_commit_hash}.tar.gz"
  info "Download URL: ${UNDERLINE}${BLUE}${download_url}${NO_COLOR}"
  confirm "Install the PlanktoScope software distro?"
  if [ "${HOME_DIR}" != "/home/pi" ]; then
    warn "Currently, the PlanktoScope distro only works when it's installed to /home/pi, but you have asked to install it to ${HOME_DIR}"
    confirm "Are you sure you want to continue?"
  fi
  check_home_dir "${HOME_DIR}"
  install_dir="${HOME_DIR}/PlanktoScope"

  info "Downloading the PlanktoScope distro, please wait..."
  archive="$(get_tmpfile "tar.gz")"
  download "${archive}" "${download_url}"
  dir_name="$(tar -ztf "${archive}" | head -n 1 | sed -e 's~/.*~~')"
  extracted_dir="$(get_tmpdir)"
  unpack "${archive}" "${extracted_dir}"
  rm "${archive}"
  if [ -d "${install_dir}" ]; then
    warn "The ${install_dir} directory already exists, so it will be erased."
    confirm "Are you sure you want to continue?"
    rm -rf "${install_dir}"
  fi
  mv "${extracted_dir}/${dir_name}" "${install_dir}"
  rm -rf "${extracted_dir}"

  # Record versioning information

  local_etc_dir="${HOME_DIR}/.local/etc/pkscope-distro"
  if [ -d "${local_etc_dir}" ]; then
    warn "The ${local_etc_dir} directory already exists, so it will be erased."
    confirm "Are you sure you want to continue?"
    rm -rf "${local_etc_dir}"
  fi
  mkdir -p "${local_etc_dir}"
  installer_config_file="${local_etc_dir}/installer-config.json"
  jq --null-input \
    --arg "versionQuery" "${VERSION_QUERY}" \
    --arg "queryType" "${QUERY_TYPE}" \
    --arg "hardware" "${HARDWARE}" \
    --arg "repo" "github.com/${REPO}" \
    --arg "version" "${version_string}" \
    '{"version-query": $versionQuery, "query-type": $queryType, "hardware": $hardware, "repo": $repo, "version": $version}' \
    > "${installer_config_file}"

  installer_version_lock_file="${local_etc_dir}/installer-version-lock.yml"
  printf "%s: %s\n" \
    "type" "${version_type}" \
    "tag-prefix" "${TAG_PREFIX}" \
    "tag-version" "${tag_version}" \
    "commit" "${commit_hash}" \
    "timestamp" "$(sed "s~[-T:Z]~~g" <<< "${commit_timestamp}")" \
    > "${installer_version_lock_file}"

  if [ "${jq}" != "jq" ]; then
    rm "${jq}"
  fi

  # Run the setup scripts

  info "Running the distro setup scripts, please wait..."
  echo "${install_dir}/software/distro/setup/setup.sh" "${HARDWARE}"
}

usage() {
  printf "%s\n" \
    "distro.sh [options]" \
    "Download and install the PlanktoScope software distro."

  printf "\n%s\n" "Options:"
  printf "  %s\n    %s\n    %s\n" \
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
    "-r, --repo" \
    "Set the GitHub repo used for downloading the PlanktoScope distro setup scripts" \
    "[default: ${DEFAULT_REPO}]" \
    \
    "--tag-prefix" \
    "Set the prefix for Git version tags in version queries of type \"tag\"" \
    "[default: ${DEFAULT_TAG_PREFIX}]" \
    \
    "-H, --home-dir" \
    "Set the directory where various components of the PlanktoScope distro will be installed" \
    "[default: ${DEFAULT_HOME_DIR}]" \
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

# Set default values for the command-line arguments
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
DEFAULT_REPO="PlanktoScope/PlanktoScope"
if [ -z "${REPO-}" ]; then
  REPO="${DEFAULT_REPO}"
fi
DEFAULT_TAG_PREFIX="software/"
if [ -z "${TAG_PREFIX-}" ]; then
  TAG_PREFIX="${DEFAULT_TAG_PREFIX}"
fi
DEFAULT_HOME_DIR="/home/pi"
if [ -z "${HOME_DIR-}" ]; then
  HOME_DIR="${DEFAULT_HOME_DIR}"
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
    -r | --repo)
      REPO="$2"
      shift 2
      ;;
    -r=* | --repo=*)
      REPO="${1#*=}"
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
    -H | --home-dir)
      HOME_DIR="$2"
      shift 2
      ;;
    -H=* | --home-dir=*)
      HOME_DIR="${1#*=}"
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
