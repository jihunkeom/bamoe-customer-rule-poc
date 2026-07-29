#!/usr/bin/env sh

set -eu

OCP_OC_INSTALL_ROOT='/Users/jihunkeom/.local/openshift'

usage() {
  printf '%s\n' \
    'Usage: sh deploy/openshift/install-cluster-oc.sh' \
    'Downloads the oc client published by the currently logged-in cluster,' \
    'validates its minor version, then installs it under ~/.local/openshift.'
}

case "${1-}" in
  '')
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

for required_command in oc jq curl unzip awk uname mktemp install; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'ERROR: required command was not found: %s\n' \
      "$required_command" \
      >&2
    exit 1
  fi
done

server_version="$(
  oc get clusterversion version \
    -o jsonpath='{.status.desired.version}'
)"

server_minor="$(
  printf '%s\n' "$server_version" \
    | awk -F. '{print $1 "." $2}'
)"

case "$server_minor" in
  ''|*[!0-9.]*)
    printf 'ERROR: invalid OpenShift server version: %s\n' \
      "$server_version" \
      >&2
    exit 1
    ;;
esac

machine_architecture="$(uname -m)"

case "$machine_architecture" in
  arm64)
    download_label='Download oc for Mac for ARM 64'
    ;;
  x86_64)
    download_label='Download oc for Mac for x86_64'
    ;;
  *)
    printf 'ERROR: unsupported macOS architecture: %s\n' \
      "$machine_architecture" \
      >&2
    exit 1
    ;;
esac

download_url="$(
  oc get consoleclidownloads.console.openshift.io oc-cli-downloads \
    -o json \
    | jq -r \
      --arg label "$download_label" \
      '
        [
          .spec.links[]
          | select(.text == $label)
          | .href
        ][0] // empty
      '
)"

case "$download_url" in
  https://*)
    ;;
  *)
    printf 'ERROR: cluster oc download URL was not found\n' >&2
    printf 'Expected link label: %s\n' "$download_label" >&2
    exit 1
    ;;
esac

install_directory="${OCP_OC_INSTALL_ROOT}/${server_minor}"
download_directory="$(
  mktemp -d /private/tmp/bamoe-oc-install.XXXXXX
)"

cleanup_download_directory() {
  case "$download_directory" in
    /private/tmp/bamoe-oc-install.*)
      rm -rf -- "$download_directory"
      ;;
  esac
}

trap cleanup_download_directory EXIT HUP INT TERM

printf 'OpenShift server: %s\n' "$server_version"
printf 'Mac architecture: %s\n' "$machine_architecture"
printf 'Downloading approximately 100 MB from:\n%s\n' "$download_url"

curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --retry 3 \
  --output "$download_directory/oc.zip" \
  "$download_url"

unzip \
  -oq \
  "$download_directory/oc.zip" \
  -d "$download_directory/extracted"

if [ ! -f "$download_directory/extracted/oc" ]; then
  printf 'ERROR: downloaded archive does not contain oc\n' >&2
  exit 1
fi

chmod u+x "$download_directory/extracted/oc"

installed_client_version="$(
  "$download_directory/extracted/oc" version \
    --client \
    -o json \
    | jq -r '.clientVersion.gitVersion'
)"

installed_client_minor="$(
  printf '%s\n' "$installed_client_version" \
    | awk -F. '{print $1 "." $2}'
)"

if [ "$installed_client_minor" != "$server_minor" ]; then
  printf 'ERROR: installed client %s does not match server minor %s\n' \
    "$installed_client_version" \
    "$server_minor" \
    >&2
  exit 1
fi

mkdir -p "$install_directory"

install \
  -m 0755 \
  "$download_directory/extracted/oc" \
  "$install_directory/oc"

printf 'INSTALLED_OC=%s\n' "$install_directory/oc"
printf 'INSTALLED_OC_VERSION=%s\n' "$installed_client_version"
printf 'OC_VERSION_GATE=PASS (matching minor %s)\n' "$server_minor"
printf '%s\n' \
  'Next: source deploy/openshift/ocp-env.sh'
