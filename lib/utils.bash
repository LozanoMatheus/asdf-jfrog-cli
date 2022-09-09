#!/usr/bin/env bash

set -euo pipefail

REPO="jfrog/jfrog-cli"
TOOL_LONG_NAME="jfrog-cli"
TOOL_NAME="jfrog"
TOOL_SHORT_NAME="jf"
TOOL_TEST="${TOOL_SHORT_NAME} --version"

fail() {
  echo -e "asdf-$TOOL_NAME: $*"
  exit 1
}

CURL_OPTS=(-fSL)

if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  CURL_OPTS=("${CURL_OPTS[@]}" -H "Authorization: token ${GITHUB_API_TOKEN}")
fi

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -h -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
  local GH_RELEASES_PAGE='1'
  local GH_RELEASES
  GH_RELEASES="$(curl "${CURL_OPTS[@]}" "https://api.github.com/repos/${REPO}/releases?per_page=100&page=${GH_RELEASES_PAGE}" | awk '/tag_name/{ rc = 1; gsub(/,|"/,"") ; print $2 }; END { exit !rc }')"
  local RC="0"
  set +euo pipefail
  while [ ${RC} -eq 0 ]; do
    GH_RELEASES_PAGE=$((${GH_RELEASES_PAGE} + 1))
    GH_RELEASES="${GH_RELEASES}$(curl "${CURL_OPTS[@]}" "https://api.github.com/repos/${REPO}/releases?per_page=100&page=${GH_RELEASES_PAGE}" | awk '/tag_name/{ rc = 1; gsub(/,|"/,"") ; print $2 }; END { exit !rc }')"
    RC="${?}"
  done
  set -euo pipefail

  echo "${GH_RELEASES}"
}

list_all_versions() {
  list_github_tags | sed 's/^v//'
}

download_release() {
  local version filename url os_name
  version="$1"
  cli_major_version="${version//\.*}"
  os_name="$2"
  arch="$3"
  filename="$4"


  url="https://releases.jfrog.io/artifactory/jfrog-cli/v${cli_major_version}/${version}/jfrog-cli-${os_name}-${arch}/jfrog"

  echo "* Downloading $TOOL_NAME release $version..."
  curl "${CURL_OPTS[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="${3%/bin}/bin"

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  (
    mkdir -p "$install_path"
    cp -r "$ASDF_DOWNLOAD_PATH"/* "$install_path"

    local tool_cmd
    tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
    test -x "$install_path/$tool_cmd" || fail "Expected $install_path/$tool_cmd to be executable."

    echo "$TOOL_NAME $version installation was successful!"
  ) || (
    rm -rf "$install_path"
    fail "An error occurred while installing $TOOL_NAME $version."
  )
}

get_os_name() {
  local os_name
  case $(uname -s) in
  Linux*)
    os_name="linux"
    ;;
  Darwin*)
    os_name="macos"
    ;;
  *)
    log_failure_and_exit "Script only supports macOS and Linux"
    ;;
  esac
  echo "${os_name}"
}

get_arch() {
  local arch
  MACHINE_TYPE="$(uname -m)"
  case "${MACHINE_TYPE}" in
  i386 | i486 | i586 | i686 | i786 | x86)
    arch="386"
    ;;
  amd64 | x86_64 | x64)
    arch="amd64"
    ;;
  arm | armv7l)
    arch="arm"
    ;;
  aarch64)
    arch="arm64"
    ;;
  s390x)
    arch="s390x"
    ;;
  ppc64)
    arch="ppc64"
    ;;
  ppc64le)
    arch="ppc64le"
    ;;
  *)
    echo "Unknown machine type: $MACHINE_TYPE"
    exit -1
    ;;
  esac
  echo "${arch}"
}
