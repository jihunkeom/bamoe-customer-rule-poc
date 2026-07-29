#!/usr/bin/env sh
#
# BAMOE PoC OpenShift 환경값
#
# 사용법:
#   source deploy/openshift/ocp-env.sh
#   bamoe_show_env
#   bamoe_check_env
#
# Secret이나 token은 이 파일에 넣지 않는다.

export OCP_API_SERVER='https://api.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com:6443'
export OCP_ROUTE_DOMAIN='apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com'
export OCP_EXPECTED_OC_MINOR='4.19'
export OCP_OC_BIN_DIR='/Users/jihunkeom/.local/openshift/4.19'

if [ -x "$OCP_OC_BIN_DIR/oc" ]; then
  case ":$PATH:" in
    *":$OCP_OC_BIN_DIR:"*)
      ;;
    *)
      PATH="$OCP_OC_BIN_DIR:$PATH"
      export PATH
      ;;
  esac
fi

export DEV_NS='bamoe-devtools'
export RUNTIME_NS='bamoe-runtime'
export APP_NS='bamoe-poc'
export SANDBOX_NS='bamoe-sandbox'

export GITHUB_OWNER='jihunkeom'
export GITHUB_REPO='bamoe-customer-rule-poc'
export SOURCE_DIR='/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test'
export GITHUB_WORK_DIR='/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/bamoe-customer-rule-poc'
export GITHUB_PARENT_REPO_ROOT='/Users/jihunkeom/Desktop/projects/2026/SKT'
export GITHUB_WORK_DIR_EXCLUDE_PATTERN='/skt_bamoe_party/bamoe-customer-rule-poc/'

bamoe_show_env() {
  printf '%-20s %s\n' 'OCP_API_SERVER' "$OCP_API_SERVER"
  printf '%-20s %s\n' 'OCP_ROUTE_DOMAIN' "$OCP_ROUTE_DOMAIN"
  printf '%-20s %s\n' 'OCP_EXPECTED_OC' "$OCP_EXPECTED_OC_MINOR"
  printf '%-20s %s\n' 'OCP_OC_BIN_DIR' "$OCP_OC_BIN_DIR"
  printf '%-20s %s\n' 'ACTIVE_OC' "$(command -v oc 2>/dev/null || true)"
  printf '%-20s %s\n' 'DEV_NS' "$DEV_NS"
  printf '%-20s %s\n' 'RUNTIME_NS' "$RUNTIME_NS"
  printf '%-20s %s\n' 'APP_NS' "$APP_NS"
  printf '%-20s %s\n' 'SANDBOX_NS' "$SANDBOX_NS"
  printf '%-20s %s\n' 'GITHUB_OWNER' "$GITHUB_OWNER"
  printf '%-20s %s\n' 'GITHUB_REPO' "$GITHUB_REPO"
  printf '%-20s %s\n' 'SOURCE_DIR' "$SOURCE_DIR"
  printf '%-20s %s\n' 'GITHUB_WORK_DIR' "$GITHUB_WORK_DIR"
  printf '%-20s %s\n' 'GITHUB_PARENT_ROOT' "$GITHUB_PARENT_REPO_ROOT"
  printf '%-20s %s\n' 'PARENT_EXCLUDE' "$GITHUB_WORK_DIR_EXCLUDE_PATTERN"
}

bamoe_check_env() {
  : "${OCP_API_SERVER:?OCP_API_SERVER is not set}"
  : "${OCP_ROUTE_DOMAIN:?OCP_ROUTE_DOMAIN is not set}"
  : "${OCP_EXPECTED_OC_MINOR:?OCP_EXPECTED_OC_MINOR is not set}"
  : "${OCP_OC_BIN_DIR:?OCP_OC_BIN_DIR is not set}"
  : "${DEV_NS:?DEV_NS is not set}"
  : "${RUNTIME_NS:?RUNTIME_NS is not set}"
  : "${APP_NS:?APP_NS is not set}"
  : "${SANDBOX_NS:?SANDBOX_NS is not set}"
  : "${GITHUB_OWNER:?GITHUB_OWNER is not set}"
  : "${GITHUB_REPO:?GITHUB_REPO is not set}"
  : "${SOURCE_DIR:?SOURCE_DIR is not set}"
  : "${GITHUB_WORK_DIR:?GITHUB_WORK_DIR is not set}"
  : "${GITHUB_PARENT_REPO_ROOT:?GITHUB_PARENT_REPO_ROOT is not set}"
  : "${GITHUB_WORK_DIR_EXCLUDE_PATTERN:?GITHUB_WORK_DIR_EXCLUDE_PATTERN is not set}"

  for _bamoe_required_command in \
    oc kustomize docker gh jq git rsync rg java mvn curl awk sed sort \
    mktemp openssl tar unzip xmllint python3
  do
    if ! command -v "$_bamoe_required_command" >/dev/null 2>&1; then
      printf 'ERROR: required command was not found: %s\n' \
        "$_bamoe_required_command" \
        >&2
      return 1
    fi
  done

  if ! docker compose version >/dev/null 2>&1; then
    printf 'ERROR: docker compose plugin is not available\n' >&2
    return 1
  fi

  if ! docker buildx version >/dev/null 2>&1; then
    printf 'ERROR: docker buildx plugin is not available\n' >&2
    return 1
  fi

  _bamoe_java_version="$(
    java -version 2>&1 \
      | awk -F '"' '/version/ { print $2; exit }'
  )"

  _bamoe_java_major="$(
    printf '%s\n' "$_bamoe_java_version" \
      | awk -F. '{ if ($1 == "1") print $2; else print $1 }'
  )"

  if [ "$_bamoe_java_major" != '21' ]; then
    printf 'ERROR: Java 21 is required; actual version: %s\n' \
      "$_bamoe_java_version" \
      >&2
    return 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    printf 'ERROR: GitHub CLI is not logged in; run gh auth login\n' >&2
    return 1
  fi

  _bamoe_oc_client_version="$(
    oc version \
      --client \
      -o json \
      | jq -r '.clientVersion.gitVersion'
  )"

  _bamoe_oc_client_minor="$(
    printf '%s\n' "$_bamoe_oc_client_version" \
      | awk -F. '{print $1 "." $2}'
  )"

  if [ "$_bamoe_oc_client_minor" != "$OCP_EXPECTED_OC_MINOR" ]; then
    printf 'ERROR: oc client minor does not match the cluster\n' >&2
    printf 'expected: %s.x\n' "$OCP_EXPECTED_OC_MINOR" >&2
    printf 'actual:   %s\n' "$_bamoe_oc_client_version" >&2
    printf '%s\n' \
      'run: sh deploy/openshift/install-cluster-oc.sh' \
      >&2
    return 1
  fi

  if [ "$(oc whoami --show-server 2>/dev/null)" != "$OCP_API_SERVER" ]; then
    printf 'ERROR: oc is connected to a different cluster or is logged out\n' >&2
    printf 'expected: %s\n' "$OCP_API_SERVER" >&2
    printf 'actual:   %s\n' "$(oc whoami --show-server 2>/dev/null)" >&2
    return 1
  fi

  _bamoe_oc_server_version="$(
    oc version \
      -o json \
      | jq -r '.openshiftVersion // empty'
  )"

  _bamoe_oc_server_minor="$(
    printf '%s\n' "$_bamoe_oc_server_version" \
      | awk -F. '{print $1 "." $2}'
  )"

  if [ -z "$_bamoe_oc_server_version" ] \
    || [ "$_bamoe_oc_server_minor" != "$OCP_EXPECTED_OC_MINOR" ] \
    || [ "$_bamoe_oc_server_minor" != "$_bamoe_oc_client_minor" ]; then
    printf 'ERROR: live OpenShift server, expected, and oc client minors differ\n' >&2
    printf 'expected: %s.x\n' "$OCP_EXPECTED_OC_MINOR" >&2
    printf 'server:   %s\n' "${_bamoe_oc_server_version:-unknown}" >&2
    printf 'client:   %s\n' "$_bamoe_oc_client_version" >&2
    return 1
  fi

  if [ ! -f "$SOURCE_DIR/pom.xml" ]; then
    printf 'ERROR: project pom.xml was not found under SOURCE_DIR\n' >&2
    return 1
  fi

  if [ "$SOURCE_DIR" = "$GITHUB_WORK_DIR" ]; then
    printf 'ERROR: SOURCE_DIR and GITHUB_WORK_DIR must be different\n' >&2
    return 1
  fi

  if [ "$(
    git -C "$GITHUB_PARENT_REPO_ROOT" \
      rev-parse --show-toplevel 2>/dev/null
  )" != "$GITHUB_PARENT_REPO_ROOT" ]; then
    printf 'ERROR: GITHUB_PARENT_REPO_ROOT is not the expected Git root\n' >&2
    return 1
  fi

  if ! git -C "$GITHUB_PARENT_REPO_ROOT" \
    check-ignore -q --no-index "${GITHUB_WORK_DIR%/}/" 2>/dev/null
  then
    printf '%s\n' \
      'INFO: parent local exclude is not registered yet; this is expected before §6.1 setup. Do not create GITHUB_WORK_DIR until §6.1 is complete.'
  fi

  printf '%s\n' \
    'OK: commands, Java 21, GitHub/OpenShift login, environment, and source directory are valid'
}
