# BAMOE PoC OpenShift 배포 시작 가이드

이 문서는 배포를 시작하기 전에 로컬 도구, OpenShift 로그인, 실제 cluster 정보가
맞는지 확인하는 진입 가이드다. 이 문서의 OpenShift 명령은 마지막 권한 확인까지
조회용이며 OpenShift resource를 만들지 않는다. 단, §4.1은 Mac의 사용자 전용
디렉터리에 cluster용 `oc`를 설치한다.

실제 설치는 모든 Gate가 통과한 뒤
[deploy/openshift/FULL-POC-GUIDE.md](deploy/openshift/FULL-POC-GUIDE.md)의
§1부터 시작한다. 전체 명령 묶음을 복사하지 말고 학습 카드의 코드 블록을 하나씩
실행해 결과를 관찰한다.

## 0. 이번 PoC에서 확정한 범위

- 제품 구성: 공개 Quay 9.5 image를 이용해 PAMOE Dev/Runtime 구성요소 직접 설치
- BAMOE version: `9.5.0-ibm-0005`
- 현재 실행 자산: Case 01~04
- Business Service: Spring Boot 4
- 외부 연동: `customer-rule-mock`
- 형상관리: private GitHub repository
- 이미지: GitHub Actions가 GHCR에 생성
- 최초 배포: commit SHA 이미지로 수동 bootstrap
- 이후 배포: `main` push → test/build → OCP 자동 재배포
- Canvas 시연: `Deploy` 버튼과 `bamoe-sandbox` 사용
- 접근: 외부 Route 사용, 인증 없는 합성 데이터 PoC
- License Service: 이번 IBM 내부 PoC의 설치 Gate에서 제외

현재 OCP `4.19`와 BAMOE 9.5 조합의 정식 운영 지원 여부는 확인되지 않았다.
PoC 기술 검증은 진행하지만 운영 지원을 보증하는 결과로 표현하지 않는다. 운영
전환 시 IBM Software Product Compatibility Reports에서 다시 확인한다.

## 1. 정확한 프로젝트 root 확인

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

현재 위치를 확인한다.

```bash
pwd
```

필수 파일을 이름별로 확인한다.

```bash
READY=true

for file in \
  pom.xml \
  deploy/openshift/ocp-env.sh \
  deploy/openshift/install-cluster-oc.sh \
  deploy/openshift/FULL-POC-GUIDE.md \
  deploy/openshift/products/dev/kustomization.yaml \
  deploy/openshift/products/runtime/kustomization.yaml \
  deploy/openshift/canvas-sandbox-rbac.yaml \
  .bamoe/dev-deployments/openshift/option.json \
  config/settings-bamoe-openshift.xml \
  .github/workflows/build-images.yml
do
  if [ -f "$file" ]; then
    printf '[OK] %s\n' "$file"
  else
    printf '[MISSING] %s\n' "$file"
    READY=false
  fi
done

if [ "$READY" = true ]; then
  printf 'PROJECT_FILES_GATE=PASS\n'
else
  printf 'PROJECT_FILES_GATE=FAIL\n'
fi
```

`pwd`의 기대 출력:

```text
/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

필수 파일은 모두 `[OK]`, 마지막 줄은 `PROJECT_FILES_GATE=PASS`여야 한다.

## 2. 로컬 command 준비

Case 00에서 준비한 Java 21, Maven, Docker, Git에 더해 배포 가이드는
`kustomize`, `ripgrep`, `jq`, GitHub CLI를 사용한다. 누락된 Homebrew 도구만
설치한다.

```bash
brew install kustomize ripgrep maven jq gh
```

GitHub Actions와 같은 `linux/amd64` image를 Mac에서 만들기 위해 Buildx plugin도
별도로 준비한다.

```bash
brew install docker-buildx
```

설치 확인:

```bash
oc version --client
kustomize version
docker --version
docker compose version
docker buildx version
gh --version
jq --version
git --version
rsync --version | head -1
rg --version
java --version
mvn --version
python3 --version
xmllint --version
openssl version
unzip -v | head -1
```

하나라도 `command not found`가 나오면 다음 단계로 진행하지 않는다.
`docker compose version`이 실패하면 먼저 Case 00에서 만든 전용 Colima VM과
context를 시작·선택하고 Docker CLI plugin 설정을 다시 확인한다. Docker Desktop은
이 PoC의 기본 runtime이 아니며, 사용자가 의도적으로 Colima 대신 선택한 경우에만
실행한다. `docker buildx version`만 실패하면 Homebrew가 출력한 caveat대로
Docker의 `cliPluginsExtraDirs`에 plugin 경로를 등록한다. Apple Silicon 기준
경로는 `/opt/homebrew/lib/docker/cli-plugins`, Intel Mac은
`/usr/local/lib/docker/cli-plugins`다. JSON을 덮어쓰지 말고 기존 최상위 object에
배열 property를 병합하는 방법은 [Case 00의 Docker CLI 설정](case-00-environment-setup.md#32-java-maven-vs-code-colima와-docker-cli)을 따른다.

Docker는
[`FULL-POC-GUIDE.md`](deploy/openshift/FULL-POC-GUIDE.md) §14의 로컬 Maven
Repository에 사용한다. `java --version`과 `mvn --version`에 표시되는 Java
runtime은 GitHub Actions와 같은 Java 21이어야 한다.

뒤의 `bamoe_check_env`는 위 도구 외에도 macOS 기본 `curl`, `awk`, `sed`,
`sort`, `mktemp`, `tar`, `rsync`가 실제 PATH에서 보이는지 한 번 더 검사한다.

GitHub 로그인:

```bash
gh auth login -h github.com -p https -w
gh auth status
```

GitHub token과 로그인 URL에 포함된 일회용 코드는 문서나 채팅에 공유하지 않는다.

## 3. OpenShift 로그인

1. OpenShift Web Console을 연다.
2. 우측 상단 사용자 메뉴에서 **Copy login command**를 선택한다.
3. 로그인 페이지가 새로 열리면 **Display Token**을 선택한다.
4. 표시된 `oc login ...` 명령을 자신의 terminal에서만 실행한다.

확인:

```bash
oc whoami
oc whoami --show-server
```

다음 정보는 공유하지 않는다.

- `oc login` 명령 전체
- `oc whoami --show-token` 출력
- kubeconfig
- GitHub PAT 또는 GHCR token

## 4. 실제 API, Route domain, version 확인

이 절은 긴 script를 한 번에 실행하지 않는다. 명령 하나를 실행하고 출력의 의미를
확인한 뒤 다음 명령으로 이동한다. 모두 조회 명령이며 cluster resource를 바꾸지
않는다.

### 현재 사용자와 API server

현재 로그인 사용자를 확인한다.

```bash
oc whoami
```

기대값은 이번 PoC에 사용할 계정이다. 이어서 현재 `oc`가 연결된 API server를
확인한다.

```bash
oc whoami --show-server
```

출력은 `https://...:6443` 형태여야 한다. 다른 cluster면 여기서 멈춘다.

### API TLS trust

직전 API 주소를 현재 terminal 변수로 저장한다.

```bash
export API_SERVER_CHECK="$(oc whoami --show-server)"
```

Mac의 일반 CA trust로 API에 접근할 수 있는지 확인한다.

```bash
if API_TLS_HTTP_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out '%{http_code}' \
    --connect-timeout 10 \
    "${API_SERVER_CHECK}/version"
)"
then
  printf 'API_TLS_GATE=PASS (ordinary TLS trust, HTTP %s)\n' \
    "$API_TLS_HTTP_STATUS"
else
  printf 'API_TLS_GATE=FAIL (TLS, DNS, or connection error)\n' >&2
fi
```

`401`이나 `403`도 인증서와 연결 검증은 성공한 것이다. `PASS`면 Mac의 일반 CA
trust로 API에 연결할 수 있다는 뜻이며, GitHub-hosted runner는 전체 가이드
§12.4에서 별도로 확인한다. `FAIL`이면 인증을 무시하지 말고 DNS·방화벽·cluster CA
전달 방식을 먼저 정한다.

### Route domain

외부 Route의 공통 suffix를 조회한다.

```bash
oc get ingresses.config.openshift.io cluster \
  -o jsonpath='{.spec.domain}'; printf '\n'
```

출력은 `apps....` 형태다. 이후 `OCP_ROUTE_DOMAIN`과 정확히 비교한다.

### OCP server와 `oc` client version

cluster version과 Available 상태를 조회한다.

```bash
oc get clusterversion version \
  -o custom-columns='NAME:.metadata.name,VERSION:.status.desired.version,AVAILABLE:.status.conditions[?(@.type=="Available")].status'
```

비교에 사용할 server version을 저장한다.

```bash
export OCP_SERVER_VERSION="$(
  oc get clusterversion version \
    -o jsonpath='{.status.desired.version}'
)"
```

```bash
export OCP_SERVER_MINOR="$(
  printf '%s\n' "$OCP_SERVER_VERSION" \
    | awk -F. '{print $1 "." $2}'
)"
```

현재 `oc` client version도 저장한다.

```bash
export OC_CLIENT_VERSION="$(
  oc version \
    --client \
    -o json \
    | jq -r '.clientVersion.gitVersion'
)"
```

```bash
export OC_CLIENT_MINOR="$(
  printf '%s\n' "$OC_CLIENT_VERSION" \
    | awk -F. '{print $1 "." $2}'
)"
```

두 실제값을 눈으로 확인한다.

```bash
printf 'OCP_SERVER_VERSION=%s\n' "$OCP_SERVER_VERSION"
printf 'OC_CLIENT_VERSION=%s\n' "$OC_CLIENT_VERSION"
```

minor version 일치 Gate를 실행한다.

```bash
if [ "$OCP_SERVER_MINOR" = "$OC_CLIENT_MINOR" ]; then
  printf 'OC_VERSION_GATE=PASS (matching minor %s)\n' "$OCP_SERVER_MINOR"
else
  printf 'OC_VERSION_GATE=FAIL (server %s, client %s)\n' \
    "$OCP_SERVER_MINOR" \
    "$OC_CLIENT_MINOR"
fi
```

`FAIL`이면 이 절의 마지막까지 조회는 계속할 수 있지만 실제 배포 전에는 §4.1의
방법으로 client를 맞춘다.

### Worker architecture

master를 제외하고 실제 worker만 조회한다.

```bash
oc get nodes \
  -l node-role.kubernetes.io/worker \
  -o custom-columns='NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,KUBELET:.status.nodeInfo.kubeletVersion'
```

worker가 한 개 이상 있고 모두 `amd64`인지 검사한다. `jq`의 `all([])`가 참이 되는
빈 목록 함정을 피하기 위해 worker 수까지 함께 검사한다.

```bash
if oc get nodes \
  -l node-role.kubernetes.io/worker \
  -o json \
  | jq -e '
      (.items | length) > 0
      and all(.items[]; .status.nodeInfo.architecture == "amd64")
    ' \
  >/dev/null
then
  printf 'WORKER_ARCH_GATE=PASS (all worker nodes amd64)\n'
else
  printf 'WORKER_ARCH_GATE=FAIL (no workers found or a worker is not amd64)\n'
fi
```

현재 workflow는 `linux/amd64`만 build하므로 `FAIL`이면 진행하지 않는다.

### Internal image registry

OpenShift 내부 image registry의 관리 상태를 기록한다.

```bash
oc get configs.imageregistry.operator.openshift.io cluster \
  -o custom-columns='NAME:.metadata.name,STATE:.spec.managementState'
```

이 절의 출력에는 token이 없으므로 그대로 공유해도 된다. 이 결과를 알려주면 다음을
확정할 수 있다.

- 실제 API server
- API server 인증서의 일반 TLS trust 여부
- 실제 Route domain
- OCP server와 local `oc` client version
- worker architecture
- 내부 Image Registry 사용 가능 여부

일부 조회가 `Forbidden`이면 그 오류 문구도 token을 포함하지 않는 범위에서 그대로
알려주면 된다. 값을 추측하지 말고 cluster 관리자에게 같은 조회를 요청한다.

### 4.1 현재 확인된 결과와 `oc 4.19` 설치

`2026-07-28`에 확인한 실제 결과:

| 항목 | 결과 | 판정 |
|---|---|---|
| API TLS | `PASS` | 통과 |
| Route domain | 환경파일과 일치 | 통과 |
| OCP server | `4.19.34` | 확인 |
| 기존 Homebrew `oc` | `4.22.5` | minor 불일치 |
| worker | 모두 `amd64` | 통과 |
| Internal Registry | `Removed` | 현재 구조에서는 허용 |

현재 배포는 PAMOE component는 Quay, 사용자 image는 GHCR에서 직접 pull하므로
`INTERNAL_REGISTRY=Removed`는 차단 사유가 아니다. 내부 Registry를 활성화하지
않고 [`FULL-POC-GUIDE.md`](deploy/openshift/FULL-POC-GUIDE.md) §3의 Quay/Red
Hat Registry pull과 §7의 private GHCR pull을 실제 Gate로 사용한다.

기존 Homebrew `oc`를 삭제하거나 덮어쓰지 않는다. 아래 script는 cluster의
`ConsoleCLIDownload`에서 현재 Mac ARM64용 URL을 찾아 약 100 MB ZIP을 받고,
`/Users/jihunkeom/.local/openshift/4.19/oc`에 설치한 뒤 server와 client minor가
같은지 검증한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test

sh deploy/openshift/install-cluster-oc.sh
```

현재 cluster가 실제로 제공한 ARM64 다운로드 주소:

```text
https://downloads-openshift-console.apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com/arm64/mac/oc.zip
```

script 완료 후 현재 terminal에 새 `oc`를 적용한다.

```bash
source deploy/openshift/ocp-env.sh

command -v oc
oc version --client
bamoe_show_env
bamoe_check_env
```

기대 핵심 출력:

```text
/Users/jihunkeom/.local/openshift/4.19/oc
OC_VERSION_GATE=PASS (matching minor 4.19)
OK: commands, Java 21, GitHub/OpenShift login, environment, and source directory are valid
```

cluster가 제공하는 client build 문자열은 정확히 `4.19.34`가 아닐 수 있지만
`4.19.x`이면 정상이다. 이후 새 terminal에서도 가장 먼저
`source deploy/openshift/ocp-env.sh`를 실행하면 Homebrew의 `4.22.5`보다 설치한
`4.19`가 우선된다. `bamoe_check_env`는 기록된 기대 minor만 보는 것이 아니라
매번 연결된 OpenShift server version도 다시 읽어 기대값·client·server 세 minor가
모두 같은지 검사하므로, cluster upgrade나 다른 `oc`가 PATH에 들어온 drift도
여기서 차단한다.

script가 download URL 조회 권한 문제로 실패할 때만 OpenShift Web Console의
**Help → Command Line Tools → Download oc for Mac for ARM 64**를 사용한다.
[Red Hat OpenShift 4.19 macOS CLI 설치 절차](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html-single/cli_tools/cli_tools)

설치 후 §4의 version Gate와 worker Gate 명령을 다시 실행해 다음 두 줄을
확인하고 §5로 넘어간다.

```text
OC_VERSION_GATE=PASS (matching minor 4.19)
WORKER_ARCH_GATE=PASS (all worker nodes amd64)
```

현재 환경파일에 기록된 마지막 값:

| 변수 | 기록된 값 |
|---|---|
| `OCP_API_SERVER` | `https://api.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com:6443` |
| `OCP_ROUTE_DOMAIN` | `apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com` |
| `DEV_NS` | `bamoe-devtools` |
| `RUNTIME_NS` | `bamoe-runtime` |
| `APP_NS` | `bamoe-poc` |
| `SANDBOX_NS` | `bamoe-sandbox` |

출력된 API 또는 Route domain이 다르면
`deploy/openshift/ocp-env.sh`를 먼저 수정하고 나서 진행한다.

## 5. 환경파일 불러오기와 비교

실제값과 환경파일이 같다는 것을 확인한 뒤 실행한다.

```bash
source deploy/openshift/ocp-env.sh
bamoe_show_env
bamoe_check_env
```

기대 출력의 마지막 줄:

```text
OK: commands, Java 21, GitHub/OpenShift login, environment, and source directory are valid
```

Route domain도 다시 비교한다.

```bash
export ACTUAL_ROUTE_DOMAIN="$(
  oc get ingresses.config.openshift.io cluster \
    -o jsonpath='{.spec.domain}'
)"

test "$ACTUAL_ROUTE_DOMAIN" = "$OCP_ROUTE_DOMAIN" \
  && printf 'OK: route domain matches\n'
```

출력이 없으면 두 값이 다르므로 설치하지 않는다.

## 6. Project 생성 권한 사전 확인

이번 PoC에서는 다음 네 Project를 새로 만드는 것이 승인되어 있다.

```text
bamoe-devtools
bamoe-runtime
bamoe-poc
bamoe-sandbox
```

Project 생성 권한과 namespace ownership label 적용 권한을 조회한다.

```bash
printf 'CREATE_PROJECT=%s\n' "$(
  oc auth can-i create projectrequests.project.openshift.io
)"

printf 'LABEL_NAMESPACE=%s\n' "$(
  oc auth can-i patch namespaces
)"
```

두 값이 모두 `yes`면 전체 가이드에서 직접 생성할 수 있다. 하나라도 `no`면
OpenShift 관리자에게 다음 세 가지를 함께 요청해야 한다.

1. 네 Project 생성
2. 각 Project에 `app.kubernetes.io/managed-by=bamoe-poc-guide` label 적용
3. 자신의 계정에 네 Project의 namespace-scoped `admin` 권한 부여

Project만 만들고 ownership label을 빠뜨리면 전체 가이드의 안전 검사에서
의도적으로 중단된다.

기존 Project 존재 여부도 조회한다.

```bash
for namespace in "$DEV_NS" "$RUNTIME_NS" "$APP_NS" "$SANDBOX_NS"; do
  if oc get namespace "$namespace" >/dev/null 2>&1; then
    printf 'EXISTS: %s\n' "$namespace"
  else
    printf 'MISSING: %s\n' "$namespace"
  fi
done
```

`EXISTS`가 나오더라도 바로 재사용하지 않는다. 전체 가이드는 이 PoC의 ownership
label이 있는 Project만 재사용하고, label 없는 기존 Project에서는 중단한다.

## 7. Registry 연결 확인

OCP API가 인터넷에서 열려 있다는 사실과 worker가 외부 Registry에서 image를
pull할 수 있다는 사실은 서로 다르다.

Mac에서 public endpoint가 보이는지 먼저 확인한다.

```bash
curl -sS -o /dev/null \
  -w 'quay.io HTTP %{http_code}\n' \
  https://quay.io/v2/

curl -sS -o /dev/null \
  -w 'ghcr.io HTTP %{http_code}\n' \
  https://ghcr.io/v2/
```

인증하지 않은 Registry의 정상적인 기대값은 대개 `401`이다. `401`은 연결 성공 후
인증이 필요하다는 뜻이다. DNS 오류, timeout, connection refused면 네트워크
문제다.

실제 OCP worker pull은 Project 생성이 필요한 변경 작업이므로
[`FULL-POC-GUIDE.md`](deploy/openshift/FULL-POC-GUIDE.md) §3에서 다음 두 단계로
검증한다.

1. Quay의 BAMOE image와 Red Hat UBI image pull
2. GitHub Actions build 후 private GHCR image pull

## 8. 진행 Gate

다음 항목이 모두 맞아야 실제 설치를 시작한다.

- [ ] `kustomize`, `oc`, `docker compose`, `docker buildx`, `gh`, `jq`, `git`, `rsync`, `rg`, Java 21, `mvn` 사용 가능
- [ ] `gh auth status` 성공
- [ ] `oc whoami` 성공
- [ ] 실제 API server와 `ocp-env.sh` 값 일치
- [ ] `API_TLS_GATE=PASS` 또는 GitHub용 CA PEM 준비
- [ ] 실제 Route domain과 `ocp-env.sh` 값 일치
- [ ] OCP version 기록
- [ ] `OC_VERSION_GATE=PASS`
- [ ] `WORKER_ARCH_GATE=PASS (all worker nodes amd64)`
- [ ] 네 Project가 없거나 이 PoC 전용임을 확인
- [ ] Project 직접 생성 시 namespace label 적용 권한도 확인
- [ ] 고객 원문 `BAMOE_POC_CASE.pdf`는 GitHub 제외 대상으로 확인

완료되면 아래 문서를 §1부터 순서대로 진행한다.

[명령어 학습형 BAMOE 9.5 전체 PoC 가이드](deploy/openshift/FULL-POC-GUIDE.md)
