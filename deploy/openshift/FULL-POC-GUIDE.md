# SKT BAMOE 9.5 OpenShift 단계별 PoC 학습 가이드

이 문서는 명령 묶음을 복사해 한 번에 배포하는 자동화 실행서가 아니다. OpenShift를
처음 사용하는 사람이 **명령을 하나씩 실행하고, 그 명령이 바꾼 상태를 직접
관찰하면서** 현재 프로젝트를 PoC 환경에 올리는 실습 교재다.

최종적으로 구성할 구조는 다음과 같다.

```text
로컬 UI 개발
  → private GitHub repository
  → GitHub Actions test / image build
  → private GHCR
  → OpenShift의 Business Service + Mock API 자동 재배포

BAMOE Canvas
  → GitHub의 DMN/BPMN 편집
  → bamoe-sandbox에 Deploy 버튼으로 임시 Dev Deployment

PAMOE Runtime Environment
  → Management Console에 Business Service 연결 항목 사전 구성
  → MCP Server Tech Preview에서 Business Service OpenAPI 해석
```

## 이 문서를 사용하는 방법

각 실습 단계는 다음 순서를 따른다.

1. 명령 위의 **목적**과 **학습 포인트**를 먼저 읽는다.
2. 코드 블록 하나만 복사해 실행한다.
3. 설명된 정상 출력 또는 OpenShift 상태를 직접 확인한다.
4. 변경 명령 뒤에 있는 조회 명령으로 실제 생성된 리소스를 관찰한다.
5. 섹션 마지막 **Gate**를 모두 통과한 뒤 다음 섹션으로 이동한다.

대부분의 코드 블록은 `\`로 화면 줄만 나눈 **하나의 명령**이며, 한 블록씩
실행하고 결과를 읽은 뒤 다음 블록으로 간다. 단, ownership·identity·rollback처럼
검사와 변경을 분리하면 TOCTOU 위험이 생기는 곳은 여러 조회와 `if`를 하나로 묶은
**Gate script**다. 본문에서 “같은 블록”, “한 Gate”, “함수”라고 부르는 블록이
이에 해당한다.

Gate script는 앞 문단에서 각 변수와 성공 조건을 먼저 설명하며, 중간 줄만 골라
실행하거나 나눠 붙여 넣지 않는다. 실패하면 출력된 `REFUSE`/`FAIL` 원인을
해결하고 Gate 전체를 다시 실행한다. 서로 다른 코드 블록을 한꺼번에 선택해
실행하지 않는다. `export`로 만든 변수는 현재 terminal에서만 유지되므로 한 섹션을
진행하는 동안에는 같은 terminal을 사용한다.

명령의 성격은 본문에서 다음처럼 표시한다. `변경`과 `정리`는 반드시 OCP만
뜻하지 않으며, 바로 앞 문장에서 로컬·GitHub·OpenShift 중 어느 상태를 바꾸는지
확인한다.

| 표시 | 의미 | 바뀔 수 있는 범위 |
|---|---|---|
| **조회 / 관찰** | 현재 사용자, 리소스, 권한, 로그 등을 확인 | 없음 |
| **조회 준비 / 로컬 준비** | 변수, 임시 파일·디렉터리, Git 작업 사본 준비 | 현재 shell 또는 로컬 파일 |
| **변경** | 파일, GitHub 설정, OCP 리소스 등을 생성·수정 | 명령별로 본문에 명시 |
| **대기** | 비동기 배포가 특정 상태가 될 때까지 관찰 | 없음 |
| **검증** | 예상 결과를 다시 조회하거나 호출 | 원칙적으로 없음 |
| **실패 진단** | 실패한 리소스의 상세 상태·Event·로그 조회 | 없음 |
| **정리** | 정확히 지정한 임시 자산·권한·노출 제거 | 로컬, GitHub 또는 OCP |

`oc apply`, `oc patch`, `--list` 없는 `oc set env`, `oc delete`,
`oc rollout undo`는 실제 상태를 변경한다. 이 명령은 바로 위에서 대상 namespace와
리소스 이름을 확인한 뒤에만 실행한다. `oc set env --list`는 저장된 환경변수를
읽기만 하며, `kustomize build`는 선언 파일을 하나의 YAML로 조립할 뿐 cluster를
변경하지 않는다.

명령 자체가 궁금할 때에는 실행 전에 도움말을 볼 수 있다.

```bash
oc help
```

`oc`가 다루는 Kubernetes/OpenShift 리소스의 필드 구조는 `oc explain`으로
확인할 수 있다.

```bash
oc explain deployment
```

예를 들어 Route가 어떤 Service를 가리키는지는 다음 명령으로 필드 설명을 읽는다.

```bash
oc explain route.spec.to
```

`oc` 명령은 대부분 다음 형태로 읽으면 된다.

```text
oc <동작> <리소스 종류>/<리소스 이름> -n <Project> <출력 옵션>
```

| 부분 | 예 | 의미 |
|---|---|---|
| 동작 | `get`, `describe`, `apply`, `delete` | 무엇을 할지 |
| 리소스 종류 | `pod`, `deployment`, `service`, `route` | 어떤 종류를 다룰지 |
| 리소스 이름 | `customer-rule-poc` | 정확히 어느 리소스인지 |
| `-n` | `-n "$APP_NS"` | 어느 Project에서 실행할지 |
| `-o` | `-o wide`, `-o yaml`, `-o jsonpath=...` | 결과를 어떤 형태로 볼지 |

자주 사용하는 동작의 차이도 먼저 기억해 둔다.

| 명령 | 용도 |
|---|---|
| `oc get` | 목록과 현재 상태를 간단히 조회 |
| `oc describe` | 이벤트와 상세 상태를 사람이 읽기 좋게 조회 |
| `oc logs` | 컨테이너 애플리케이션 로그 조회 |
| `oc auth can-i` | 현재 계정이나 ServiceAccount의 권한 확인 |
| `oc apply --dry-run=server` | 저장하지 않고 API server validation만 수행 |
| `oc apply` | manifest의 원하는 상태를 cluster에 반영 |
| `oc wait` | 특정 조건이 될 때까지 대기 |
| `oc rollout status` | Deployment 교체 진행 상태 관찰 |
| `oc port-forward` | 외부 Route 없이 로컬 포트와 Service 연결 |

shell 기호도 다음처럼 읽는다.

| 기호 | 의미 |
|---|---|
| 줄 끝의 `\` | 다음 화면 줄까지 같은 명령이 계속됨 |
| `\|` | 왼쪽 프로그램의 출력을 오른쪽 프로그램의 입력으로 전달 |
| `>` | 화면에 출력할 내용을 지정한 파일에 저장 |
| `$(...)` | 괄호 안 조회 결과를 현재 변수 값으로 사용 |
| `$NAME` 또는 `${NAME}` | 앞에서 `export`한 변수의 값을 사용 |

특히 token을 다루는 pipeline은 왼쪽에서 만든 값을 화면이나 파일에 두지 않고
오른쪽 명령으로 바로 전달하기 위해 사용한다. 그런 pipeline은 한 단계로 실행하되,
본문에서 설명한 왼쪽·오른쪽 역할을 모두 이해한 뒤 실행한다.

명령은 프로젝트 root를 기준으로 실행하며, token이나 Secret 값은 출력하거나
문서·채팅에 공유하지 않는다.

## 전체 학습 순서

| 단계 | 배우는 내용 | 완료 기준 |
|---|---|---|
| 1 | 로그인, API, Route domain, 노드와 `oc` | cluster 사전 점검 통과 |
| 2 | Project와 namespace 권한 | 네 Project 및 ownership 확인 |
| 3 | Pod scheduling과 image pull | 외부 registry pull 성공 |
| 4~5 | 제품 YAML, Kustomize, dry-run, apply | PAMOE Dev Environment 정상 |
| 6~8 | Git, Actions, GHCR, Kustomize | 앱과 Mock 최초 배포 |
| 9~10 | Service, port-forward, Route | 내부·외부 E2E 검증 |
| 11 | Runtime, Service DNS, 환경변수, CORS | Management Console/MCP 연결 |
| 12 | ServiceAccount, RBAC, CI/CD | digest 기반 자동 배포 |
| 13 | Canvas sandbox 배포 | 권한이 격리된 Dev Deployment |
| 14~18 | 반복 개발, 진단, rollback, 정리 | 운영 흐름과 안전한 종료 이해 |

한 번에 전부 진행할 필요는 없다. 다음 단위로 나누면 각 세션이 하나의 학습
주제로 끝난다.

| 추천 세션 | 범위 | 여기서 배우는 핵심 | 안전한 중단 상태 |
|---|---|---|---|
| A | §1~§3 | cluster, Project, Pod, image pull | 임시 pull-test Pod 삭제 완료 |
| B | §4~§5 | 직접 배포 YAML, render, dry-run, apply | Dev Deployment Ready; 장기 중단이면 §17.5 Route 제거 |
| C | §6~§7 | GitHub Actions, GHCR, image SHA | pull-test Pod 삭제 완료 |
| D | §8~§10 | Kustomize, Deployment, Service, Route | 검증 완료; 장기 중단이면 §17.3 Route 제거 |
| E | §11 | Runtime, Service DNS, 환경변수, CORS | MCP 외부 Route 제거 완료 |
| F | §12 | ServiceAccount, RBAC, CI/CD | digest 자동 배포 검증 완료 |
| G | §13 | Canvas와 sandbox 권한 | 임시 Dev Deployment 삭제 완료 |
| H | §14~§18 | 반복 개발, 진단, rollback, 정리 | 목적에 맞게 선택 실행 |

장기 중단 때문에 Route를 제거했다면 재개할 때 상태를 추측하지 않는다. 세션 B는
§5.1부터 제품 manifest와 실제 Deployment를 다시 확인하고 §5.3의 `oc apply`로
Route를 복원한다. 세션 D는 §10.1부터 Service와 manifest를 다시 확인해 Route를
적용한다.

다음 항목은 모든 명령을 순서대로 실행하는 구간이 아니라 **조건부 분기**다.

- §6.2의 “처음 만드는 경우”와 §6.3의 “기존 repository” 중 하나만 선택한다.
- `실패 진단` 명령은 바로 앞 단계가 실패했을 때만 실행한다.
- §12.5의 private CA 분기는 일반 TLS 검증이 실패한 cluster에서만 실행한다.
- §16 rollback은 실제 복구가 필요할 때만 실행한다.
- §17 정리는 PoC 시연을 종료할 때만 실행한다.

세션을 끝내기 전에 해당 장의 Gate를 기록한다. 새 terminal에서 다시 시작할
때에는 먼저 프로젝트 root로 이동하고 환경을 다시 불러온다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

```bash
source deploy/openshift/ocp-env.sh
```

그 뒤 해당 장에서 따로 만든 `BOOTSTRAP_SHA`, Route host 같은 임시 변수가
필요한지 확인한다. 제품 manifest는 `deploy/openshift/products/` 아래에 버전
관리되므로 새 terminal에서도 다시 다운로드하거나 임시 경로를 복원하지 않는다.

## 0. 확정 범위와 중요한 구분

### 0.1 이번 PoC의 확정값

| 항목 | 값 |
|---|---|
| Offering | PAMOE |
| BAMOE version | `9.5.0-ibm-0005` |
| 현재 Business Service | Spring Boot 기반 Case 01~04 |
| 이후 확장 | Case 05~06 자산을 같은 repository와 pipeline에 추가 |
| 개발 도구 | Canvas, Extended Services, CORS Proxy, Maven Repository |
| Runtime 도구 | Management Console, MCP Server |
| 사용자 이미지 | GitHub Actions가 GHCR에 생성 |
| Mock API | OCP 내부 `customer-rule-mock` Service |
| 기본 배포 | 로컬 개발 → `main` push → Actions 자동 재배포 |
| Canvas 배포 | `bamoe-sandbox`에서만 사용하는 임시 시연용 배포 |
| 외부 접근 | Business Service와 제품 UI Route |
| 데이터 | 합성 데이터만 사용 |
| 고객 원문 PDF | GitHub에서 제외 |
| License Service | 이번 내부 PoC의 진행 Gate에서 제외 |

PAMOE Dev/Runtime 제품 컴포넌트를 모두 직접 배포한다는 의미와, 모든 선택 기능을
현재 Business Service에 활성화한다는 의미는 다르다. 현재 앱에는 persistence,
User Task, timer/job, Data Index 연동이 없다. 따라서 Management Console의
지속성 프로세스 관리 기능 전체를 보여주는 앱은 아니며, 이 범위는 §15에 따로
정리한다.

### 0.2 본선 배포와 Canvas Deploy의 차이

| 구분 | 본선 | Canvas 시연 |
|---|---|---|
| 대상 | `bamoe-poc` | `bamoe-sandbox` |
| 실행 이미지 | GHCR의 현재 Spring Boot 앱 이미지 | Canvas Dev Deployment JDK 21 base |
| 입력 자산 | Java + DMN + BPMN + 설정 전체 | 같은 프로젝트 전체를 임시 upload |
| 배포 시작 | `main` push | Canvas의 **Deploy** 버튼 |
| 목적 | 반복 가능한 통합 배포 | UI 수정본의 빠른 통합 검증 |
| Mock 접근 | 같은 Project의 Service | sandbox의 `ExternalName` alias |

이 repository에는 `.bamoe/dev-deployments/openshift/` 사용자 정의 옵션이 있다.
따라서 기본 `Quarkus Blank App`과 `Custom Image` 선택지는 UI에서 숨겨지고,
**OpenShift Spring Boot PoC** 옵션만 보이는 것이 정상이다. 이 경로는 완성된
GHCR image를 재사용하지 않고 Canvas가 현재 작업공간 전체를 임시 Pod에 올려
Maven으로 Spring Boot를 시작한다. 본선 배포를 대체하는 경로가 아니라 UI 수정본을
빠르게 확인하는 개발용 경로다.

### 0.3 지원성 주의

대상 OCP version과 BAMOE 9.5의 정식 지원 조합은 아직 SPCR에서 확인하지 않았다.
PoC 검증은 진행할 수 있지만, 결과를 운영 지원 보증으로 표현하지 않는다. 운영
전환 전에는
[IBM BAMOE Kubernetes 지원 정책](https://www.ibm.com/support/pages/ibm-business-automation-manager-open-editions-support-statement-kubernetes-platforms-0)과
Software Product Compatibility Reports를 다시 확인한다.

### 0.4 이 PoC에서 명시적으로 수용한 보안 한계

현재 manifest는 인터넷에서 접근 가능한 Route에 edge TLS를 적용하지만 별도
사용자 인증 계층은 두지 않는다. CORS는 브라우저 호출 제어이지 인증이 아니며,
CORS Proxy의 cluster Route wildcard 허용은 동적으로 생성되는 Canvas sandbox
Route를 지원하기 위한 PoC 설정이다. 또한 namespace별 default-deny
`NetworkPolicy`는 아직 없다.

따라서 다음 조건을 모두 지키는 **감독형·단기·합성 데이터 시연**에만 사용한다.

- 고객 개인정보, 실서비스 자격증명, 운영 DB를 넣지 않는다.
- Canvas와 Management Console은 필요한 시연 시간에만 공개한다.
- MCP와 Maven Repository에는 외부 Route를 만들지 않는다.
- Canvas ServiceAccount는 Secret이 없는 전용 sandbox namespace에서만 사용한다.
- 시연이 끝나면 §17.5의 소유권·Service target Gate를 거쳐 고정 Route를 제거한다.

운영 또는 장기 공유로 전환할 때에는 배포 전에 지원되는 OAuth/OIDC proxy 또는
ingress IP allowlist, 정확한 CORS target allowlist, namespace별 default-deny
NetworkPolicy와 필요한 통신만 허용하는 policy를 설계한다. 이 작업이 완료되지
않으면 현재 Route를 장기 존치하지 않는다.

## 1. 작업 시작과 실제 cluster 확인

먼저 [OpenShift 배포 시작 가이드](../../OPENSHIFT-DEPLOYMENT-GUIDE.md)의 모든
Gate를 통과한다. 이 절에서는 저장된 설정과 실제 cluster가 여전히 같은지만 한
항목씩 확인한다.

### 1.1 작업 디렉터리와 환경 불러오기

성격: 조회 준비. 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

정상 관찰값: terminal prompt의 현재 경로가 `.../prelim/test`다. 실패하면 경로가
실제로 존재하는지 Finder 또는 `pwd`로 확인한다.

성격: 조회 준비. 이 terminal에서 사용할 OCP 변수와 함수만 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

정상 관찰값: 오류 없이 prompt로 돌아온다. `No such file`이면 현재 경로가
`test/`인지 먼저 확인한다.

성격: 조회. token 없이 현재 설정값을 화면에 표시한다.

```bash
bamoe_show_env
```

정상 관찰값: `OCP_API_SERVER`, `OCP_ROUTE_DOMAIN`, 네 Project 이름이 출력된다.
`GITHUB_WORK_DIR`는
`/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/bamoe-customer-rule-poc`
이어야 한다. 이 위치는 상위 `/Users/jihunkeom/Desktop/projects/2026/SKT`
repository 안이지만 `SOURCE_DIR` 밖의 sibling 작업 폴더다. §6.1에서 상위
repository의 로컬 exclude를 먼저 설정한 뒤 별도 Git repository로 초기화한다.
Secret이나 token이 출력되면 다음 단계로 가지 말고 `ocp-env.sh`를 점검한다.

성격: 검증. 필수 명령과 환경변수가 준비됐는지 확인한다.

```bash
bamoe_check_env
```

정상 관찰값: 모든 사전 조건이 통과한다. 실패하면 출력된 첫 누락 항목을
[시작 가이드](../../OPENSHIFT-DEPLOYMENT-GUIDE.md)에서 해결한 뒤 다시 실행한다.

### 1.2 로그인 대상 확인

성격: 조회. 현재 OpenShift 사용자만 확인한다.

```bash
oc whoami
```

정상 관찰값: 자신의 OCP 사용자 ID가 출력된다. `Unauthorized`이면 새 token으로
다시 로그인한다.

성격: 조회. 현재 로그인한 API server를 확인한다.

```bash
oc whoami --show-server
```

정상 관찰값: 출력값이 `bamoe_show_env`에서 본 `OCP_API_SERVER`와 정확히 같다.
다르면 다른 cluster에 로그인한 것이므로 여기서 중단한다.

성격: 검증. Mac의 일반 trust store로 API server의 TLS 인증서를 검증한다.

```bash
curl \
  --silent \
  --show-error \
  --output /dev/null \
  --write-out 'HTTP_STATUS=%{http_code}\n' \
  --connect-timeout 10 \
  "${OCP_API_SERVER}/version"
```

정상 관찰값: 인증서 오류 없이 HTTP 상태가 출력된다. `401` 또는 `403`도 TLS
연결 자체는 성공한 것이다. 인증서 오류가 나오면 §12에서 GitHub Actions에 등록할
cluster CA PEM을 플랫폼 관리자에게 요청한다. `--insecure` 또는 `-k`는 사용하지
않는다.

### 1.3 Route domain과 버전 확인

성격: 조회. cluster의 실제 Route domain을 확인한다.

```bash
oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}{"\n"}'
```

정상 관찰값: 출력값이 `OCP_ROUTE_DOMAIN`과 같다. `Forbidden`이면 이 명령과
오류를 플랫폼 관리자에게 전달하고 값을 확인받는다.

성격: 조회. OCP server 버전과 Available 상태를 확인한다.

```bash
oc get clusterversion version \
  -o custom-columns='VERSION:.status.desired.version,AVAILABLE:.status.conditions[?(@.type=="Available")].status'
```

정상 관찰값: `AVAILABLE`이 `True`다. `VERSION`의 앞 두 숫자, 예를 들어
`4.19`를 기록한다. `Forbidden`이면 플랫폼 관리자에게 같은 출력을 요청한다.

성격: 조회. 로컬 `oc` client 버전을 확인한다.

```bash
oc version --client
```

정상 관찰값: client 버전의 앞 두 숫자가 직전 OCP server minor와 같다. 다르면
다음 교정 단계를 실행하고, 같으면 1.4로 이동한다.

성격: 변경. server minor와 다른 `oc` client를 cluster 버전에 맞게 설치한다.
버전이 이미 같으면 실행하지 않는다.

```bash
sh deploy/openshift/install-cluster-oc.sh
```

정상 관찰값: 설치가 오류 없이 끝난다. script는 임시 위치의 `oc`를 먼저 실행해
cluster minor와 일치하는지 검증한 뒤 최종 경로에 설치한다. 다운로드 또는 archive
검증 오류가 나면 네트워크와 시작 가이드 §4.1을 확인한다.

성격: 조회 준비. 새로 설치된 `oc` 경로가 반영되도록 환경을 다시 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

정상 관찰값: 오류 없이 prompt로 돌아온다.

성격: 검증. 실제 사용될 `oc` 실행 파일을 확인한다.

```bash
command -v oc
```

정상 관찰값: OCP 4.19 cluster라면
`/Users/jihunkeom/.local/openshift/4.19/oc`가 출력된다. 다른 경로면 새 terminal을
열어 환경을 다시 불러온다.

성격: 검증. 교정 후 client 버전을 다시 확인한다.

```bash
oc version --client
```

정상 관찰값: server와 client minor가 같다. 다르면 다음 절로 넘어가지 않는다.

### 1.4 Worker와 image registry 확인

성격: 조회. 모든 worker의 architecture와 kubelet 버전을 확인한다.

```bash
oc get nodes \
  -l node-role.kubernetes.io/worker \
  -o custom-columns='NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,KUBELET:.status.nodeInfo.kubeletVersion'
```

정상 관찰값: 모든 worker의 `ARCH`가 `amd64`다. 하나라도 다르면 현재 GitHub
Actions가 `linux/amd64`만 build하므로 workflow를 바꾸기 전에는 진행하지 않는다.
`Forbidden`이면 플랫폼 관리자에게 같은 출력을 요청한다.

성격: 검증. worker가 한 개 이상 있고 모두 `amd64`인지 기계적으로 확인한다.

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

정상 관찰값: `WORKER_ARCH_GATE=PASS`. `jq`에서는 빈 배열의 `all(...)`도 참이 될
수 있으므로 worker 수를 별도로 확인한다.

성격: 조회. OpenShift internal image registry의 관리 상태를 기록한다.

```bash
oc get configs.imageregistry.operator.openshift.io cluster \
  -o custom-columns='NAME:.metadata.name,STATE:.spec.managementState'
```

정상 관찰값: 실제 `STATE`가 출력된다. 이 PoC의 사용자 이미지는 GHCR을 사용하므로
internal registry가 `Removed`여도 즉시 실패 조건은 아니지만, cluster 상태 기록에
남긴다.

이 절의 출력은 token을 포함하지 않으므로 검토 목적으로 공유할 수 있다. 다음 값은
공유하지 않는다.

- `oc login` 명령 전체
- `oc whoami --show-token` 출력
- kubeconfig
- GitHub PAT
- OpenShift ServiceAccount token

**Gate**

- 현재 사용자와 API server가 의도한 cluster의 값이다.
- API TLS가 일반 trust로 성공했거나 cluster CA PEM을 별도로 확보할 계획이 있다.
- 실제 Route domain과 `OCP_ROUTE_DOMAIN`이 같다.
- OCP server와 로컬 `oc` client의 minor가 같다.
- 모든 worker가 `amd64`다.
- OCP version과 internal registry 상태를 기록했다.

## 2. 네 개 Project를 안전하게 만들기

OpenShift의 **Project**는 사용자와 권한 관리 경험을 더한 Kubernetes
**namespace**다. 그래서 생성할 때에는 `oc new-project`를 사용하지만 조회와
label 명령에서는 `namespace`라는 리소스 이름이 보인다. `oc new-project`는 생성
후 현재 Project도 바꾸므로, 이 가이드의 이후 명령은 현재 선택값에 의존하지 않고
항상 `-n "$..._NS"`로 대상을 명시한다.

사용할 Project:

| 변수 | 기본 이름 | 역할 |
|---|---|---|
| `DEV_NS` | `bamoe-devtools` | Canvas 등 Dev Environment |
| `RUNTIME_NS` | `bamoe-runtime` | Management Console, MCP Server |
| `APP_NS` | `bamoe-poc` | 앱과 Mock API |
| `SANDBOX_NS` | `bamoe-sandbox` | Canvas Dev Deployment |

### 2.1 생성과 label 권한 확인

성격: 조회. 현재 사용자가 Project를 생성할 수 있는지 확인한다.

```bash
oc auth can-i create projectrequests.project.openshift.io
```

정상 관찰값: 직접 만들 경우 `yes`다. `no`면 생성 명령을 실행하지 말고 아래의
관리자 요청 항목을 전달한다.

성격: 조회. namespace에 ownership label을 적용할 수 있는지 확인한다.

```bash
oc auth can-i patch namespaces
```

정상 관찰값: 직접 label을 적용할 경우 `yes`다. `no`면 임의로 우회하지 않는다.

두 결과 중 하나라도 `no`이면 플랫폼 관리자에게 다음 세 가지를 한 번에 요청한다.

1. `bamoe-devtools`, `bamoe-runtime`, `bamoe-poc`, `bamoe-sandbox` 생성
2. 네 Project 모두에
   `app.kubernetes.io/managed-by=bamoe-poc-guide` label 적용
3. 자신의 계정에 네 Project의 namespace-scoped `admin` 권한 부여

### 2.2 기존 Project와 ownership 확인

성격: 조회. 네 이름이 이미 사용 중인지와 ownership label을 함께 확인한다.

```bash
oc get namespace \
  "$DEV_NS" \
  "$RUNTIME_NS" \
  "$APP_NS" \
  "$SANDBOX_NS" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

정상 관찰값은 다음 두 경우 중 하나다.

- Project가 존재하고 `OWNER`가 `bamoe-poc-guide`면 그대로 재사용한다.
- `NotFound`인 Project는 2.3에서 새로 만든다.

이름이 이미 존재하지만 `OWNER`가 비어 있거나 다른 값이면 다른 사용자의 자원일 수
있다. 그 Project에는 label을 추가하지 말고 플랫폼 관리자에게 소유자를 확인한다.

직전 실습에서 `oc new-project` 직후 terminal이 끊겨 label만 빠졌을 가능성이
있다면, 먼저 정확한 namespace 하나를 기록한다.

```bash
export RECOVERY_NS='<방금 자신이 생성한 것으로 확인할 Project 이름>'
```

OpenShift가 기록한 생성 요청자와 생성 시각을 조회한다.

```bash
oc get namespace "$RECOVERY_NS" \
  -o custom-columns='NAME:.metadata.name,REQUESTER:.metadata.annotations.openshift\.io/requester,CREATED:.metadata.creationTimestamp,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

현재 사용자도 별도로 확인한다.

```bash
oc whoami
```

`REQUESTER`가 현재 사용자와 같고, 생성 시각이 방금 실습한 시점이며, 플랫폼
관리자가 다른 용도로 사용되지 않았음을 확인한 경우에만 2.3의 해당
`oc label namespace ...` 단계부터 재개한다. requester가 비어 있거나 다르면
label을 임의로 붙이지 않는다.

### 2.3 없는 Project만 생성하고 표시하기

아래 변경 명령은 2.2에서 해당 이름이 `NotFound`였고, 2.1의 두 권한이 모두
`yes`일 때만 실행한다. 관리자가 이미 만든 Project 또는 올바른 label이 있는
Project에는 실행하지 않는다.

#### Dev Environment Project

성격: 변경. `bamoe-devtools` Project 하나만 생성한다.

```bash
oc new-project "$DEV_NS"
```

정상 관찰값: Project가 생성되고 현재 Project가 `bamoe-devtools`로 바뀐다.
`AlreadyExists`면 label을 적용하지 말고 2.2의 ownership 조회로 돌아간다.

성격: 관찰. 방금 생성된 namespace가 `Active`인지 확인한다.

```bash
oc get namespace "$DEV_NS" -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'
```

정상 관찰값: `STATUS`가 `Active`다. 그렇지 않으면 label을 적용하기 전에 플랫폼
관리자에게 상태를 확인한다.

성격: 변경. 이 가이드가 만든 namespace임을 표시한다.

```bash
oc label namespace "$DEV_NS" app.kubernetes.io/managed-by=bamoe-poc-guide
```

정상 관찰값: `namespace/... labeled`가 출력된다. `Forbidden`이면 관리자에게 같은
label 적용을 요청한다.

#### Runtime Environment Project

성격: 변경. `bamoe-runtime` Project 하나만 생성한다.

```bash
oc new-project "$RUNTIME_NS"
```

정상 관찰값: Project가 생성된다. `AlreadyExists`면 2.2의 ownership 조회로
돌아간다.

성격: 관찰. 방금 생성된 namespace가 `Active`인지 확인한다.

```bash
oc get namespace "$RUNTIME_NS" -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'
```

정상 관찰값: `STATUS`가 `Active`다.

성격: 변경. 이 가이드가 만든 namespace임을 표시한다.

```bash
oc label namespace "$RUNTIME_NS" app.kubernetes.io/managed-by=bamoe-poc-guide
```

정상 관찰값: `namespace/... labeled`가 출력된다. 실패하면 같은 label 적용을
관리자에게 요청한다.

#### Business Service Project

성격: 변경. `bamoe-poc` Project 하나만 생성한다.

```bash
oc new-project "$APP_NS"
```

정상 관찰값: Project가 생성된다. `AlreadyExists`면 2.2의 ownership 조회로
돌아간다.

성격: 관찰. 방금 생성된 namespace가 `Active`인지 확인한다.

```bash
oc get namespace "$APP_NS" -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'
```

정상 관찰값: `STATUS`가 `Active`다.

성격: 변경. 이 가이드가 만든 namespace임을 표시한다.

```bash
oc label namespace "$APP_NS" app.kubernetes.io/managed-by=bamoe-poc-guide
```

정상 관찰값: `namespace/... labeled`가 출력된다. 실패하면 같은 label 적용을
관리자에게 요청한다.

#### Canvas Sandbox Project

성격: 변경. `bamoe-sandbox` Project 하나만 생성한다.

```bash
oc new-project "$SANDBOX_NS"
```

정상 관찰값: Project가 생성된다. `AlreadyExists`면 2.2의 ownership 조회로
돌아간다.

성격: 관찰. 방금 생성된 namespace가 `Active`인지 확인한다.

```bash
oc get namespace "$SANDBOX_NS" -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'
```

정상 관찰값: `STATUS`가 `Active`다.

성격: 변경. 이 가이드가 만든 namespace임을 표시한다.

```bash
oc label namespace "$SANDBOX_NS" app.kubernetes.io/managed-by=bamoe-poc-guide
```

정상 관찰값: `namespace/... labeled`가 출력된다. 실패하면 같은 label 적용을
관리자에게 요청한다.

### 2.4 최종 상태와 권한 관찰

성격: 검증. 네 Project의 상태와 ownership을 한 화면에서 확인한다.

```bash
oc get namespace \
  "$DEV_NS" \
  "$RUNTIME_NS" \
  "$APP_NS" \
  "$SANDBOX_NS" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

정상 관찰값: 네 행 모두 `Active`, `bamoe-poc-guide`다. 하나라도 다르면 다음
권한 확인이나 설치로 넘어가지 않는다.

성격: 조회. 바로 다음 실습에서 필요한 Dev Project의 Pod 생성 권한을 확인한다.

```bash
oc auth can-i create pods -n "$DEV_NS"
```

정상 관찰값: `yes`다. `no`면 §3의 registry pull-test Pod를 만들 수 없다.

성격: 조회. Runtime 제품 manifest의 핵심 리소스인 Deployment 생성 권한을
확인한다.

```bash
oc auth can-i create deployments.apps -n "$RUNTIME_NS"
```

정상 관찰값: `yes`다. `no`면 Runtime 제품을 배포하기 전에 관리자에게 권한을
요청한다.

성격: 조회. Business Service Deployment 생성 권한을 확인한다.

```bash
oc auth can-i create deployments.apps -n "$APP_NS"
```

정상 관찰값: `yes`다. `no`면 앱, Secret, RBAC를 적용하기 전에 관리자에게 권한을
요청한다.

성격: 조회. Canvas가 sandbox Deployment를 만들 수 있도록 현재 사용자의 준비
권한을 확인한다.

```bash
oc auth can-i create deployments.apps -n "$SANDBOX_NS"
```

정상 관찰값: `yes`다. `no`면 Canvas Deploy 시연 전에 관리자에게 권한을 요청한다.

`oc auth can-i '*' '*'`는 실제 필요한 권한보다 훨씬 넓고, namespace `admin`에게도
`no`가 나올 수 있으므로 Gate로 사용하지 않는다. 위 네 명령은 다음 작업에 필요한
대표 권한만 확인한다. 실제 제품과 애플리케이션 manifest가 요구하는 Service,
Route, Secret,
ConfigMap, RBAC, PVC 등의 세부 권한은 적용 직전의 server-side dry-run에서
최종 검증한다.

**Gate**

- 네 Project가 모두 `Active`다.
- 네 Project의 `OWNER`가 모두 `bamoe-poc-guide`다.
- 기존 Project를 임의로 인수하거나 덮어쓰지 않았다.
- 네 namespace의 대표 권한 조회가 모두 `yes`다.

## 3. OpenShift worker의 외부 Registry 연결 확인

Mac에서 image를 내려받을 수 있어도 OpenShift worker가 같은 Registry에 접근할 수
있다는 보장은 없다. 이 절에서는 실제 worker에 임시 Pod를 하나씩 만들고
`생성 → 대기 → 관찰 → 삭제` 순서로 확인한다.

### 3.1 Quay의 BAMOE image 확인

성격: 조회. 같은 이름의 이전 테스트 Pod가 남아 있는지 확인한다.

```bash
oc get pod bamoe-quay-pull-test -n "$DEV_NS"
```

정상 관찰값: 첫 실행이라면 `NotFound`, 재실행이라면 기존 Pod 정보가 출력된다.
기존 Pod가 있을 때만 다음 삭제 단계를 실행한다.

성격: 변경. 재실행을 막는 이전 테스트 Pod 하나를 삭제한다.

```bash
oc delete pod bamoe-quay-pull-test -n "$DEV_NS" --ignore-not-found
```

정상 관찰값: 기존 Pod가 있으면 `deleted`, 없으면 오류 없이 끝난다. 다른 resource는
삭제하지 않는다.

성격: 변경. 공식 BAMOE 9.5 Maven Repository image로 임시 Pod 하나를 만든다.

```bash
oc run bamoe-quay-pull-test -n "$DEV_NS" --image=quay.io/bamoe/maven-repository:9.5.0-ibm-0005 --restart=Never
```

정상 관찰값: `pod/bamoe-quay-pull-test created`가 출력된다. 즉시
`Forbidden`이면 §2 권한을, admission 오류면 cluster 정책을 확인한다.

성격: 검증. worker가 image를 pull하고 container가 Ready가 될 때까지 기다린다.

```bash
oc wait pod/bamoe-quay-pull-test -n "$DEV_NS" --for=condition=Ready --timeout=5m
```

정상 관찰값: `condition met`가 출력된다. timeout 또는 실패면 삭제하기 전에 다음
두 진단 명령으로 원인을 확인한다.

성격: 실패 진단. Pod 상태와 image pull 오류를 확인한다.

```bash
oc describe pod bamoe-quay-pull-test -n "$DEV_NS"
```

정상 관찰값: 성공 시에는 실행할 필요가 없다. 실패 시 `ImagePullBackOff`, DNS,
인증 또는 allowlist 관련 Event를 찾는다.

성격: 실패 진단. 같은 Project의 최근 Event를 시간순으로 확인한다.

```bash
oc get events -n "$DEV_NS" --sort-by=.lastTimestamp
```

정상 관찰값: 성공 시에는 실행할 필요가 없다. 실패 시 마지막 Event의 registry
주소와 원인을 플랫폼 관리자에게 전달한다.

성격: 관찰. 실제 image와 Ready 값을 기록한다.

```bash
oc get pod bamoe-quay-pull-test \
  -n "$DEV_NS" \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready'
```

정상 관찰값: image가
`quay.io/bamoe/maven-repository:9.5.0-ibm-0005`, `READY`가 `true`다.

성격: 변경. 확인이 끝난 임시 Pod 하나를 삭제한다.

```bash
oc delete pod bamoe-quay-pull-test -n "$DEV_NS"
```

정상 관찰값: `deleted`가 출력된다. 삭제 실패면 Project 이름과 현재 권한을
확인한다.

### 3.2 Red Hat Registry의 UBI image 확인

성격: 조회. 같은 이름의 이전 테스트 Pod가 남아 있는지 확인한다.

```bash
oc get pod redhat-registry-pull-test -n "$DEV_NS"
```

정상 관찰값: 첫 실행이라면 `NotFound`, 재실행이라면 기존 Pod 정보가 출력된다.
기존 Pod가 있을 때만 다음 삭제 단계를 실행한다.

성격: 변경. 재실행을 막는 이전 테스트 Pod 하나를 삭제한다.

```bash
oc delete pod redhat-registry-pull-test -n "$DEV_NS" --ignore-not-found
```

정상 관찰값: 기존 Pod가 있으면 `deleted`, 없으면 오류 없이 끝난다.

성격: 변경. 명령을 읽고 관찰하는 동안 종료되지 않도록 Red Hat UBI 9.6 image로
최대 1시간 실행되는 임시 Pod 하나를 만든다. 검증 후에는 기다리지 않고 직접
삭제한다.

```bash
oc run redhat-registry-pull-test \
  -n "$DEV_NS" \
  --image=registry.access.redhat.com/ubi9/ubi:9.6 \
  --restart=Never \
  --command -- \
  sleep 3600
```

정상 관찰값: `pod/redhat-registry-pull-test created`가 출력된다.

성격: 검증. worker가 image를 pull하고 container가 Ready가 될 때까지 기다린다.

```bash
oc wait pod/redhat-registry-pull-test -n "$DEV_NS" --for=condition=Ready --timeout=5m
```

정상 관찰값: `condition met`가 출력된다. timeout 또는 실패면 삭제하기 전에 다음
두 진단 명령을 실행한다.

성격: 실패 진단. Pod 상태와 image pull 오류를 확인한다.

```bash
oc describe pod redhat-registry-pull-test -n "$DEV_NS"
```

정상 관찰값: 성공 시에는 실행할 필요가 없다. 실패 시 registry DNS, egress 또는
allowlist 관련 Event를 확인한다.

성격: 실패 진단. 같은 Project의 최근 Event를 시간순으로 확인한다.

```bash
oc get events -n "$DEV_NS" --sort-by=.lastTimestamp
```

정상 관찰값: 성공 시에는 실행할 필요가 없다. 실패 시 마지막 Event를 플랫폼
관리자에게 전달한다.

성격: 관찰. 실제 image와 Ready 값을 기록한다.

```bash
oc get pod redhat-registry-pull-test \
  -n "$DEV_NS" \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[0].image,READY:.status.containerStatuses[0].ready'
```

정상 관찰값: image가 `registry.access.redhat.com/ubi9/ubi:9.6`, `READY`가
`true`다.

성격: 변경. 확인이 끝난 임시 Pod 하나를 삭제한다.

```bash
oc delete pod redhat-registry-pull-test -n "$DEV_NS"
```

정상 관찰값: `deleted`가 출력된다.

**Gate**

- Quay BAMOE image의 `READY=true`를 확인했다.
- Red Hat UBI image의 `READY=true`를 확인했다.
- 두 임시 Pod를 모두 삭제했다.
- 실패가 있었다면 DNS, egress 또는 registry allowlist를 해결하고 두 검증을 다시
  통과했다.

## 4. PAMOE 9.5 직접 배포 자산 이해와 검증

이제 Helm chart를 다운로드하지 않는다. IBM이 공개한 여섯 개의 9.5 컨테이너
이미지를 `Deployment`, `Service`, `Route`로 직접 선언하고 Kustomize로 조립한다.
IBM 9.5 문서도 Dev 구성요소의 개별 OpenShift 설치와 Management Console의 직접
설치를 안내한다.

- [BAMOE 9.5 Dev Environment 설치](https://www.ibm.com/docs/en/ibamoe/9.5.0?topic=installing-dev-environment)
- [BAMOE 9.5 Runtime Environment 설치](https://www.ibm.com/docs/en/ibamoe/9.5.0?topic=installing-runtime-environment)
- [BAMOE MCP Server Tech Preview](https://www.ibm.com/docs/en/ibamoe/9.5.0?topic=ia-exposing-bamoe-capabilities-ai-agents-through-mcp-server-tech-preview)

직접 배포는 chart가 자동으로 만들던 값을 우리가 명시적으로 관리한다는 뜻이다.
이번 repository의 `deploy/openshift/products/`가 그 선언의 기준이다.

```text
deploy/openshift/products/
├─ dev/
│  ├─ kustomization.yaml
│  ├─ canvas.yaml
│  ├─ cors-proxy.yaml
│  ├─ extended-services.yaml
│  └─ maven-repository.yaml
└─ runtime/
   ├─ kustomization.yaml
   ├─ management-console.yaml
   └─ mcp-server.yaml
```

> **PoC 지원 경계:** 공식 문서는 Helm을 권장 설치 경로로 설명한다. 여기서는 공개
> 9.5 chart를 받을 수 없는 현재 상황과 OCP 학습 목적 때문에 공식 개별 이미지를
> 직접 배포한다. PAMOE 라이선스 annotation은 Pod template에 수동으로 넣었지만,
> License Service 연동은 이번 내부 PoC의 Gate에서 제외한다. 운영 전환 시에는
> IBM 지원 설치 경로, 라이선스 수집, 인증, persistence와 정식 지원 OCP 조합을
> 다시 검토한다. 9.4 chart에 9.5 image를 끼워 넣는 혼합 방식은 사용하지 않는다.

추천 세션 B를 새 terminal에서 시작했다면 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

환경값과 현재 cluster 연결을 다시 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

```bash
bamoe_check_env
```

### 4.1 여섯 이미지의 역할과 네트워크 계약

| Project | 구성요소 | 공식 image | 컨테이너 HTTP port | 외부 Route |
|---|---|---|---:|---|
| `bamoe-devtools` | Canvas | `quay.io/bamoe/canvas:9.5.0-ibm-0005` | 8080 | 있음 |
| `bamoe-devtools` | CORS Proxy | `quay.io/bamoe/cors-proxy:9.5.0-ibm-0005` | 8080 | 있음 |
| `bamoe-devtools` | Extended Services | `quay.io/bamoe/extended-services:9.5.0-ibm-0005` | 21345 | 있음 |
| `bamoe-devtools` | Maven Repository | `quay.io/bamoe/maven-repository:9.5.0-ibm-0005` | 8080 | 없음 |
| `bamoe-runtime` | Management Console | `quay.io/bamoe/management-console:9.5.0-ibm-0005` | 8080 | 있음 |
| `bamoe-runtime` | MCP Server | `quay.io/bamoe/mcp-server:9.5.0-ibm-0005` | 8080 | 없음 |

Canvas의 사용자 정의 배포는 위 여섯 상시 제품 Pod와 별도로
`quay.io/bamoe/canvas-dev-deployment-base:9.5.0-ibm-0005-jdk21`을
`bamoe-sandbox`의 임시 Pod에 사용한다.

성격: 조회. 여섯 제품 tag와 Canvas 지원 image tag의 `linux/amd64` metadata를
Quay에서 읽는다.

```bash
oc image info \
  quay.io/bamoe/canvas:9.5.0-ibm-0005 \
  quay.io/bamoe/cors-proxy:9.5.0-ibm-0005 \
  quay.io/bamoe/extended-services:9.5.0-ibm-0005 \
  quay.io/bamoe/maven-repository:9.5.0-ibm-0005 \
  quay.io/bamoe/management-console:9.5.0-ibm-0005 \
  quay.io/bamoe/mcp-server:9.5.0-ibm-0005 \
  quay.io/bamoe/canvas-dev-deployment-base:9.5.0-ibm-0005-jdk21 \
  --filter-by-os='linux/amd64'
```

정상 관찰값: 일곱 image가 모두 조회되고 각각의 digest, OS `linux`, Architecture
`amd64`가 표시된다. `not found`가 하나라도 있으면 version을 임의로 바꾸지 않고
중단한다. `--insecure` 또는 `--skip-verification`도 추가하지 않는다. 실제
sandbox worker pull은 §13.1에서 한 번 더 확인한다.

이번 PoC manifest는 사람이 읽기 쉬운 IBM release tag를 사용한다. 위 출력의
digest를 배포 기록에 함께 남긴다. 운영 전환이나 장기 rollback 재현성이 필요할
때에는 검증한 동일 digest로 image를 고정하고 변경 관리한다.

Canvas 화면은 사용자 Mac의 브라우저에서 Extended Services와 CORS Proxy를 직접
호출한다. 따라서 Canvas의 두 backend URL에는 내부 Service DNS가 아니라 브라우저가
접근할 수 있는 HTTPS Route를 넣어야 한다.

Maven Repository는 BAMOE 라이브러리를 포함하므로 기본적으로 인터넷에 공개하지
않는다. 로컬에서 잠시 확인할 때에는 §5.4의 `port-forward`를 사용한다. MCP Server도
현재 인증을 사용하지 않는 Technology Preview이므로 ClusterIP Service만 만들고
Route를 만들지 않는다.

성격: 조회. Dev Kustomization이 참조하는 파일을 읽는다.

```bash
sed -n '1,120p' deploy/openshift/products/dev/kustomization.yaml
```

정상 관찰값: `canvas.yaml`, `cors-proxy.yaml`, `extended-services.yaml`,
`maven-repository.yaml` 네 파일이 보이고 namespace가 `bamoe-devtools`다.

성격: 조회. Runtime Kustomization도 읽는다.

```bash
sed -n '1,120p' deploy/openshift/products/runtime/kustomization.yaml
```

정상 관찰값: `management-console.yaml`, `mcp-server.yaml` 두 파일과
`namespace: bamoe-runtime`이 보인다.

### 4.2 현재 cluster에 묶인 값 확인

제품 YAML에는 현재 확인한 Route domain과 고정 Project 이름이 들어 있다. 다른
cluster에 재사용할 때에는 이 값을 먼저 바꾸고 review해야 한다. `${VAR}` 문자열은
일반 YAML 안에서 자동 치환되지 않으므로 manifest에 넣지 않았다.

현재 실제 Route domain을 다시 조회한다.

```bash
printf 'ACTUAL_ROUTE_DOMAIN=%s\n' "$OCP_ROUTE_DOMAIN"
```

제품 YAML에 들어 있는 Route host와 브라우저 URL을 확인한다.

```bash
rg -n 'https://|host:' \
  deploy/openshift/route.yaml \
  deploy/openshift/base/configmap.yaml \
  deploy/openshift/products/dev \
  deploy/openshift/products/runtime
```

정상 관찰값: 모든 외부 host가
`apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com`으로 끝난다. 실제
`OCP_ROUTE_DOMAIN`과 한 글자라도 다르면 적용하지 말고 제품 YAML의 `spec.host`,
Canvas backend URL, Management Console의 Business Service URL, 앱 CORS
origin/allowlist를 함께 수정한다. 특히 다음 세 값은 하나의 계약이다.

- `route.yaml`의 Business Service host
- `management-console.yaml`의 `businessServiceUrl`
- `base/configmap.yaml`의 `BAMOE_CORS_ALLOWED_ORIGIN_PATTERNS`

셋 중 하나만 바꾸면 Management Console 카드 또는 브라우저 호출이 실패한다.
고친 뒤에는 Git에 포함된 manifest를 다시 render·dry-run·apply한다. live
Deployment나 ConfigMap만 즉석 수정하면 다음 재배포에서 값이 되돌아간다.

Canvas에 필요한 세 환경변수를 확인한다.

```bash
rg -n \
  'KIE_SANDBOX_(EXTENDED_SERVICES_URL|CORS_PROXY_URL|DEV_DEPLOYMENT_BASE_IMAGE_URL)' \
  deploy/openshift/products/dev/canvas.yaml
```

정상 관찰값:

- Extended Services와 CORS Proxy가 각각 `https://` Route URL을 사용한다.
- Dev Deployment base가
  `quay.io/bamoe/canvas-dev-deployment-base:9.5.0-ibm-0005-jdk21`이다.

CORS Proxy의 origin과 host 제한을 확인한다.

```bash
rg -n 'CORS_PROXY_(ALLOWED_ORIGINS|ALLOWED_HOSTS|VERBOSE)' \
  deploy/openshift/products/dev/cors-proxy.yaml
```

`CORS_PROXY_ALLOWED_ORIGINS`는 정확한 Canvas origin 하나다. `ALLOWED_HOSTS`에는
현재 GitHub와 OpenShift API/Route domain만 있다. 기능이 안 된다는 이유로
`ALLOWED_ORIGINS=*`를 넣으면 안 된다. 새 Git provider나 cluster를 연결할 때에는
필요한 host pattern만 review해서 추가한다.

Runtime의 내부 OpenAPI URL을 확인한다.

```bash
rg -n 'MCP_SERVER_(OPENAPI_URLS|SECURITY_ENABLED)' \
  deploy/openshift/products/runtime/mcp-server.yaml
```

정상 관찰값:

```text
http://customer-rule-poc.bamoe-poc.svc.cluster.local:8080/v3/api-docs
MCP_SERVER_SECURITY_ENABLED=false
```

MCP는 서버에서 OpenAPI를 읽으므로 여기에는 내부 Service DNS가 맞다.

### 4.3 Kustomize가 만드는 최종 YAML 관찰

Kustomize는 여러 파일을 API server에 보낼 한 manifest로 조립한다. 원본 파일은
바꾸지 않는다.

성격: 로컬 준비. Dev render 결과를 저장할 충돌 없는 임시 파일을 만든다.

```bash
export BAMOE_DEV_RENDERED="$(mktemp /tmp/bamoe-dev-direct.XXXXXX)"
```

```bash
printf 'BAMOE_DEV_RENDERED=%s\n' "$BAMOE_DEV_RENDERED"
```

성격: 조회 준비. Dev manifest를 조립한다.

```bash
kustomize build deploy/openshift/products/dev > "$BAMOE_DEV_RENDERED"
```

성격: 관찰. 조립 결과가 비어 있지 않은지 본다.

```bash
wc -l "$BAMOE_DEV_RENDERED"
```

0보다 큰 줄 수가 나와야 한다.

Dev manifest의 리소스 종류와 이름을 읽는다.

```bash
rg -n '^(kind:|  name:)' "$BAMOE_DEV_RENDERED"
```

정상 관찰값: Service 4개, Deployment 4개, Route 3개다. Maven Repository Route는
없어야 한다.

Dev manifest의 실제 image 전체를 추출한다.

```bash
awk '
  $1 == "image:" {print $2}
  $1 == "-" && $2 == "image:" {print $3}
' "$BAMOE_DEV_RENDERED" | sort -u
```

정상 관찰값: Canvas, CORS Proxy, Extended Services, Maven Repository 네 image다.
tag 뒤에 다른 문자가 붙지 않은 전체 값이어야 한다.

기대 목록과 **전체 문자열**이 정확히 같은지 검증한다.

```bash
test "$(
  awk '
    $1 == "image:" {print $2}
    $1 == "-" && $2 == "image:" {print $3}
  ' "$BAMOE_DEV_RENDERED" | sort -u
)" = "$(
  printf '%s\n' \
    'quay.io/bamoe/canvas:9.5.0-ibm-0005' \
    'quay.io/bamoe/cors-proxy:9.5.0-ibm-0005' \
    'quay.io/bamoe/extended-services:9.5.0-ibm-0005' \
    'quay.io/bamoe/maven-repository:9.5.0-ibm-0005' \
    | sort -u
)"
```

정상이면 출력 없이 성공한다.

Runtime 결과용 임시 파일을 만든다.

```bash
export BAMOE_RUNTIME_RENDERED="$(mktemp /tmp/bamoe-runtime-direct.XXXXXX)"
```

Runtime manifest를 조립한다.

```bash
kustomize build deploy/openshift/products/runtime > "$BAMOE_RUNTIME_RENDERED"
```

Runtime 리소스 종류와 이름을 읽는다.

```bash
rg -n '^(kind:|  name:)' "$BAMOE_RUNTIME_RENDERED"
```

정상 관찰값: Service 2개, Deployment 2개, Management Console Route 1개다.
MCP Route는 없어야 한다.

Runtime image 전체를 추출한다.

```bash
awk '
  $1 == "image:" {print $2}
  $1 == "-" && $2 == "image:" {print $3}
' "$BAMOE_RUNTIME_RENDERED" | sort -u
```

정상 관찰값: Management Console과 MCP Server 두 image다.

기대 목록과 전체 문자열이 정확히 같은지 검증한다.

```bash
test "$(
  awk '
    $1 == "image:" {print $2}
    $1 == "-" && $2 == "image:" {print $3}
  ' "$BAMOE_RUNTIME_RENDERED" | sort -u
)" = "$(
  printf '%s\n' \
    'quay.io/bamoe/management-console:9.5.0-ibm-0005' \
    'quay.io/bamoe/mcp-server:9.5.0-ibm-0005' \
    | sort -u
)"
```

정상이면 출력 없이 성공한다.

### 4.4 보안과 라이선스 선언 확인

모든 제품 컨테이너는 OpenShift restricted SCC가 namespace 범위의 UID를 배정할
수 있게 `runAsUser`를 고정하지 않았다. 대신 non-root, seccomp, privilege
escalation 금지, Linux capability 제거를 선언했다. 제품 entrypoint가 시작할 때
설정 파일을 만들 수 있으므로 검증 없이 `readOnlyRootFilesystem: true`를 일괄
적용하지 않는다.

고정 UID가 없는지 확인한다.

```bash
if rg -n 'runAsUser:' deploy/openshift/products; then
  printf 'GATE=FAIL: fixed runAsUser found\n'
else
  printf 'GATE=PASS: SCC may assign an allowed UID\n'
fi
```

정상 출력은 `GATE=PASS`다.

PAMOE 제품 annotation이 여섯 Deployment의 Pod template에 들어 있는지 관찰한다.

```bash
rg -n 'product(Name|ID|Version|Metric|ChargedContainers)|includeSWCUpload' \
  deploy/openshift/products
```

이 annotation을 넣었다고 License Service 연결까지 완료되는 것은 아니다. 이번
PoC에서는 product identity를 보존하지만 라이선스 수집을 성공 Gate로 삼지 않는다.

**Gate**

- 여섯 제품 image가 모두 정확히 `9.5.0-ibm-0005`다.
- Canvas 지원 image가 정확히 `9.5.0-ibm-0005-jdk21`이고 `amd64` metadata가
  조회된다.
- Dev render에는 Deployment/Service 4개와 외부 Route 3개가 있다.
- Runtime render에는 Deployment/Service 2개와 Management Console Route만 있다.
- Canvas backend URL과 CORS origin이 현재 외부 Route 계약과 일치한다.
- Maven Repository와 MCP Server에는 외부 Route가 없다.
- manifest에 고정 `runAsUser`가 없고 PAMOE annotation이 있다.

## 5. PAMOE Dev Environment 직접 설치

이 절에서는 §4에서 조립한 **동일한 Dev manifest 파일**을 순서대로 검증하고
적용한다. `oc apply`는 여러 리소스를 차례로 저장하므로 Helm의 `--atomic` 같은
전체 자동 rollback은 없다. dry-run이 모두 성공한 뒤 한 번만 적용하고, 실패하면
즉시 반복하지 말고 생성된 상태와 Event를 먼저 확인한다.

### 5.1 대상과 기존 리소스 확인

현재 로그인 대상과 namespace를 표시한다.

```bash
oc whoami --show-server
```

```bash
printf 'DEV_NS=%s\n' "$DEV_NS"
```

기대값은 현재 API server와 `bamoe-devtools`다.

Dev Project ownership을 확인한다.

```bash
oc get namespace "$DEV_NS" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

`STATUS=Active`, `OWNER=bamoe-poc-guide`가 아니면 적용하지 않는다.

Dev Project의 quota와 기본 제한을 관찰한다.

```bash
oc get resourcequota,limitrange -n "$DEV_NS"
```

네 Dev Deployment의 기본 요청량 합계는 CPU 약 `1.1`, memory 약 `2.2Gi`다.
ResourceQuota가 더 작거나 LimitRange가 manifest와 충돌하면 적용 전에 플랫폼
관리자와 값을 조정한다.

같은 part-of label을 가진 기존 리소스를 조회한다.

```bash
oc get deployment,service,route \
  -n "$DEV_NS" \
  -l app.kubernetes.io/part-of=bamoe-dev-environment
```

처음이면 `No resources found`가 정상이다. 기존 리소스가 있으면 새 설치가 아니라
선언 상태 갱신이므로 현재 소유자와 image를 먼저 확인한다.

cluster 전체에서 같은 Dev Route host를 이미 쓰는지 조회한다.

```bash
oc get route -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOST:.spec.host' \
  | rg 'bamoe-(canvas|cors-proxy|extended-services)\.'
```

처음 설치라면 아무 출력이 없어야 한다. 행이 있다면
`bamoe-devtools`의 같은 이름으로 이전에 만든 리소스인지 확인한다. 다른 Project가
host를 사용 중이면 manifest host를 review해서 바꾸기 전에는 적용하지 않는다.

현재 render 파일이 남아 있는지 확인한다.

```bash
test -s "$BAMOE_DEV_RENDERED"
```

아무 출력 없이 성공해야 한다. 새 terminal이라 변수가 비었다면 §4.3의 `mktemp`와
`kustomize build`를 다시 실행한다.

### 5.2 API server dry-run

성격: 검증. manifest를 저장하지 않고 schema, 권한, admission policy를 확인한다.

```bash
oc apply \
  --dry-run=server \
  -n "$DEV_NS" \
  -f "$BAMOE_DEV_RENDERED"
```

모든 행이 `created (server dry run)` 또는 `configured (server dry run)`이어야
한다. `Forbidden`이면 §2 권한을, SCC 오류면 Pod securityContext를, Route host
충돌이면 동일 host를 선점한 Route를 확인한다.

적용 전 예상 차이를 읽는다.

```bash
oc diff -n "$DEV_NS" -f "$BAMOE_DEV_RENDERED"
```

처음 설치에서는 추가될 YAML과 종료 코드 `1`이 정상이다. `oc diff`의 `1`은
“차이가 있다”는 뜻이고 설치 오류가 아니다. 이해하지 못한 삭제나 다른 namespace가
보이면 적용하지 않는다.

### 5.3 Dev manifest 한 번 적용하고 rollout 관찰

> **외부 공개 전 확인:** Canvas, CORS Proxy, Extended Services Route에는 아직
> 사용자 인증이 없다. 합성 데이터만 사용하고 시연 후에는 §17.5에서 Route를
> 제거한다. Maven Repository는 manifest에서 외부에 공개하지 않는다.

검증한 동일 파일을 cluster에 반영한다.

```bash
oc apply -n "$DEV_NS" -f "$BAMOE_DEV_RENDERED"
```

`created`, `configured`, `unchanged`는 API server가 선언을 받아들였다는 뜻이다.
애플리케이션 준비 완료라는 뜻은 아니므로 다음 네 rollout을 하나씩 확인한다.

Extended Services를 기다린다.

```bash
oc rollout status \
  deployment/bamoe-extended-services \
  -n "$DEV_NS" \
  --timeout=8m
```

CORS Proxy를 기다린다.

```bash
oc rollout status \
  deployment/bamoe-cors-proxy \
  -n "$DEV_NS" \
  --timeout=5m
```

Maven Repository를 기다린다.

```bash
oc rollout status \
  deployment/bamoe-maven-repository \
  -n "$DEV_NS" \
  --timeout=5m
```

Canvas를 기다린다.

```bash
oc rollout status \
  deployment/bamoe-canvas \
  -n "$DEV_NS" \
  --timeout=5m
```

네 Deployment 상태와 실제 image를 관찰한다.

```bash
oc get deployment \
  -n "$DEV_NS" \
  -l app.kubernetes.io/part-of=bamoe-dev-environment \
  -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas,IMAGE:.spec.template.spec.containers[0].image'
```

정상 관찰값: 네 행 모두 `READY=1`, `AVAILABLE=1`이고 image가 정확한 9.5 tag다.

Pod가 할당받은 실제 UID와 node를 관찰한다.

```bash
oc get pod \
  -n "$DEV_NS" \
  -l app.kubernetes.io/part-of=bamoe-dev-environment \
  -o wide
```

실패한 Deployment가 있을 때에만 최근 Event를 확인한다.

```bash
oc get events -n "$DEV_NS" --sort-by=.lastTimestamp
```

실패한 Pod 하나의 이름을 위 출력에서 복사한다.

```bash
export FAILED_DEV_POD='<실패한 실제 Pod 이름>'
```

실패했을 때에만 상세와 log를 확인한다.

```bash
oc describe pod "$FAILED_DEV_POD" -n "$DEV_NS"
```

```bash
oc logs pod/"$FAILED_DEV_POD" -n "$DEV_NS" --tail=200
```

성공했다면 `FAILED_DEV_POD` 설정과 두 진단 명령은 실행하지 않는다.

### 5.4 Route와 브라우저 연결 검증

세 Route의 host, Service, TLS를 확인한다.

```bash
oc get route \
  -n "$DEV_NS" \
  -l app.kubernetes.io/part-of=bamoe-dev-environment \
  -o custom-columns='NAME:.metadata.name,HOST:.spec.host,SERVICE:.spec.to.name,PORT:.spec.port.targetPort,TLS:.spec.tls.termination,ADMITTED:.status.ingress[0].conditions[?(@.type=="Admitted")].status'
```

정상 관찰값:

- `bamoe-canvas → bamoe-canvas:http`
- `bamoe-cors-proxy → bamoe-cors-proxy:http`
- `bamoe-extended-services → bamoe-extended-services:http`
- 모두 `TLS=edge`, `ADMITTED=True`

Maven Repository Route가 없는지 확인한다.

```bash
oc get route bamoe-maven-repository \
  -n "$DEV_NS" \
  --ignore-not-found \
  -o name
```

정상 관찰값은 빈 출력이다.

Canvas URL을 manifest의 고정 Route에서 읽는다.

```bash
export CANVAS_URL="https://$(oc get route bamoe-canvas -n "$DEV_NS" -o jsonpath='{.spec.host}')"
```

```bash
printf 'CANVAS_URL=%s\n' "$CANVAS_URL"
```

Canvas 외부 HTTPS와 인증서를 확인한다.

```bash
curl \
  --fail \
  --silent \
  --show-error \
  --output /dev/null \
  --write-out 'HTTP_STATUS=%{http_code}\n' \
  --retry 10 \
  --retry-delay 3 \
  "$CANVAS_URL/"
```

정상은 `HTTP_STATUS=200`이며 인증서 오류가 없어야 한다. `-k`는 추가하지 않는다.

CORS Proxy health를 확인한다.

```bash
curl \
  --fail \
  --silent \
  --show-error \
  "https://$(oc get route bamoe-cors-proxy -n "$DEV_NS" -o jsonpath='{.spec.host}')/ping"
```

Extended Services health를 확인한다.

```bash
curl \
  --fail \
  --silent \
  --show-error \
  "https://$(oc get route bamoe-extended-services -n "$DEV_NS" -o jsonpath='{.spec.host}')/ping"
```

Canvas Pod에 실제 저장된 backend URL을 읽는다.

```bash
oc set env \
  deployment/bamoe-canvas \
  -n "$DEV_NS" \
  --list \
  | rg 'KIE_SANDBOX_(EXTENDED_SERVICES_URL|CORS_PROXY_URL|DEV_DEPLOYMENT_BASE_IMAGE_URL)'
```

두 backend URL이 방금 성공한 Route와 정확히 같아야 한다.

CORS Proxy의 실제 제한값도 읽는다.

```bash
oc set env \
  deployment/bamoe-cors-proxy \
  -n "$DEV_NS" \
  --list \
  | rg 'CORS_PROXY_(ALLOWED_ORIGINS|ALLOWED_HOSTS|VERBOSE)'
```

`ALLOWED_ORIGINS`가 정확한 Canvas origin이어야 한다.

Maven Repository를 외부 Route 없이 확인하려면 별도 terminal에서 다음 forwarding을
시작한다. 이 명령은 종료할 때까지 terminal을 점유한다.

```bash
oc port-forward \
  -n "$DEV_NS" \
  service/bamoe-maven-repository \
  11099:8080
```

다른 terminal에서 응답을 확인한다.

```bash
curl --fail --silent --show-error http://127.0.0.1:11099/ >/dev/null
```

확인이 끝나면 port-forward terminal에서 `Ctrl+C`를 눌러 종료한다. 이 단계는
Route나 Service를 삭제하지 않는다.

마지막으로 브라우저에서 `CANVAS_URL`을 연다. 화면은 열리지만 DMN Runner,
검증, Git/OCP 연결이 실패한다면 브라우저 개발자 도구의 Network와 CORS Proxy
log를 확인한다.

```bash
oc logs deployment/bamoe-cors-proxy -n "$DEV_NS" --tail=200
```

Mac에서 GitHub가 열리는 것과 Dev Pod가 외부로 나갈 수 있는 것은 다른 조건이다.
Canvas Git 연결과 임시 Maven build에 필요한 Pod outbound egress를 별도 확인한다.
먼저 같은 이름의 진단 Pod만 정리한다.

```bash
oc delete pod bamoe-dev-egress-check \
  -n "$DEV_NS" \
  --ignore-not-found
```

GitHub API와 Maven Central에 HTTPS GET을 수행하는 일회성 Pod를 만든다.

```bash
oc run bamoe-dev-egress-check \
  -n "$DEV_NS" \
  --image=registry.access.redhat.com/ubi9/ubi:latest \
  --restart=Never \
  --command -- \
  sh -c '
    curl --fail --silent --show-error \
      --connect-timeout 10 \
      --max-time 30 \
      https://api.github.com/meta \
      >/dev/null \
    && curl --fail --silent --show-error \
      --connect-timeout 10 \
      --max-time 30 \
      https://repo.maven.apache.org/maven2/ \
      >/dev/null \
    && printf "DEV_POD_EGRESS_GATE=PASS\n"
  '
```

Pod가 성공 종료될 때까지 기다린다.

```bash
oc wait pod/bamoe-dev-egress-check \
  -n "$DEV_NS" \
  --for=jsonpath='{.status.phase}'=Succeeded \
  --timeout=2m
```

결과를 확인한다.

```bash
oc logs pod/bamoe-dev-egress-check -n "$DEV_NS"
```

정상 출력은 `DEV_POD_EGRESS_GATE=PASS`다. DNS, proxy, timeout 오류면 Canvas
설정을 바꾸기 전에 cluster egress policy, corporate proxy, NetworkPolicy를
플랫폼 관리자와 확인한다.

```bash
oc delete pod bamoe-dev-egress-check -n "$DEV_NS"
```

**Gate**

- 네 Dev Deployment가 `READY=1`, `AVAILABLE=1`이다.
- 세 외부 Route가 정확한 Service를 가리키고 `Admitted=True`다.
- Canvas, CORS `/ping`, Extended Services `/ping`이 일반 TLS로 성공한다.
- Canvas backend URL과 CORS origin이 실제 Route와 일치한다.
- Maven Repository는 Route 없이 port-forward로 응답한다.
- Dev Pod에서 GitHub API와 Maven Central HTTPS egress가 성공한다.

§4에서 만든 두 비밀이 아닌 render 파일은 더 이상 사용하지 않는다. 경로 prefix,
일반 파일, 현재 사용자 소유를 같은 블록에서 확인한 뒤 제거한다.

```bash
if (
  case "${BAMOE_DEV_RENDERED:-}" in
    /tmp/bamoe-dev-direct.*) ;;
    *) exit 1 ;;
  esac
  case "${BAMOE_RUNTIME_RENDERED:-}" in
    /tmp/bamoe-runtime-direct.*) ;;
    *) exit 1 ;;
  esac
  test -f "$BAMOE_DEV_RENDERED" \
    && test -O "$BAMOE_DEV_RENDERED" \
    && test ! -L "$BAMOE_DEV_RENDERED"
  test -f "$BAMOE_RUNTIME_RENDERED" \
    && test -O "$BAMOE_RUNTIME_RENDERED" \
    && test ! -L "$BAMOE_RUNTIME_RENDERED"
)
then
  unlink "$BAMOE_DEV_RENDERED"
  unlink "$BAMOE_RUNTIME_RENDERED"
  unset BAMOE_DEV_RENDERED BAMOE_RUNTIME_RENDERED
  printf 'PRODUCT_RENDER_TEMP_CLEANUP_GATE=PASS\n'
else
  printf 'REFUSE: product render temp path or ownership mismatch\n' >&2
fi
```

## 6. 독립 private GitHub repository 만들기

현재 `test/`는 더 큰 상위 Git repository 안에 있으므로 `SOURCE_DIR`에서 다시
`git init`하지 않는다. 배포 가능한 내용만 sibling 경로인
`skt_bamoe_party/bamoe-customer-rule-poc`로 복사해 별도 repository를 만든다.
선택한 작업 경로 역시 상위 `/Users/jihunkeom/Desktop/projects/2026/SKT`
repository 안에 있으므로, 복사나 `git init` 전에 그 상위 repository의
`.git/info/exclude`에 대상 경로를 로컬로 제외해야 한다. 이 제외는 GitHub에
push되지 않으며, 상위 repository가 내부 BAMOE repository를 실수로 stage하는
것만 방지한다.

추천 세션 C를 새 terminal에서 시작했다면 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

source와 독립 GitHub 작업 사본 경로를 다시 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

필수 값과 현재 cluster 연결을 검증한다.

```bash
bamoe_check_env
```

최초 실행에서 아직 상위 Git local exclude를 설정하지 않았다면
`INFO: parent local exclude is not registered yet`가 함께 나올 수 있다. 이것은
환경 검사 실패가 아니라 §6.1 설정 전 상태를 알려 주는 안내다. 이 시점에는
`GITHUB_WORK_DIR`를 만들지 말고 §6.1의 local exclude 등록까지 순서대로 진행한다.
등록 후 `bamoe_check_env`를 다시 실행하면 이 `INFO`는 사라져야 한다.

이 섹션에서 가장 중요한 순서는 다음과 같다.

```text
독립 작업 사본 → 보안 제외 확인 → 첫 commit → private repository 생성
→ OCP_AUTO_DEPLOY=false → 첫 push
```

`OCP_AUTO_DEPLOY=false`를 첫 push보다 먼저 설정해야 아직 존재하지 않는 OCP
Deployment를 workflow가 수정하려고 시도하지 않는다.

`SOURCE_DIR`에는 아직 로컬 구현 중인 Case 05 실행 자산도 있지만, 이번 OCP
bootstrap 범위는 검증이 끝난 Case 01~04다. 아래 복사 명령은 Case 05 가이드 문서는
보존하되 BPMN, DMN, SCESIM, Mock 초안은 명시적으로 제외한다. Case 05 구현이
로컬에서 완료되면 §14의 검증·commit 절차와 함께 OCP Mock port·Service 계약도
별도 변경으로 추가한다.

현재 checked-in `Case02WirelineNameChangeTest.scesim`은 결과 상태·사유 코드는
검증하지만 `Result.reasonMessage` EXPECT mapping은 아직 사용자가 UI에서 보강할
후속 항목이다. 이 누락은 container 배포를 막지는 않지만 “모든 고객 메시지까지
자동 회귀 검증됐다”는 주장에는 포함할 수 없다. Case 02 가이드의 SCESIM 표대로
mapping을 추가하고 `clean verify`를 다시 통과한 뒤에만 해당 체크를 완료 처리한다.

### 6.1 공통 사전 확인

**목적:** GitHub CLI가 의도한 계정으로 로그인되어 있는지 조회한다.

```bash
gh auth status
```

정상이면 `github.com` 로그인 계정이 `GITHUB_OWNER`와 일치한다. 실패하면 repository를
만들기 전에 `gh auth login`으로 로그인하고, token이나 인증 코드는 공유하지 않는다.

**목적:** 이 가이드가 검증하는 방식과 동일하게 GitHub remote protocol이
HTTPS인지 조회한다.

```bash
gh config get git_protocol --host github.com
```

정상 출력은 `https`다. `ssh`가 나오면 아래 로컬 설정 변경을 한 번 실행한다.

```bash
gh config set git_protocol https --host github.com
```

설정 후 바로 위 조회 명령을 다시 실행해 `https`를 확인한다.

**목적:** 만들려는 이름의 GitHub repository가 이미 있는지 먼저 조회한다.

```bash
gh repo view "${GITHUB_OWNER}/${GITHUB_REPO}" --json nameWithOwner,isPrivate,url
```

- `Could not resolve to a Repository`라면 새 repository 이름이므로 §6.2로 간다.
- private repository 정보가 출력되고 완성된 `GITHUB_WORK_DIR`도 있다면 §6.2를
  건너뛰고 §6.3으로 간다.
- repository는 있지만 로컬 작업 사본이 없다면 같은 이름으로 새 repository를
  만들지 않는다. 기존 내용을 먼저 별도 clone해 검토하거나, 이번 PoC에 사용할
  새 이름으로 `GITHUB_REPO`와 `GITHUB_WORK_DIR`를 변경한 뒤 §6.1부터 다시
  확인한다.

**목적:** 복사 원본이 BAMOE 프로젝트 root인지 확인한다.

```bash
test -f "$SOURCE_DIR/pom.xml"
```

정상이면 출력 없이 종료 코드가 `0`이다. 실패하면 새 terminal에서
`source deploy/openshift/ocp-env.sh`를 다시 실행하고 `SOURCE_DIR` 값을 확인한다.

**목적:** 복사 원본을 포함하는 상위 Git repository의 root를 조회한다.

```bash
git -C "$SOURCE_DIR" rev-parse --show-toplevel
```

현재 환경의 정상 출력은
`/Users/jihunkeom/Desktop/projects/2026/SKT`다. 즉 `SOURCE_DIR` 안에서 다시
`git init`하면 독립 repository가 아니라 상위 repository 안의 중첩 repository가
된다.

**목적:** 새 작업 사본이 위치할 상위 Git repository를 확인한다.

```bash
git -C "$(dirname "$GITHUB_WORK_DIR")" rev-parse --show-toplevel
```

현재 환경의 정상 출력은
`/Users/jihunkeom/Desktop/projects/2026/SKT`다. 선택한 `GITHUB_WORK_DIR`는 이
상위 repository 안에 있지만 `SOURCE_DIR`와는 다른 sibling 경로다. 이 구성을
안전하게 사용하려면 다음 로컬 제외 Gate를 반드시 통과해야 한다.

**목적:** 환경 파일에 저장된 상위 root가 실제 조회값과 같은지 검증한다.

```bash
test "$(
  git -C "$(dirname "$GITHUB_WORK_DIR")" rev-parse --show-toplevel
)" = "$GITHUB_PARENT_REPO_ROOT"
```

정상이면 출력 없이 성공한다. 실패하면 경로를 추측해 진행하지 말고
`bamoe_show_env`의 `GITHUB_WORK_DIR`와 `GITHUB_PARENT_ROOT`를 확인한다.

**조회:** 상위 repository의 로컬 exclude 파일에 대상 규칙이 이미 있는지
확인한다.

```bash
rg -n -F \
  "$GITHUB_WORK_DIR_EXCLUDE_PATTERN" \
  "$GITHUB_PARENT_REPO_ROOT/.git/info/exclude"
```

`/skt_bamoe_party/bamoe-customer-rule-poc/`가 포함된 한 줄이 나오면 아래 추가
명령은 건너뛴다. 아무 출력도 없으면 아직 규칙이 없는 최초 실행 상태다.

**조건부 변경:** 바로 위 조회가 아무 출력도 내지 않았을 때만 대상 경로를 상위
repository의 로컬 exclude에 한 번 추가한다.

```bash
printf '%s\n' \
  "$GITHUB_WORK_DIR_EXCLUDE_PATTERN" \
  >> "$GITHUB_PARENT_REPO_ROOT/.git/info/exclude"
```

이 명령은 상위 repository의 commit 대상 `.gitignore`를 바꾸지 않는다. 현재
Mac의 로컬 Git metadata만 바꾸므로 고객 소스나 GitHub history에는 들어가지
않는다.

**검증:** 아직 디렉터리가 없어도 trailing slash를 사용해 로컬 제외 규칙이
정확히 적용되는지 확인한다.

```bash
git -C "$GITHUB_PARENT_REPO_ROOT" \
  check-ignore -v --no-index "${GITHUB_WORK_DIR%/}/"
```

정상이면 `.git/info/exclude`와
`/skt_bamoe_party/bamoe-customer-rule-poc/` 규칙이 함께 출력된다. 아무 출력도
없으면 `mkdir`, `rsync`, `git init`으로 진행하지 않는다. exclude 파일 경로와
규칙의 선행 `/` 및 후행 `/`를 확인한다.

**검증:** 대상 경로가 상위 repository에 이미 tracked된 파일이 아님을 확인한다.

```bash
test -z "$(
  git -C "$GITHUB_PARENT_REPO_ROOT" \
    ls-files -- "$GITHUB_WORK_DIR"
)"
```

정상이면 출력 없이 성공한다. 실패하면 ignore는 이미 tracked된 파일에 적용되지
않으므로 새 repository를 만들기 전에 상위 repository 상태를 별도로 정리해야
한다.

### 6.2 처음 만드는 경우

**목적:** 독립 작업 디렉터리가 없는 최초 실행인지, 이전 작업이 남아 있는
재개 상황인지 명확하게 구분한다.

```bash
if [ ! -e "$GITHUB_WORK_DIR" ]; then
  printf 'GITHUB_WORK_DIR_STATE=ABSENT\n'
else
  printf 'GITHUB_WORK_DIR_STATE=EXISTS\n'
fi
```

- `GITHUB_WORK_DIR_STATE=ABSENT`면 정상적인 최초 실행이다. 아래 §6.2.1 복구
  명령은 실행하지 말고 §6.2.2의 `mkdir`부터 진행한다.
- `GITHUB_WORK_DIR_STATE=EXISTS`면 덮어쓰지 말고 §6.2.1만 수행한다. 디렉터리가
  존재한다는 이유만으로 완성된 repository라고 가정해 §6.3으로 바로 이동하지
  않는다.

#### 6.2.1 대상 디렉터리가 이미 있을 때만 수행하는 중단 복구

이 절 전체는 `GITHUB_WORK_DIR_STATE=EXISTS`일 때만 수행한다.
`GITHUB_WORK_DIR_STATE=ABSENT`인데 아래 `ls`나 `git -C`를 실행하면
`No such file or directory`가 나오는 것이 당연하므로 실행하지 않는다.

이전 실행이 중간에 끊겼다면 대상 디렉터리의 내용을 조회한다.

```bash
ls -la "$GITHUB_WORK_DIR"
```

Git 초기화까지 끝났는지 확인한다.

```bash
test -d "$GITHUB_WORK_DIR/.git"
```

Git repository라면 remote 설정까지 확인한다.

```bash
git -C "$GITHUB_WORK_DIR" remote
```

정상적으로 설정된 경우 remote 이름 `origin`만 출력된다. URL은 legacy
credential이 포함됐을 가능성을 피하기 위해 화면에 표시하지 않는다.

관찰 결과에 따라 다음처럼 재개한다.

- `.git`과 예상한 `origin`이 모두 있으면 §6.3을 사용한다.
- `.git`은 있지만 `origin`이 없으면 변경 파일을 확인하고 §6.1의 GitHub
  repository 존재 여부를 다시 조회한다. 이름이 비어 있을 때만 §6.2의
  `gh repo create` 단계부터 재개한다.
- 디렉터리만 있고 `.git`이 없다면 `pom.xml`, `src`, `.github`, `deploy`가 모두
  있는지 확인하고 §6.2의 `cd "$GITHUB_WORK_DIR"` 단계부터 재개한다.
- 필수 파일이 빠졌거나 복사 도중 수정한 파일이 있는지 확실하지 않으면 삭제하거나
  `rsync`를 반복하지 말고 원본과 대상의 차이를 먼저 검토한다.

복사 차이는 실제 파일을 바꾸지 않는 dry-run으로 확인할 수 있다.

```bash
rsync -ani \
  --exclude '.git' \
  --exclude '.m2' \
  --exclude 'target' \
  --exclude 'config/settings-bamoe-container.xml' \
  --exclude 'BAMOE_POC_CASE.pdf' \
  --exclude 'src/main/resources/bpmn/Case05CompositeAuthorityProcess.bpmn' \
  --exclude 'src/main/resources/dmn/Case05CompositeAuthority.dmn' \
  --exclude 'src/test/resources/scesim/Case05CompositeAuthorityTest.scesim' \
  --exclude 'mock-server/case05_mock_server.py' \
  "$SOURCE_DIR/" \
  "$GITHUB_WORK_DIR/"
```

출력된 변경 후보가 복사 도중 누락된 파일뿐이고 대상에 별도 편집이 없다는 것을
확인했다면, 바로 아래의 원래 `rsync -a` 명령을 한 번 실행해 복사를 완성하고
누락된 단계부터 계속한다. 자동 삭제나 새 `git init`으로 기존 내용을 덮지 않는다.

#### 6.2.2 최초 작업 디렉터리 생성과 프로젝트 복사

이 절은 `GITHUB_WORK_DIR_STATE=ABSENT`일 때 수행한다. §6.2.1에서 기존
디렉터리가 안전한 미완성 사본이라고 확인한 경우에는 이미 완료한 명령을 반복하지
말고 해당 지점부터 재개한다.

**변경:** 비어 있는 독립 작업 디렉터리를 만든다.

```bash
mkdir -p "$GITHUB_WORK_DIR"
```

**조회:** 방금 만든 대상이 일반 디렉터리인지 확인한다.

```bash
ls -ld "$GITHUB_WORK_DIR"
```

정상이면 디렉터리 한 줄이 출력된다. 권한 오류가 나면 상위 디렉터리의 쓰기 권한과
`GITHUB_WORK_DIR` 오타를 확인한다.

**변경:** build 산출물, 로컬 Maven 설정, 고객 원문 PDF를 제외하고 프로젝트를
복사한다.

```bash
rsync -a \
  --exclude '.git' \
  --exclude '.m2' \
  --exclude 'target' \
  --exclude 'config/settings-bamoe-container.xml' \
  --exclude 'BAMOE_POC_CASE.pdf' \
  --exclude 'src/main/resources/bpmn/Case05CompositeAuthorityProcess.bpmn' \
  --exclude 'src/main/resources/dmn/Case05CompositeAuthority.dmn' \
  --exclude 'src/test/resources/scesim/Case05CompositeAuthorityTest.scesim' \
  --exclude 'mock-server/case05_mock_server.py' \
  "$SOURCE_DIR/" \
  "$GITHUB_WORK_DIR/"
```

정상이면 오류 없이 prompt로 돌아온다. 실패하면 목적지에서 Git 초기화를 하지 말고
원본 경로, 디스크 공간, 파일 권한을 먼저 확인한다.

**조회:** 복사된 최상위 파일을 관찰한다.

```bash
ls -la "$GITHUB_WORK_DIR"
```

`pom.xml`, `src`, `.github`, `deploy`가 보여야 하며 `.git`, `.m2`, `target`,
`BAMOE_POC_CASE.pdf`는 없어야 한다.

**검증:** 이번 배포 범위에서 제외한 Case 05 실행 초안이 복사되지 않았는지
파일 이름으로 확인한다.

```bash
find \
  "$GITHUB_WORK_DIR/src/main/resources" \
  "$GITHUB_WORK_DIR/src/test/resources" \
  "$GITHUB_WORK_DIR/mock-server" \
  -type f \
  \( -name 'Case05*' -o -name 'case05*' \) \
  -print
```

정상은 아무 출력도 없는 상태다. 파일이 보이면 Git 초기화 전에 복사 옵션을
확인한다.

**로컬 준비:** 이후 Git 명령의 기준 디렉터리로 이동한다.

```bash
cd "$GITHUB_WORK_DIR"
```

`pwd`로 현재 위치를 확인할 수 있다.

```bash
pwd
```

출력이 `GITHUB_WORK_DIR`와 달라 보이면 다음 명령으로 진행하지 않는다.

**변경:** 독립 repository를 `main` branch로 초기화한다.

```bash
git init -b main
```

**조회:** 아직 remote가 없는 새 repository인지 확인한다.

```bash
git status --short --branch
```

정상이면 첫 줄에 `No commits yet on main`에 해당하는 상태가 보인다. 상위
repository branch가 보이면 잘못된 디렉터리에서 실행한 것이므로 중단한다.

**검증:** 현재 repository root가 새 BAMOE 작업 사본인지 확인한다.

```bash
git rev-parse --show-toplevel
```

정상 출력은
`/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/bamoe-customer-rule-poc`
다. `/Users/jihunkeom/Desktop/projects/2026/SKT`가 나오면 새 repository
초기화가 완료되지 않은 것이므로 다음 단계로 진행하지 않는다.

**검증:** 상위 repository에서는 새 작업 사본 전체가 계속 제외되는지 확인한다.

```bash
git -C "$GITHUB_PARENT_REPO_ROOT" \
  status --short -- "$GITHUB_WORK_DIR"
```

정상은 아무 출력도 없는 상태다. `??` 또는 다른 변경 표시가 나오면 내부
repository를 stage하지 말고 §6.1의 로컬 exclude Gate를 다시 확인한다.

**검증:** 로컬 전용 Maven 설정이 복사되지 않았는지 확인한다.

```bash
test ! -e config/settings-bamoe-container.xml
```

**검증:** 고객 원문 PDF가 복사되지 않았는지 확인한다.

```bash
test ! -e BAMOE_POC_CASE.pdf
```

**검증:** 로컬 Maven cache가 복사되지 않았는지 확인한다.

```bash
test ! -e .m2
```

**검증:** 기존 build 산출물이 복사되지 않았는지 확인한다.

```bash
test ! -e target
```

위 네 명령은 모두 출력 없이 성공해야 한다. 하나라도 실패하면 `git add`를 실행하지
말고 해당 파일이 왜 복사됐는지 먼저 해결한다.

**조회:** 나중에 같은 이름의 파일이 생겨도 Git이 제외하도록 `.gitignore` 규칙을
확인한다.

```bash
git check-ignore \
  --no-index \
  -v \
  BAMOE_POC_CASE.pdf \
  config/settings-bamoe-container.xml
```

정상이면 두 경로와 이를 제외한 `.gitignore` 줄이 출력된다. 아무것도 출력되지
않으면 `.gitignore`를 확인한 뒤 진행한다.

**조회:** 첫 commit 후보를 stage하기 전에 사람이 검토한다.

```bash
git status --short
```

고객 PDF, `.m2`, `target`, `settings-bamoe-container.xml`이 보이면 중단한다.

**변경:** 검토한 현재 PoC 구성요소만 첫 commit 대상으로 stage한다. 아래처럼
경로를 명시하면 새로 생긴 임시 파일까지 포괄하는 `git add .`보다 대상이
분명하다.

```bash
git add -- \
  .bamoe \
  .dockerignore \
  .github \
  .gitignore \
  .kie-sandbox \
  Containerfile \
  GUIDE-VERSIONS.md \
  OPENSHIFT-DEPLOYMENT-GUIDE.md \
  README.md \
  case-00-environment-setup.md \
  case-01-process-service-status-change.md \
  case-02-service-name-change-authority.md \
  case-03-mms-origin-number-authority.md \
  case-04-csmaux004-005-fallback.md \
  case-05-csmaux006-007-composite.md \
  case-06-wireline-suspension.md \
  compose.bamoe-dev.yaml \
  config/settings-bamoe-ci.xml \
  config/settings-bamoe-openshift.xml \
  deploy \
  fact-ready-dmn \
  mock-server \
  pom.xml \
  src
```

**조회:** stage된 파일 이름만 확인한다. 파일 내용이나 Secret 값을 화면에
출력하지 않는다.

```bash
git diff --cached --name-status
```

위 제외 대상이 한 줄이라도 보이면 `git commit`을 실행하지 않는다. 이 repository에는
token, kubeconfig, GitHub PAT를 파일로 저장하지 않는다.

**검증:** 알려진 로컬 전용·자격증명 파일 이름이 stage 목록에 없는지 한 번 더
검사한다.

```bash
git diff --cached --name-only | rg '(^|/)(BAMOE_POC_CASE\.pdf|settings-bamoe-container\.xml|\.m2($|/)|target($|/)|kubeconfig$|[^/]*\.(pem|key|p12)$)'
```

정상일 때는 아무것도 출력되지 않고 `rg`의 종료 코드는 `1`이다. 파일명이
출력되면 commit하지 말고 정확한 경로를 `git restore --staged -- <경로>`로
stage에서 제외한다. 파일 내용을 terminal에 출력할 필요는 없다.

**검증:** whitespace 오류처럼 명백한 patch 문제를 확인한다.

```bash
git diff --cached --check
```

정상이면 출력 없이 성공한다. 오류가 있으면 표시된 파일을 수정한 후 다시 stage한다.

**변경:** 검토가 끝난 파일로 첫 commit을 만든다.

```bash
git commit -m 'Initial BAMOE customer rule PoC'
```

**조회:** 생성된 commit과 branch를 확인한다.

```bash
git show \
  --no-patch \
  --format='commit=%H%nsubject=%s'
```

40자리 commit SHA와 예상 subject가 보여야 한다. branch는 앞의
`git status --short --branch`에서 `main`으로 확인한다. Git 사용자 정보 오류가
나면 작성자 이름과 이메일을 설정한 뒤 commit만 다시 실행한다.

**변경:** 빈 README를 추가하지 않고 현재 작업 사본을 기준으로 private GitHub
repository와 `origin` remote를 만든다. 아직 push하지 않는다.

```bash
gh repo create "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --private \
  --source=. \
  --remote=origin
```

**조회:** remote repository의 소유자, private 여부, URL을 확인한다.

```bash
gh repo view "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --json nameWithOwner,isPrivate,url
```

`nameWithOwner`가 예상값이고 `isPrivate`가 `true`여야 한다. 이미 존재한다는 오류가
나면 `origin`이 생겼다고 가정하지 않는다. §6.1의 repository 존재 여부 분기로
돌아가 기존 작업 사본을 사용할지 새 repository 이름을 사용할지 먼저 정한다.

**변경:** 첫 push가 image build만 수행하도록 자동 OCP 배포를 명시적으로 끈다.

```bash
gh variable set OCP_AUTO_DEPLOY \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --body false
```

**조회:** Actions variable은 Secret이 아니므로 값을 읽어 상태를 확인한다.

```bash
gh variable get OCP_AUTO_DEPLOY \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

정상 출력은 `false`다. 다른 값이거나 조회가 실패하면 첫 push를 하지 않는다.

**변경:** `main`의 첫 commit을 push해 build workflow를 시작한다.

```bash
git push --set-upstream origin main
```

**조회:** 로컬 `main`과 `origin/main`이 연결되고 작업 사본이 깨끗한지 확인한다.

```bash
git status --short --branch
```

정상이면 `main...origin/main`이 표시되고 추가 변경 파일은 없다. push가 거절되면
remote URL과 GitHub 계정 권한을 확인하고 강제 push는 하지 않는다.

### 6.3 기존 repository를 이어서 쓰는 경우

이미 독립 작업 사본과 remote repository가 있다면 다시 복사하거나 `git init`하지
않는다.

**로컬 준비:** 기존 독립 작업 사본으로 이동한다.

```bash
cd "$GITHUB_WORK_DIR"
```

**조회:** 현재 작업 사본이 연결된 GitHub repository의 identity가 의도한
owner/name인지 값 노출 없이 검증한다.

```bash
test "$(gh repo view --json nameWithOwner --jq '.nameWithOwner')" = "${GITHUB_OWNER}/${GITHUB_REPO}"
```

정상이면 출력 없이 성공한다. HTTPS와 SSH 중 어떤 protocol을 쓰든 repository
identity만 비교하므로 URL이나 legacy credential을 화면에 표시하지 않는다.

**조회:** 현재 branch와 미반영 변경을 확인한다.

```bash
git status --short --branch
```

현재 branch가 `main`이어야 한다. 예상하지 못한 변경이 있으면 보존한 채 먼저
내용을 확인하고, 덮어쓰거나 초기화하지 않는다.

**조회:** remote repository가 private인지 다시 확인한다.

```bash
gh repo view "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --json nameWithOwner,isPrivate,url
```

`isPrivate: true`가 아니면 고객 자산을 push하지 않는다.

**조회:** remote의 최신 `main` 상태를 가져오되 작업 파일은 바꾸지 않는다.

```bash
git fetch origin
```

**조회:** fetch 후 local `main`이 ahead, behind, diverged 중 어느 상태인지
확인한다.

```bash
git status --short --branch
```

`behind`이면서 작업 사본이 깨끗할 때에만 fast-forward한다.

```bash
git pull --ff-only origin main
```

`diverged`이거나 미확인 변경이 있으면 push하지 말고 commit 관계와 변경 소유자를
먼저 확인한다. 강제 push나 reset으로 해결하지 않는다.

**검증:** 기존 작업 사본에 현재 PoC의 build workflow가 있는지 확인한다.

```bash
test -f .github/workflows/build-images.yml
```

**검증:** 최초 배포에 필요한 PAMOE overlay가 있는지 확인한다.

```bash
test -f deploy/openshift/overlays/pamoe/kustomization.yaml
```

**검증:** OCP Route와 최소 권한 manifest가 있는지 확인한다.

```bash
test -f deploy/openshift/route.yaml
```

**검증:** Dev 제품 직접 배포 Kustomization을 확인한다.

```bash
test -f deploy/openshift/products/dev/kustomization.yaml
```

**검증:** Runtime 제품 직접 배포 Kustomization도 확인한다.

```bash
test -f deploy/openshift/products/runtime/kustomization.yaml
```

**검증:** Canvas의 OpenShift 사용자 정의 배포와 전용 Maven 설정도 확인한다.

```bash
test -f .bamoe/dev-deployments/openshift/option.json
```

```bash
test -f config/settings-bamoe-openshift.xml
```

**검증:** 파일 이름만 존재하는 것이 아니라 두 제품 묶음이 실제로 조립되는지
확인한다. 출력은 버리는 로컬 검증이며 cluster는 바뀌지 않는다.

```bash
kustomize build deploy/openshift/products/dev >/dev/null
```

```bash
kustomize build deploy/openshift/products/runtime >/dev/null
```

**검증:** 조립만 되는 오래된 제품 YAML도 통과시키지 않도록 image 전체 목록을
확인한다.

```bash
test "$(
  kustomize build deploy/openshift/products/dev \
    | awk '
        $1 == "image:" {print $2}
        $1 == "-" && $2 == "image:" {print $3}
      ' \
    | sort -u
)" = "$(
  printf '%s\n' \
    'quay.io/bamoe/canvas:9.5.0-ibm-0005' \
    'quay.io/bamoe/cors-proxy:9.5.0-ibm-0005' \
    'quay.io/bamoe/extended-services:9.5.0-ibm-0005' \
    'quay.io/bamoe/maven-repository:9.5.0-ibm-0005' \
    | sort -u
)"
```

```bash
test "$(
  kustomize build deploy/openshift/products/runtime \
    | awk '
        $1 == "image:" {print $2}
        $1 == "-" && $2 == "image:" {print $3}
      ' \
    | sort -u
)" = "$(
  printf '%s\n' \
    'quay.io/bamoe/management-console:9.5.0-ibm-0005' \
    'quay.io/bamoe/mcp-server:9.5.0-ibm-0005' \
    | sort -u
)"
```

**검증:** Canvas 사용자 정의 옵션도 현재 image와 OpenShift Maven 설정을
가리키는지 확인한다.

```bash
jq -e '
  .name == "OpenShift Spring Boot PoC"
  and .parameters.containerImage.defaultValue
    == "quay.io/bamoe/canvas-dev-deployment-base:9.5.0-ibm-0005-jdk21"
  and (
    .parameters.command.defaultValue
    | startswith("./mvnw --settings config/settings-bamoe-openshift.xml ")
  )
' .bamoe/dev-deployments/openshift/option.json
```

열두 검증 중 하나라도 실패하면 기존 repository가 현재 PoC 구조보다 오래된 것이다.
`SOURCE_DIR`를 통째로 덮어쓰지 말고 다음 dry-run으로 파일 차이를 먼저 읽는다.

```bash
rsync -ani \
  --exclude '.git' \
  --exclude '.m2' \
  --exclude 'target' \
  --exclude 'config/settings-bamoe-container.xml' \
  --exclude 'BAMOE_POC_CASE.pdf' \
  --exclude 'src/main/resources/bpmn/Case05CompositeAuthorityProcess.bpmn' \
  --exclude 'src/main/resources/dmn/Case05CompositeAuthority.dmn' \
  --exclude 'src/test/resources/scesim/Case05CompositeAuthorityTest.scesim' \
  --exclude 'mock-server/case05_mock_server.py' \
  "$SOURCE_DIR/" \
  "$GITHUB_WORK_DIR/"
```

필요한 변경만 Git diff로 검토해 별도 commit으로 반영한다. 기존 GitHub 작업 사본은
§6 이후의 기준 원본이므로 자동 `rsync -a`로 덮어쓰지 않는다.

**검증:** 기존 repository에도 이번 01~04 배포 범위 밖의 Case 05 실행 초안이
남아 있지 않은지 확인한다.

```bash
find \
  src/main/resources \
  src/test/resources \
  mock-server \
  -type f \
  \( -name 'Case05*' -o -name 'case05*' \) \
  -print
```

정상은 아무 출력도 없는 상태다. 파일이 보이면 자동 삭제하거나 push하지 않는다.
현재 branch에서 초안을 보존할지, 별도 branch로 옮길지 결정한 뒤 이번 배포
작업 사본에서는 제외된 상태를 사람이 검토한다.

**변경:** bootstrap이 끝나기 전에는 자동 배포를 항상 끈 상태로 둔다.

```bash
gh variable set OCP_AUTO_DEPLOY \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --body false
```

**조회:** 값이 실제로 `false`인지 확인한다.

```bash
gh variable get OCP_AUTO_DEPLOY \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

**변경:** 현재 `main`의 commit을 remote에 반영한다.

```bash
git push --set-upstream origin main
```

이미 반영된 상태라면 `Everything up-to-date`가 정상이다. 새 commit이 push되면
§7에서 그 commit에 대응하는 run을 식별한다.

**조회:** push 후 `main`과 `origin/main`의 추적 상태를 확인한다.

```bash
git status --short --branch
```

정상이면 두 branch가 일치하며 예상하지 못한 작업 파일이 없다.

**Gate**

- `gh repo view`의 `isPrivate`가 `true`다.
- 고객 PDF, 로컬 Maven 설정, `.m2`, `target`이 commit 대상에 없다.
- 이번 bootstrap image에 Case 05 실행 초안이 포함되지 않는다.
- 현재 branch가 `main`이고 `origin/main`을 추적한다.
- 첫 push 전에 `OCP_AUTO_DEPLOY`가 `false`로 확인됐다.
- token, kubeconfig, PAT를 파일이나 명령 출력으로 노출하지 않았다.

## 7. 첫 GitHub Actions build와 GHCR pull

첫 push는 `.github/workflows/build-images.yml`을 실행한다. 여기서는 “가장 최근
run”을 막연히 기다리지 않고, **현재 commit SHA와 일치하는 run을 사람이 직접
식별한 뒤 그 run ID만 watch**한다.

### 7.1 bootstrap commit SHA 기록

**로컬 준비:** 독립 작업 사본으로 이동한다.

```bash
cd "$GITHUB_WORK_DIR"
```

**조회:** image tag의 기준이 될 현재 commit SHA를 출력한다.

```bash
git rev-parse HEAD
```

출력된 40자리 값을 안전하게 복사한다. 이 값은 Secret이 아니며 build, image,
bootstrap Deployment가 같은 소스를 가리키는 계약이다.

**로컬 준비:** 아래 예시 값을 방금 본 40자리 SHA로 직접 바꿔 현재 terminal에
기록한다. 작은따옴표 안에 설명 문구를 그대로 두지 않는다.

```bash
export BOOTSTRAP_SHA='여기에-방금-확인한-40자리-commit-SHA'
```

**검증:** 입력한 SHA가 현재 `main` commit을 실제로 가리키는지 확인한다.

```bash
git show \
  --no-patch \
  --format='commit=%H%nsubject=%s' \
  "$BOOTSTRAP_SHA"
```

`commit=` 뒤의 값이 `BOOTSTRAP_SHA`와 글자 단위로 같아야 한다. `bad object`가
나오면 값을 다시 복사한다.

**검증:** 사람이 눈으로 비교하는 데서 끝내지 않고, 40자리 형식·현재
`main`·`origin/main`을 한 번에 검사한다.

```bash
if printf '%s\n' "$BOOTSTRAP_SHA" \
    | rg -q -x '[0-9a-f]{40}' \
  && [ "$(git branch --show-current)" = 'main' ] \
  && [ "$(git rev-parse HEAD)" = "$BOOTSTRAP_SHA" ] \
  && [ "$(git rev-parse origin/main)" = "$BOOTSTRAP_SHA" ]
then
  printf 'BOOTSTRAP_SHA_GATE=PASS\n'
else
  printf 'BOOTSTRAP_SHA_GATE=FAIL\n' >&2
fi
```

정상 출력은 `BOOTSTRAP_SHA_GATE=PASS`다. 실패하면 run이나 image를 선택하지 않는다.

### 7.2 해당 SHA의 Actions run을 수동으로 식별하고 watch

**조회:** 현재 SHA로 시작된 workflow run만 나열한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --commit "$BOOTSTRAP_SHA" \
  --limit 5 \
  --json databaseId,headSha,status,conclusion,event,createdAt
```

정상이면 `headSha`가 `BOOTSTRAP_SHA`와 같은 항목이 하나 보인다. 첫 push 직후라
빈 배열 `[]`이면 자동 loop를 만들지 말고 잠시 뒤 이 조회 명령을 사람이 다시
실행한다. 다른 SHA의 run ID를 사용하지 않는다.

**로컬 준비:** 위 출력의 `databaseId`를 직접 복사한다.

```bash
export BUILD_RUN_ID='여기에-databaseId-숫자'
```

**조회:** watch하기 전에 선택한 run의 SHA와 현재 상태를 한 번 더 확인한다.

```bash
gh run view "$BUILD_RUN_ID" \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --json databaseId,headSha,status,conclusion,url
```

`headSha`가 `BOOTSTRAP_SHA`와 다르면 중단하고 run 목록에서 올바른 ID를 다시
고른다.

**검증:** 선택한 run ID가 숫자이고 실제 `headSha`가 bootstrap SHA인지
기계적으로 확인한다.

```bash
SELECTED_RUN_HEAD="$(
  gh run view "$BUILD_RUN_ID" \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --json headSha \
    --jq '.headSha'
)"

if printf '%s\n' "$BUILD_RUN_ID" | rg -q -x '[0-9]+' \
  && [ "$SELECTED_RUN_HEAD" = "$BOOTSTRAP_SHA" ]
then
  printf 'BUILD_RUN_IDENTITY_GATE=PASS\n'
else
  printf 'BUILD_RUN_IDENTITY_GATE=FAIL\n' >&2
fi
```

`BUILD_RUN_IDENTITY_GATE=PASS`가 아니면 `gh run watch`를 실행하지 않는다.

**대기:** 사람이 식별한 정확한 run 하나가 끝날 때까지 GitHub의 진행 상태를
watch한다.

```bash
gh run watch "$BUILD_RUN_ID" \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --exit-status
```

정상이면 명령이 종료 코드 `0`으로 끝난다. 이 watch는 run을 찾기 위한 polling이
아니라, 이미 확인한 run ID 하나의 완료를 관찰하는 단계다.

**조회:** 완료된 run의 commit과 각 job 결론을 확인한다.

```bash
gh run view "$BUILD_RUN_ID" \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --json headSha,status,conclusion,jobs,url \
  --jq '{headSha,status,conclusion,jobs:[.jobs[]|{name,status,conclusion}],url}'
```

정상 상태는 다음과 같다.

- 최상위 `headSha`가 `BOOTSTRAP_SHA`와 정확히 같다.
- build job은 `success`다.
- deploy job은 `skipped`다. §6에서 `OCP_AUTO_DEPLOY=false`로 설정했기 때문이다.

완료 상태, workflow/event identity, build 성공과 deploy skip을 같은 run ID에서
기계적으로 확인한다.

```bash
COMPLETED_RUN_JSON="$(
  gh run view "$BUILD_RUN_ID" \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --json headSha,status,conclusion,event,workflowName,jobs,url
)"

if printf '%s\n' "$COMPLETED_RUN_JSON" \
  | jq -e \
      --arg sha "$BOOTSTRAP_SHA" \
      '
        .headSha == $sha
        and .status == "completed"
        and .conclusion == "success"
        and .event == "push"
        and .workflowName == "Build and publish PoC images"
        and (
          [.jobs[] | select(.name == "build" and .conclusion == "success")]
          | length
        ) == 1
        and (
          [
            .jobs[]
            | select(
                .name == "Deploy immutable images to OpenShift"
                and .conclusion == "skipped"
              )
          ]
          | length
        ) == 1
      ' \
    >/dev/null
then
  printf 'BUILD_RUN_COMPLETION_GATE=PASS\n'
else
  printf 'BUILD_RUN_COMPLETION_GATE=FAIL\n' >&2
fi
```

`PASS`가 아니면 image pull 단계로 이동하지 않는다.

실패한 job이 있으면 Secret을 출력하지 않고 실패 로그만 조회한다.

```bash
gh run view "$BUILD_RUN_ID" \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --log-failed
```

workflow의 build job은 다음 순서로 동작한다.

1. BAMOE Maven Repository service 시작
2. SCESIM을 포함한 `mvn clean verify`
3. 앱과 Mock을 `linux/amd64` image로 build
4. 두 image에 `latest`와 `sha-${BOOTSTRAP_SHA}` tag를 붙여 GHCR에 push

현재 두 `Containerfile`의 UBI base는 `:latest`이므로 같은 commit의 workflow를
나중에 다시 실행하면 base content가 달라질 수 있고 SHA tag도 갱신될 수 있다.
따라서 SHA **tag만** immutable하다고 표현하지 않는다. 이 가이드는 worker가 실제
pull한 digest를 추출해 `tag@digest`로 Deployment를 고정한다. 운영 전환 전에는
지원되는 UBI base digest와 GitHub Action commit SHA까지 별도 승인·고정한다.
같은 40자리 SHA는 같은 source commit만 뜻하며 같은 workflow 실행까지 식별하지는
않는다. 이번 PoC에서는 한 bootstrap run을 선택한 뒤 같은 SHA를 재실행하거나
서로 다른 rerun의 앱/Mock digest를 섞지 않는다. 엄밀한 provenance가 필요하면
workflow run ID를 OCI provenance와 두 Deployment annotation에 함께 기록해
검증한다.
5. 각 image digest를 deploy job output으로 전달

build가 실패했다면 아래 GHCR Secret 단계로 넘어가지 않는다.

### 7.3 private GHCR pull Secret

GitHub에서 이 repository의 private container package를 읽을 전용 Personal
Access Token(classic)을 만든다. scope 기준은
[GitHub Container registry 인증 문서](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)를
따른다.

- scope는 `read:packages`만 사용한다.
- 조직이 SSO를 사용한다면 해당 token의 SSO 승인이 필요할 수 있다.
- Canvas가 private Git repository를 읽을 때 사용할 token과 분리한다.
- token을 파일, GitHub variable, 채팅, shell 명령의 literal 값으로 기록하지 않는다.

**로컬 준비:** token 입력 prompt만 먼저 표시한다.

```bash
printf 'GHCR read token: '
```

**로컬 준비:** Bash와 zsh 모두에서 token을 화면에 표시하지 않고
`GHCR_TOKEN` 변수로 읽는다. 입력 후 Enter를 누른다.

```bash
IFS= read -r -s GHCR_TOKEN
```

**로컬 준비:** 숨김 입력 뒤 prompt 줄을 정리한다. token 값은 출력하지 않는다.

```bash
printf '\n'
```

**로컬 준비:** 다른 Docker 로그인 설정과 섞이지 않는 권한 제한 임시 디렉터리를
만든다.

```bash
export GHCR_DOCKER_CONFIG_DIR="$(mktemp -d /tmp/bamoe-ghcr-login.XXXXXX)"
```

정상이면 `/tmp/bamoe-ghcr-login.`으로 시작하는 새 경로가 변수에 저장된다.

**로컬 준비:** token을 프로세스 인자에 넣지 않고 표준 입력으로 Docker에
전달한다. Docker는 Secret 생성에 필요한 설정을 방금 만든 임시 디렉터리에만
저장한다.

```bash
if printf '%s' "$GHCR_TOKEN" \
  | docker \
      --config "$GHCR_DOCKER_CONFIG_DIR" \
      login ghcr.io \
      --username "$GITHUB_OWNER" \
      --password-stdin
then
  printf 'GHCR_LOGIN_GATE=PASS\n'
else
  printf 'GHCR_LOGIN_GATE=FAIL\n' >&2
fi
```

정상 출력은 `Login Succeeded`와 `GHCR_LOGIN_GATE=PASS`다. `FAIL`이면 Secret을
만들지 말고 이 절 아래의 **통합 정리 블록**을 먼저 실행한 뒤 새 임시 디렉터리와
token으로 다시 시작한다. 임시 `config.json`에는 암호화되지 않은 인증 정보가
들어 있으므로 내용을 열거나 공유하지 않는다.

**정리:** 로그인 성공 여부와 관계없이 terminal memory의 token 변수를 즉시
제거한다.

```bash
unset GHCR_TOKEN
```

**검증:** 임시 Docker 설정 파일이 생성됐고 비어 있지 않은지만 확인한다.

```bash
case "${GHCR_DOCKER_CONFIG_DIR:-}" in
  /tmp/bamoe-ghcr-login.*)
    if [ -s "$GHCR_DOCKER_CONFIG_DIR/config.json" ]; then
      printf 'GHCR_CONFIG_GATE=PASS\n'
    else
      printf 'GHCR_CONFIG_GATE=FAIL (config.json missing or empty)\n' >&2
    fi
    ;;
  *)
    printf 'GHCR_CONFIG_GATE=FAIL (unexpected temporary path)\n' >&2
    ;;
esac
```

`GHCR_CONFIG_GATE=PASS`여야 한다. 실패하면 Secret을 만들지 말고 아래 통합 정리
블록을 실행한 뒤 Docker login부터 다시 수행한다.

**변경:** 검증한 임시 Docker 설정으로 `bamoe-poc`에 registry Secret을 처음
생성한다.

```bash
case "${GHCR_DOCKER_CONFIG_DIR:-}" in
  /tmp/bamoe-ghcr-login.*)
    if [ -s "$GHCR_DOCKER_CONFIG_DIR/config.json" ]; then
      oc create secret generic ghcr-pull \
        -n "$APP_NS" \
        --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson="$GHCR_DOCKER_CONFIG_DIR/config.json"
    else
      printf 'REFUSE: validated GHCR config.json is missing\n' >&2
    fi
    ;;
  *)
    printf 'REFUSE: unexpected GHCR temporary path\n' >&2
    ;;
esac
```

정상이면 `secret/ghcr-pull created`가 보인다. `AlreadyExists`이면 기존 Secret
본문을 출력하지 말고 §7.4의 pull test로 먼저 유효성을 확인한다. 교체가 꼭
필요하면 대상과 복구 방법을 정한 뒤 별도의 자격증명 회전 작업으로 수행한다.
Secret 생성의 성공 여부와 관계없이 다음 두 정리 명령은 수행한다.

**통합 정리:** 검증과 삭제를 서로 다른 명령으로 나누지 않는다. 아래 한 블록은
변수가 이번 절에서 만든 `/tmp` 하위 디렉터리이고 대상이 일반 파일일 때만
`config.json`을 지운다. 조건이 하나라도 다르면 삭제 명령 자체가 실행되지 않는다.

```bash
case "${GHCR_DOCKER_CONFIG_DIR:-}" in
  /tmp/bamoe-ghcr-login.*)
    if [ -f "$GHCR_DOCKER_CONFIG_DIR/config.json" ]; then
      if unlink "$GHCR_DOCKER_CONFIG_DIR/config.json" \
        && rmdir "$GHCR_DOCKER_CONFIG_DIR"
      then
        unset GHCR_DOCKER_CONFIG_DIR
        printf 'GHCR_TEMP_CLEANUP_GATE=PASS\n'
      else
        printf 'GHCR_TEMP_CLEANUP_GATE=FAIL (directory not empty or removal failed)\n' >&2
      fi
    elif [ -d "$GHCR_DOCKER_CONFIG_DIR" ]; then
      if rmdir "$GHCR_DOCKER_CONFIG_DIR"; then
        unset GHCR_DOCKER_CONFIG_DIR
        printf 'GHCR_TEMP_CLEANUP_GATE=PASS (no config file remained)\n'
      else
        printf 'GHCR_TEMP_CLEANUP_GATE=FAIL (unexpected files remain)\n' >&2
      fi
    else
      printf 'GHCR_TEMP_CLEANUP_GATE=FAIL (temporary directory is missing)\n' >&2
    fi
    ;;
  *)
    printf 'REFUSE: unexpected or empty GHCR temporary path\n' >&2
    ;;
esac
```

정상 출력은 `GHCR_TEMP_CLEANUP_GATE=PASS`다. `FAIL` 또는 `REFUSE`이면 경로를
출력해 공유하지 말고, 해당 임시 디렉터리의 파일 이름만 확인해 수동으로 정리한다.

**조회:** Secret 값은 열지 않고 이름과 type만 확인한다.

```bash
oc get secret ghcr-pull \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,TYPE:.type'
```

정상 type은 `kubernetes.io/dockerconfigjson`이다. `-o yaml`, `-o json` 또는
`.data` jsonpath로 Secret 본문을 출력하지 않는다.

### 7.4 두 private image를 worker에서 직접 pull

**로컬 준비:** worker pull 확인에 사용할 앱 SHA tag reference를 만든다. SHA tag는
commit 식별에는 유용하지만 registry에서 다시 push할 수 있으므로 아직 불변
reference는 아니다.

```bash
export APP_IMAGE="ghcr.io/${GITHUB_OWNER}/customer-rule-poc:sha-${BOOTSTRAP_SHA}"
```

**로컬 준비:** Mock image도 같은 commit SHA tag를 사용한다.

```bash
export MOCK_IMAGE="ghcr.io/${GITHUB_OWNER}/customer-rule-mock:sha-${BOOTSTRAP_SHA}"
```

먼저 앱 image를 확인한다.

**정리:** 이전 실습에서 남은 동일 이름의 앱 pull-test Pod만 제거한다.

```bash
oc delete pod ghcr-pull-test-app \
  -n "$APP_NS" \
  --ignore-not-found
```

**조회:** 같은 이름의 Pod가 남지 않았는지 확인한다. 출력이 없는 것이 정상이다.

```bash
oc get pod ghcr-pull-test-app \
  -n "$APP_NS" \
  --ignore-not-found
```

**변경:** `ghcr-pull`을 명시한 일회성 앱 image 확인 Pod를 만든다.

```bash
oc run ghcr-pull-test-app \
  -n "$APP_NS" \
  --image="$APP_IMAGE" \
  --restart=Never \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"ghcr-pull"}]}}'
```

**조회:** Pod 상태와 요청한 image를 관찰한다.

```bash
oc get pod ghcr-pull-test-app \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image'
```

처음에는 `Pending`일 수 있다. 자동 polling 명령을 만들지 말고 위 조회를 직접
다시 실행해 `PHASE=Running`, `READY=true`, `IMAGE=$APP_IMAGE`가 될 때까지
관찰한다.

**조회:** pull된 실제 content digest를 변수에 저장한다.

```bash
export APP_IMAGE_ID="$(
  oc get pod ghcr-pull-test-app \
    -n "$APP_NS" \
    -o jsonpath='{.status.containerStatuses[0].imageID}'
)"

printf 'APP_IMAGE_ID=%s\n' "$APP_IMAGE_ID"
```

정상이면 `sha256:` digest가 출력된다. `ImagePullBackOff` 또는 `ErrImagePull`이면
다음 두 조회로 Secret 이름, tag 존재 여부, registry 연결 오류를 확인한다.

```bash
oc describe pod ghcr-pull-test-app \
  -n "$APP_NS"
```

```bash
oc get events \
  -n "$APP_NS" \
  --sort-by=.lastTimestamp
```

앱 pull이 성공한 뒤 Mock image도 별도로 확인한다.

**정리:** 이전 Mock pull-test Pod만 제거한다.

```bash
oc delete pod ghcr-pull-test-mock \
  -n "$APP_NS" \
  --ignore-not-found
```

**조회:** 같은 이름의 Mock test Pod가 남지 않았는지 확인한다. 출력이 없는 것이
정상이다.

```bash
oc get pod ghcr-pull-test-mock \
  -n "$APP_NS" \
  --ignore-not-found
```

**변경:** 같은 Secret으로 Mock SHA image를 pull한다.

```bash
oc run ghcr-pull-test-mock \
  -n "$APP_NS" \
  --image="$MOCK_IMAGE" \
  --restart=Never \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"ghcr-pull"}]}}'
```

**조회:** Mock Pod가 요청한 SHA image로 실행되는지 관찰한다.

```bash
oc get pod ghcr-pull-test-mock \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image'
```

`Pending`이면 이 조회를 사람이 다시 실행한다. 정상은 `Running`, `true`,
`$MOCK_IMAGE`다.

**조회:** Mock image의 실제 content digest도 변수에 저장한다.

```bash
export MOCK_IMAGE_ID="$(
  oc get pod ghcr-pull-test-mock \
    -n "$APP_NS" \
    -o jsonpath='{.status.containerStatuses[0].imageID}'
)"

printf 'MOCK_IMAGE_ID=%s\n' "$MOCK_IMAGE_ID"
```

정상이면 `sha256:` digest가 출력된다. 실패하면 아래 조회로 원인을 확인한다.

```bash
oc describe pod ghcr-pull-test-mock \
  -n "$APP_NS"
```

**로컬 준비:** 두 `imageID`에서 content digest만 추출한다.

```bash
export APP_IMAGE_DIGEST="${APP_IMAGE_ID##*@}"
export MOCK_IMAGE_DIGEST="${MOCK_IMAGE_ID##*@}"
```

**검증:** 두 값이 실제 SHA-256 digest인지 확인한다.

```bash
DIGEST_COUNT="$(
  printf '%s\n%s\n' \
    "$APP_IMAGE_DIGEST" \
    "$MOCK_IMAGE_DIGEST" \
  | rg -c -x 'sha256:[0-9a-f]{64}' \
  || true
)"

if [ "$DIGEST_COUNT" = '2' ]; then
  printf 'IMAGE_DIGEST_GATE=PASS\n'
else
  printf 'IMAGE_DIGEST_GATE=FAIL\n' >&2
fi
```

정상 출력은 `IMAGE_DIGEST_GATE=PASS`다. 실패하면 Pod를 지우기 전에 두
`imageID`를 다시 확인한다.

**로컬 준비:** tag와 digest를 함께 가진 불변 reference로 두 변수를 교체한다.

```bash
export APP_IMAGE="${APP_IMAGE}@${APP_IMAGE_DIGEST}"
export MOCK_IMAGE="${MOCK_IMAGE}@${MOCK_IMAGE_DIGEST}"
```

**검증:** 배포에 사용할 최종 두 reference를 확인한다. digest는 Secret이 아니다.

```bash
printf 'APP_IMAGE=%s\nMOCK_IMAGE=%s\n' "$APP_IMAGE" "$MOCK_IMAGE"
```

두 줄 모두 `:sha-${BOOTSTRAP_SHA}@sha256:<64자리>` 형태여야 한다.

다음 terminal에서도 같은 검증 결과를 재사용할 수 있도록 non-secret reference만
임시 환경파일에 기록한다.

```bash
export BOOTSTRAP_IMAGE_ENV="/tmp/bamoe-bootstrap-images-${BOOTSTRAP_SHA}.env"
```

동일 경로를 덮어쓰지 않고 새 파일일 때만 기록한다.

```bash
if [ ! -e "$BOOTSTRAP_IMAGE_ENV" ]; then
  {
    printf "export BOOTSTRAP_SHA='%s'\n" "$BOOTSTRAP_SHA"
    printf "export BUILD_RUN_ID='%s'\n" "$BUILD_RUN_ID"
    printf "export APP_IMAGE='%s'\n" "$APP_IMAGE"
    printf "export MOCK_IMAGE='%s'\n" "$MOCK_IMAGE"
  } > "$BOOTSTRAP_IMAGE_ENV"
  chmod 600 "$BOOTSTRAP_IMAGE_ENV"
  printf 'BOOTSTRAP_IMAGE_ENV=%s\n' "$BOOTSTRAP_IMAGE_ENV"
else
  printf 'REFUSE: bootstrap image environment file already exists\n' >&2
fi
```

출력된 정확한 `BOOTSTRAP_IMAGE_ENV` 경로를 기록한다. 이 파일에는 token은 없지만
이번 배포 provenance가 있으므로 bootstrap 완료 후 §8의 정리 절차에서 제거한다.

**정리:** 검증을 마친 앱 test Pod를 삭제한다.

```bash
oc delete pod ghcr-pull-test-app \
  -n "$APP_NS"
```

**정리:** 검증을 마친 Mock test Pod를 삭제한다.

```bash
oc delete pod ghcr-pull-test-mock \
  -n "$APP_NS"
```

**조회:** 두 임시 Pod가 모두 없어졌는지 확인한다. 출력이 없는 것이 정상이다.

```bash
oc get pod ghcr-pull-test-app ghcr-pull-test-mock \
  -n "$APP_NS" \
  --ignore-not-found
```

**Gate**

- 선택한 Actions run의 `headSha`가 `BOOTSTRAP_SHA`와 정확히 같다.
- build job은 `success`, deploy job은 `skipped`다.
- 앱과 Mock 모두 `sha-${BOOTSTRAP_SHA}` tag로 worker에서 pull됐다.
- 두 Pod의 `imageID`에서 실제 digest를 추출해 최종 `tag@sha256:...`
  reference를 만들었다.
- `ghcr-pull`의 type만 확인했으며 Secret 본문과 token을 출력하지 않았다.

## 8. 앱과 Mock API 최초 bootstrap

repository의 overlay는 실수로 그대로 배포하지 못하도록
`DO_NOT_APPLY_SET_IMMUTABLE_REF` placeholder를 갖는다. 실제 bootstrap에서는
repository 파일을 수정하지 않는다. 별도의 임시 Kustomize 작업 사본에 **§7에서
성공한 동일 commit의 `tag@digest` reference**를 주입하고, server-side
validation을 통과한 결과만 적용한다.

추천 세션 D를 새 terminal에서 시작했다면 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

namespace와 독립 GitHub 작업 사본 경로를 다시 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

필수 값과 현재 cluster 연결을 검증한다.

```bash
bamoe_check_env
```

같은 terminal에서 §7을 이어서 수행했다면 `BOOTSTRAP_SHA`, `BUILD_RUN_ID`,
`APP_IMAGE`, `MOCK_IMAGE`가 이미 있다. 새 terminal이라면 §7에서 출력된 정확한
임시 환경파일 경로를 기록한다. 아래 예시 문구를 그대로 두지 않는다.

```bash
export BOOTSTRAP_IMAGE_ENV='/tmp/bamoe-bootstrap-images-여기에-40자리-SHA.env'
```

예상 prefix, 일반 파일, 현재 사용자 소유권을 확인한다.

```bash
case "$BOOTSTRAP_IMAGE_ENV" in
  /tmp/bamoe-bootstrap-images-*.env)
    if [ -f "$BOOTSTRAP_IMAGE_ENV" ] && [ -O "$BOOTSTRAP_IMAGE_ENV" ]; then
      printf 'BOOTSTRAP_ENV_FILE_GATE=PASS\n'
    else
      printf 'BOOTSTRAP_ENV_FILE_GATE=FAIL\n' >&2
    fi
    ;;
  *)
    printf 'BOOTSTRAP_ENV_FILE_GATE=FAIL (unexpected path)\n' >&2
    ;;
esac
```

`source`로 임시 파일의 코드를 실행하지 않는다. 고정된 네 key의 작은따옴표 안
값만 `awk`로 읽는다.

```bash
export BOOTSTRAP_SHA="$(
  awk -F"'" '$1 == "export BOOTSTRAP_SHA=" { print $2 }' \
    "$BOOTSTRAP_IMAGE_ENV"
)"
export BUILD_RUN_ID="$(
  awk -F"'" '$1 == "export BUILD_RUN_ID=" { print $2 }' \
    "$BOOTSTRAP_IMAGE_ENV"
)"
export APP_IMAGE="$(
  awk -F"'" '$1 == "export APP_IMAGE=" { print $2 }' \
    "$BOOTSTRAP_IMAGE_ENV"
)"
export MOCK_IMAGE="$(
  awk -F"'" '$1 == "export MOCK_IMAGE=" { print $2 }' \
    "$BOOTSTRAP_IMAGE_ENV"
)"
```

같은 terminal에서 이어온 경우에는 위 복구 세 블록을 건너뛴다.

이 장에서 처음 함께 다루는 리소스의 관계는 다음과 같다.

| 리소스 | 이 PoC에서 하는 일 |
|---|---|
| `Deployment` | 원하는 image와 replica 수를 선언하고 rollout 관리 |
| `ReplicaSet` | Deployment가 요청한 수만큼 Pod 유지 |
| `Pod` | 앱 또는 Mock container가 실제로 실행되는 최소 단위 |
| `Service` | 교체되는 Pod 앞에 고정 DNS 이름과 port 제공 |
| `ConfigMap` | image 밖에서 애플리케이션 설정 전달 |
| `Kustomize overlay` | 공통 base에 PAMOE 설정과 실행 image를 합성 |

따라서 `oc apply`가 성공한 것만으로 완료가 아니다. Deployment가 Pod를 Ready로
만들고 Service가 그 Pod를 endpoint로 선택하는 것까지 관찰해야 한다.

### 8.1 build와 bootstrap SHA 계약 재확인

**로컬 준비:** 독립 작업 사본으로 이동한다.

```bash
cd "$GITHUB_WORK_DIR"
```

**검증:** 현재 `HEAD`, `origin/main`, bootstrap SHA가 같은지 기계적으로
확인한다.

```bash
if [ "$(git rev-parse HEAD)" = "$BOOTSTRAP_SHA" ] \
  && [ "$(git rev-parse origin/main)" = "$BOOTSTRAP_SHA" ]
then
  printf 'BOOTSTRAP_SOURCE_IDENTITY_GATE=PASS\n'
else
  printf 'BOOTSTRAP_SOURCE_IDENTITY_GATE=FAIL\n' >&2
fi
```

정상 출력은 `BOOTSTRAP_SOURCE_IDENTITY_GATE=PASS`다. 실패하면 build 이후 새
commit이 생겼거나 local/remote가 달라진 것이므로 현재 SHA의 workflow를 다시
성공시키기 전에는 배포하지 않는다.

**조회:** §7에서 선택한 run이 정말 성공했고 같은 SHA인지 다시 확인한다.

```bash
gh run view "$BUILD_RUN_ID" \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --json headSha,status,conclusion,url
```

`headSha=$BOOTSTRAP_SHA`, `status=completed`, `conclusion=success`여야 한다. terminal을
새로 열어 변수가 사라졌다면 §7.1과 §7.2의 수동 조회·입력 절차를 반복한다.

workflow/event identity와 두 job 결론까지 같은 run에서 다시 읽어 자동 Gate로
확인한다.

```bash
BOOTSTRAP_RUN_JSON="$(
  gh run view "$BUILD_RUN_ID" \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --json headSha,status,conclusion,event,workflowName,jobs,url
)"

if printf '%s\n' "$BOOTSTRAP_RUN_JSON" \
  | jq -e \
      --arg sha "$BOOTSTRAP_SHA" \
      '
        .headSha == $sha
        and .status == "completed"
        and .conclusion == "success"
        and .event == "push"
        and .workflowName == "Build and publish PoC images"
        and (
          [.jobs[] | select(.name == "build" and .conclusion == "success")]
          | length
        ) == 1
        and (
          [
            .jobs[]
            | select(
                .name == "Deploy immutable images to OpenShift"
                and .conclusion == "skipped"
              )
          ]
          | length
        ) == 1
      ' \
    >/dev/null
then
  printf 'BOOTSTRAP_RUN_GATE=PASS\n'
else
  printf 'BOOTSTRAP_RUN_GATE=FAIL\n' >&2
fi
```

`BOOTSTRAP_RUN_GATE=PASS`가 아니면 image render로 이동하지 않는다.

**검증:** §7에서 worker가 실제 pull한 두 불변 image reference가 owner, SHA
tag, digest를 모두 포함하는지 확인한다.

```bash
if printf '%s\n' "$APP_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-poc:sha-${BOOTSTRAP_SHA}@sha256:[0-9a-f]{64}" \
  && printf '%s\n' "$MOCK_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-mock:sha-${BOOTSTRAP_SHA}@sha256:[0-9a-f]{64}"
then
  printf 'BOOTSTRAP_IMAGE_REFERENCE_GATE=PASS\n'
else
  printf 'BOOTSTRAP_IMAGE_REFERENCE_GATE=FAIL\n' >&2
fi
```

정상 출력은 `BOOTSTRAP_IMAGE_REFERENCE_GATE=PASS`다. `latest`, digest 없는
SHA tag, 서로 다른 SHA가 있으면 진행하지 않는다.

### 8.2 repository를 건드리지 않는 Kustomize 작업 사본

자동 `mktemp` 결과를 숨겨 저장하지 않고, 학습자가 경로를 직접 확인할 수 있는
SHA 기반 임시 디렉터리를 사용한다. 같은 SHA로 이 절차를 다시 실행해 디렉터리가
이미 있다면 `-01`을 `-02`처럼 바꿔 새 경로를 사용한다. 기존 디렉터리를 덮어쓰지
않는다.

**로컬 준비:** 이번 render 전용 디렉터리 이름을 정한다.

```bash
export DEPLOY_RENDER_DIR="/tmp/customer-rule-kustomize-${BOOTSTRAP_SHA}-01"
```

**로컬 준비:** 완성된 manifest 파일 경로를 정한다.

```bash
export DEPLOY_RENDERED_FILE="${DEPLOY_RENDER_DIR}/customer-rule-rendered.yaml"
```

**검증:** 같은 이름의 이전 작업 디렉터리가 없는지 확인한다.

```bash
test ! -e "$DEPLOY_RENDER_DIR"
```

출력 없이 성공해야 한다. 실패하면 위 변수의 마지막 번호를 바꾸고 다시 확인한다.

**변경:** 빈 render 작업 디렉터리를 만든다.

```bash
mkdir -p "$DEPLOY_RENDER_DIR"
```

**조회:** 만든 경로를 확인한다.

```bash
ls -ld "$DEPLOY_RENDER_DIR"
```

**변경:** 원본 base를 임시 작업 사본으로 복사한다.

```bash
cp -R \
  "$GITHUB_WORK_DIR/deploy/openshift/base" \
  "$DEPLOY_RENDER_DIR/base"
```

**조회:** 복사한 base의 파일 이름을 확인한다.

```bash
find "$DEPLOY_RENDER_DIR/base" \
  -maxdepth 1 \
  -type f \
  -print
```

`application.yaml`, `mock.yaml`, `configmap.yaml`, `kustomization.yaml` 네 파일이
보여야 한다.

**변경:** 원본 overlays를 같은 작업 사본으로 복사한다.

```bash
cp -R \
  "$GITHUB_WORK_DIR/deploy/openshift/overlays" \
  "$DEPLOY_RENDER_DIR/overlays"
```

**조회:** Kustomize가 참조할 세 파일과 PAMOE overlay가 모두 있는지 확인한다.

```bash
find "$DEPLOY_RENDER_DIR" \
  -maxdepth 3 \
  -type f \
  -print
```

최소한 `base/application.yaml`, `base/mock.yaml`, `base/configmap.yaml`,
`base/kustomization.yaml`, `overlays/pamoe/kustomization.yaml`,
`overlays/pamoe/license.yaml`이 보여야 한다.

**로컬 준비:** image 치환을 수행할 PAMOE overlay로 이동한다.

```bash
cd "$DEPLOY_RENDER_DIR/overlays/pamoe"
```

**변경:** 임시 overlay에서 앱과 Mock image를 동일한 bootstrap SHA의
`tag@digest` reference로 치환한다.

```bash
kustomize edit set image \
  "customer-rule-poc=$APP_IMAGE" \
  "customer-rule-mock=$MOCK_IMAGE"
```

**조회:** 수정된 임시 `kustomization.yaml`의 image 계약을 확인한다.

```bash
sed -n '1,160p' kustomization.yaml
```

`newName`은 두 GHCR package를, `newTag`는 각각 `sha-${BOOTSTRAP_SHA}`를,
`digest`는 각각 `sha256:<64자리>`를 가리켜야 한다. 원본
`$GITHUB_WORK_DIR/deploy/openshift/overlays/pamoe/kustomization.yaml`은 계속
`DO_NOT_APPLY_SET_IMMUTABLE_REF`인 것이 정상이다.

**변경:** 임시 overlay를 하나의 배포 manifest로 render한다.

```bash
kustomize build . > "$DEPLOY_RENDERED_FILE"
```

**검증:** render 결과에 앱과 Mock의 정확한 SHA image 두 개가 있고, `latest`나
안전 placeholder가 남지 않았는지 한 Gate로 확인한다.

```bash
APP_IMAGE_COUNT="$(
  rg -F -c "image: $APP_IMAGE" "$DEPLOY_RENDERED_FILE" \
  || true
)"
MOCK_IMAGE_COUNT="$(
  rg -F -c "image: $MOCK_IMAGE" "$DEPLOY_RENDERED_FILE" \
  || true
)"

if [ "$APP_IMAGE_COUNT" = '1' ] \
  && [ "$MOCK_IMAGE_COUNT" = '1' ] \
  && ! rg -q \
    'image: .+:(latest|DO_NOT_APPLY_SET_IMMUTABLE_REF)$' \
    "$DEPLOY_RENDERED_FILE"
then
  printf 'IMMUTABLE_IMAGE_RENDER_GATE=PASS\n'
else
  printf 'IMMUTABLE_IMAGE_RENDER_GATE=FAIL\n' >&2
  rg -n '^[[:space:]]*image:' "$DEPLOY_RENDERED_FILE"
fi
```

정상 출력은 `IMMUTABLE_IMAGE_RENDER_GATE=PASS`다. `FAIL`이면 이어서 표시된 image를
확인하고 `oc apply`를 실행하지 않은 채 image 치환 단계로 돌아간다.

**조회:** 적용 전에 현재 cluster에 같은 이름의 Deployment가 있는지 확인한다.

```bash
oc get deployment/customer-rule-mock \
  deployment/customer-rule-poc \
  -n "$APP_NS" \
  --ignore-not-found
```

최초 bootstrap이면 출력이 없을 수 있다. 기존 리소스가 보이면 이름과 namespace가
정확한지 확인하며, 삭제하지 않고 `apply`의 갱신 대상으로 사용한다.

### 8.3 server-side validation과 최초 적용

**검증:** 실제 API server가 권한과 리소스 schema를 검증하게 하되 아직 cluster를
변경하지 않는다.

```bash
oc apply \
  --dry-run=server \
  -n "$APP_NS" \
  -f "$DEPLOY_RENDERED_FILE"
```

Deployment 두 개, Service 세 개, ConfigMap 하나가 `created (server dry run)`
또는 `configured (server dry run)`으로 보여야 한다. `Forbidden`이면 §2 권한을,
schema 오류면 render 파일과 OCP 버전을 확인한다.

**변경:** 검증한 동일 파일을 `bamoe-poc`에 적용한다.

```bash
oc apply \
  -n "$APP_NS" \
  -f "$DEPLOY_RENDERED_FILE"
```

**조회:** 방금 생성·갱신된 리소스 종류와 이름을 확인한다.

```bash
oc get deployment,service,configmap \
  -n "$APP_NS" \
  -l app.kubernetes.io/part-of=bamoe-customer-rule-poc
```

Deployment `customer-rule-poc`, `customer-rule-mock`, Service
`customer-rule-poc`, `customer-rule-poc-management`, `customer-rule-mock`,
ConfigMap `customer-rule-poc`이 보여야 한다.

**조회:** 두 Deployment의 rollout 수치를 관찰한다.

```bash
oc get deployment/customer-rule-mock \
  deployment/customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,UPDATED:.status.updatedReplicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas'
```

처음에는 일부 값이 비어 있을 수 있다. 자동 polling이나 loop를 만들지 말고 이
조회 명령을 사람이 다시 실행해 두 행 모두 `DESIRED=1`, `UPDATED=1`, `READY=1`,
`AVAILABLE=1`이 되는지 관찰한다.

**조회:** 실제 Deployment가 사용하는 container 이름과 image를 확인한다.

```bash
oc get deployment/customer-rule-mock \
  deployment/customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,CONTAINER:.spec.template.spec.containers[0].name,IMAGE:.spec.template.spec.containers[0].image'
```

정상 계약은 다음과 같다.

| Deployment | container | image 끝 |
|---|---|---|
| `customer-rule-mock` | `mock` | `customer-rule-mock:sha-${BOOTSTRAP_SHA}@sha256:<digest>` |
| `customer-rule-poc` | `application` | `customer-rule-poc:sha-${BOOTSTRAP_SHA}@sha256:<digest>` |

`latest`, digest 없는 tag, 서로 다른 SHA가 보이면 §12의 자동 배포를 켜지 않는다.

**조회:** 실제 Pod 상태와 node 배치를 확인한다.

```bash
oc get pod \
  -n "$APP_NS" \
  -l app.kubernetes.io/part-of=bamoe-customer-rule-poc \
  -o wide
```

두 Pod가 `Running`이고 `READY 1/1`이어야 한다.

**조회:** Service port 계약을 확인한다.

```bash
oc get service/customer-rule-poc \
  service/customer-rule-poc-management \
  service/customer-rule-mock \
  -n "$APP_NS"
```

앱은 `8080`, management는 `8081`, Mock은 `8091`, `8092`, `8093`, `8094`를
노출해야 한다.

Pod가 Ready가 되지 않으면 변경 명령을 반복하지 말고 먼저 상태를 읽는다.

```bash
oc describe deployment/customer-rule-poc \
  -n "$APP_NS"
```

```bash
oc describe deployment/customer-rule-mock \
  -n "$APP_NS"
```

```bash
oc logs deployment/customer-rule-poc \
  -n "$APP_NS"
```

```bash
oc logs deployment/customer-rule-mock \
  -n "$APP_NS"
```

```bash
oc get events \
  -n "$APP_NS" \
  --sort-by=.lastTimestamp
```

Mock은 다음 OCP 내부 주소에서만 사용한다.

```text
http://customer-rule-mock:8091
http://customer-rule-mock:8092
http://customer-rule-mock:8093
http://customer-rule-mock:8094
```

현재 BPMN의 REST URL도 이 이름을 사용한다. `/etc/hosts`는 로컬 개발용일 뿐,
OpenShift Pod의 DNS에는 영향을 주지 않는다.

**조회:** 배포한 source의 BPMN이 OCP Service DNS 이름과 `8091`~`8094` port를
사용하는지 확인한다.

```bash
rg -n \
  'http://customer-rule-mock:809[1-4]/' \
  "$GITHUB_WORK_DIR/src/main/resources/bpmn"
```

`localhost`가 아니라 `customer-rule-mock`이 출력되어야 한다. 이 이름은
`deploy/openshift/base/mock.yaml`의 Service 이름과 정확히 같아야 한다.

**검증:** 배포 대상 BPMN에 Pod 자신을 가리키는 `localhost` 또는
`127.0.0.1` 외부 호출 URL이 남아 있지 않은지 검색한다.

```bash
rg -n 'https?://(localhost|127\.0\.0\.1)(:|/)' "$GITHUB_WORK_DIR/src/main/resources/bpmn"
```

정상은 아무 출력도 없고 `rg` 종료 코드가 `1`인 상태다. 한 줄이라도 출력되면
해당 프로세스가 OCP Mock Service를 호출하지 못하므로 배포를 완료로 판단하지
않는다.

bootstrap이 성공했으면 non-secret image provenance 임시 파일을 정확한 경로
검증과 같은 블록에서 제거한다.

```bash
case "${BOOTSTRAP_IMAGE_ENV:-}" in
  /tmp/bamoe-bootstrap-images-*.env)
    if [ -f "$BOOTSTRAP_IMAGE_ENV" ] && [ -O "$BOOTSTRAP_IMAGE_ENV" ]; then
      if unlink "$BOOTSTRAP_IMAGE_ENV"; then
        unset BOOTSTRAP_IMAGE_ENV
        printf 'BOOTSTRAP_ENV_CLEANUP_GATE=PASS\n'
      else
        printf 'BOOTSTRAP_ENV_CLEANUP_GATE=FAIL\n' >&2
      fi
    else
      printf 'BOOTSTRAP_ENV_CLEANUP_GATE=FAIL (file missing or not owned by current user)\n' >&2
    fi
    ;;
  *)
    printf 'REFUSE: unexpected bootstrap environment path\n' >&2
    ;;
esac
```

적용에 사용한 Kustomize 작업 사본도 더 이상 필요하지 않다. 같은 SHA로 재실습할
때 불필요한 `-02`, `-03` 디렉터리가 쌓이지 않도록, 정확한 SHA prefix·소유권·
render 파일 위치를 검증한 뒤 작업 사본 하나만 제거한다.

```bash
case "${DEPLOY_RENDER_DIR:-}" in
  /tmp/customer-rule-kustomize-"${BOOTSTRAP_SHA}"-*)
    if [ -d "$DEPLOY_RENDER_DIR" ] \
      && [ -O "$DEPLOY_RENDER_DIR" ] \
      && [ ! -L "$DEPLOY_RENDER_DIR" ] \
      && [ "${DEPLOY_RENDERED_FILE:-}" \
        = "${DEPLOY_RENDER_DIR}/customer-rule-rendered.yaml" ] \
      && [ -f "$DEPLOY_RENDERED_FILE" ]
    then
      rm -rf -- "$DEPLOY_RENDER_DIR"
      unset DEPLOY_RENDER_DIR DEPLOY_RENDERED_FILE
      printf 'KUSTOMIZE_WORK_COPY_CLEANUP_GATE=PASS\n'
    else
      printf 'REFUSE: Kustomize work copy ownership or contract mismatch\n' >&2
    fi
    ;;
  *)
    printf 'REFUSE: unexpected Kustomize work copy path\n' >&2
    ;;
esac
```

**Gate**

- server-side dry-run이 성공했다.
- 두 Deployment가 `UPDATED=READY=AVAILABLE=1`이다.
- 실제 container 이름은 `application`, `mock`이다.
- 실제 두 image가 모두 `sha-${BOOTSTRAP_SHA}@sha256:...`이며 `latest`나
  placeholder가 남지 않았다.
- 앱/management/Mock Service port가 각각 manifest 계약과 일치한다.
- BPMN의 고정 URL과 OCP Mock Service 이름이 `customer-rule-mock`으로 일치한다.
- 배포 대상 BPMN에 `localhost` 또는 `127.0.0.1` 외부 호출 URL이 없다.

## 9. Route 없이 health와 Case 04 검증

외부 Route를 만들기 전에 OCP Service와 Pod 내부 경로부터 검증한다. 이렇게 하면
문제가 생겼을 때 애플리케이션 문제와 외부 DNS/TLS 문제를 분리할 수 있다.

### 9.1 Service와 endpoint 사전 관찰

**조회:** port-forward 대상 Service 세 개와 port를 확인한다.

```bash
oc get service/customer-rule-poc \
  service/customer-rule-poc-management \
  service/customer-rule-mock \
  -n "$APP_NS"
```

앱 `8080`, management `8081`, Mock `8091`~`8094`가 보여야 한다. Service가
없으면 §8 bootstrap을 다시 검토한다.

**조회:** 앱 Service가 Ready Pod endpoint를 가지고 있는지 확인한다.

```bash
oc get endpointslice \
  -n "$APP_NS" \
  -l kubernetes.io/service-name=customer-rule-poc \
  -o wide
```

`ENDPOINTS`에 Pod IP가 있어야 한다. `<none>`이면 Deployment의 selector, Pod label,
readiness를 확인한다.

**조회:** management Service의 endpoint를 확인한다.

```bash
oc get endpointslice \
  -n "$APP_NS" \
  -l kubernetes.io/service-name=customer-rule-poc-management \
  -o wide
```

앱 Service와 같은 Ready Pod IP를 가리키는 것이 정상이다.

**조회:** Mock Service의 endpoint를 확인한다.

```bash
oc get endpointslice \
  -n "$APP_NS" \
  -l kubernetes.io/service-name=customer-rule-mock \
  -o wide
```

Mock Pod IP가 보여야 한다.

**조회:** 첫 구축 순서에서는 아직 앱 Route가 없음을 확인한다.

```bash
oc get route customer-rule-poc \
  -n "$APP_NS" \
  --ignore-not-found
```

처음 진행 중이면 출력이 없는 것이 정상이다. 이전 실습에서 Route가 이미 있다면
삭제하지 않아도 되지만, 이 섹션의 검증은 Route URL이 아니라 port-forward만
사용한다.

### 9.2 네 개 terminal 준비

terminal A~C는 각각 하나의 port-forward를 계속 실행하고, terminal D는 curl과
`oc` 조회에 사용한다. port-forward 명령은 종료되지 않고
`Forwarding from 127.0.0.1:...`를 표시하는 것이 정상이다.

#### Terminal A — Business Service HTTP 8080

**로컬 준비:** 새 terminal A에서 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

**로컬 준비:** namespace와 OCP 환경값을 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

**대기:** 앱 HTTP Service를 Mac의 `127.0.0.1:18080`에 연결한다.

```bash
oc port-forward \
  -n "$APP_NS" \
  service/customer-rule-poc \
  18080:8080
```

정상 출력은 `Forwarding from 127.0.0.1:18080 -> 8080`이다. `address already in
use`이면 기존 port-forward terminal을 찾아 종료하거나 사용 중인 프로세스를
확인한다.

#### Terminal B — management 8081

**로컬 준비:** 새 terminal B에서 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

**로컬 준비:** 같은 환경값을 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

**대기:** management Service를 Mac의 `127.0.0.1:18081`에 연결한다.

```bash
oc port-forward \
  -n "$APP_NS" \
  service/customer-rule-poc-management \
  18081:8081
```

정상 출력은 `Forwarding from 127.0.0.1:18081 -> 8081`이다. Service를 찾지
못하면 terminal의 `APP_NS`와 §8의 management Service 생성을 확인한다.

#### Terminal C — Case 04 Mock 8094

**로컬 준비:** 새 terminal C에서 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

**로컬 준비:** 같은 환경값을 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

**대기:** Mock Service의 Case 04 port를 Mac의 `127.0.0.1:18094`에 연결한다.

```bash
oc port-forward \
  -n "$APP_NS" \
  service/customer-rule-mock \
  18094:8094
```

정상 출력은 `Forwarding from 127.0.0.1:18094 -> 8094`다. 이 port는 Case 04
journal과 CSMAUX004/005 Mock에만 사용한다.

#### Terminal D — 검증 명령

**로컬 준비:** 새 terminal D에서 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

**로컬 준비:** 진단에 사용할 환경값을 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

### 9.3 health와 OpenAPI 검증

이전 실행의 JSON을 잘못 읽지 않도록 이번 검증 전용 디렉터리를 새로 만든다.

```bash
export OCP_E2E_DIR="$(
  mktemp -d /tmp/bamoe-ocp-e2e.XXXXXX
)"
```

```bash
printf 'OCP_E2E_DIR=%s\n' "$OCP_E2E_DIR"
```

아래 `curl`이 실패하면 해당 응답 파일은 새 디렉터리 안에서 비어 있거나 없으므로,
이전 성공 결과가 다음 `jq` 검증에 사용되지 않는다.

**검증:** Terminal D에서 management liveness 응답을 합성 데이터용 임시 파일에
저장한다.

```bash
curl --fail-with-body \
  --silent \
  --show-error \
  --output "$OCP_E2E_DIR/liveness.json" \
  http://127.0.0.1:18081/actuator/health/liveness
```

정상이면 출력 없이 종료되고 JSON 파일이 생긴다. 연결 거절이면 terminal B가 계속
실행 중인지 확인하고, HTTP 오류면 앱 로그를 확인한다.

**조회:** 저장한 liveness 응답이 `UP`인지 assertion한다.

```bash
jq -e '.status == "UP"' "$OCP_E2E_DIR/liveness.json"
```

정상 출력은 `true`다.

**검증:** management readiness 응답을 별도 임시 파일에 저장한다.

```bash
curl --fail-with-body \
  --silent \
  --show-error \
  --output "$OCP_E2E_DIR/readiness.json" \
  http://127.0.0.1:18081/actuator/health/readiness
```

정상이면 출력 없이 종료된다. liveness는 성공하지만 이 호출이 실패하면 dependency,
startup 상태와 readiness probe 로그를 확인한다.

**조회:** 저장한 readiness 응답이 `UP`인지 assertion한다.

```bash
jq -e '.status == "UP"' "$OCP_E2E_DIR/readiness.json"
```

정상 출력은 `true`다.

**검증:** 앱 OpenAPI 문서를 임시 파일에 저장한다.

```bash
curl --fail-with-body \
  --silent \
  --show-error \
  --output "$OCP_E2E_DIR/openapi.json" \
  http://127.0.0.1:18080/v3/api-docs
```

정상이면 출력 없이 종료되고 OpenAPI JSON이 저장된다.

**조회:** 저장한 OpenAPI에 현재 구현된 Case 01~04 process endpoint가 모두
있는지 assertion한다.

```bash
jq -e '
  .paths
  | has("/Case01ServiceStatusChangeProcess")
    and has("/Case02WirelineNameChangeProcess")
    and has("/Case03MmsSendProcess")
    and has("/Case04FallbackProcess")
' "$OCP_E2E_DIR/openapi.json"
```

정상 출력은 `true`다. `false`면 현재 image SHA가 기대한 commit인지 §8의
Deployment image 조회부터 다시 확인한다.

### 9.4 Case 04 fallback E2E와 exact journal

이 테스트는 결과가 `ALLOW`인지만 보지 않는다. BPMN이 CSMAUX004의 거절을 받은 뒤
DMN을 다시 평가하고, 그때에만 CSMAUX005를 호출했는지 Mock journal로 확인한다.

**로컬 준비:** 합성 테스트 요청 ID를 지정한다.

```bash
export OCP_TEST_REQUEST_ID='OCP-C04-FALLBACK'
```

**변경:** 같은 ID의 과거 Mock journal만 초기화한다.

```bash
curl --fail-with-body \
  --silent \
  --show-error \
  -X DELETE \
  "http://127.0.0.1:18094/mock/auth/calls/${OCP_TEST_REQUEST_ID}"
```

정상이면 성공 HTTP 응답을 받고 과거 호출 기록이 사라진다. `404`면 terminal C의
port와 Mock image SHA를 확인한다.

**조회:** process를 시작하기 전에 초기화된 journal을 임시 파일에 저장한다.

```bash
curl --fail-with-body \
  --silent \
  --show-error \
  --output "$OCP_E2E_DIR/case04-journal-empty.json" \
  "http://127.0.0.1:18094/mock/auth/calls/${OCP_TEST_REQUEST_ID}"
```

**검증:** 과거 호출이 하나도 남지 않았는지 확인한다.

```bash
jq -e '.calls == []' "$OCP_E2E_DIR/case04-journal-empty.json"
```

정상 출력은 `true`다. `false`면 요청 ID와 DELETE URL을 다시 확인하고 process를
호출하지 않는다.

**변경:** `FALLBACK_GRANTED` 합성 시나리오로 Case 04 process를 시작하고 응답을
임시 파일에 저장한다.

```bash
curl --fail-with-body \
  --silent \
  --show-error \
  --output "$OCP_E2E_DIR/case04-process-response.json" \
  --write-out 'HTTP %{http_code}\n' \
  -X POST \
  http://127.0.0.1:18080/Case04FallbackProcess \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d "{
    \"requestId\": \"${OCP_TEST_REQUEST_ID}\",
    \"customerId\": \"C001\",
    \"mockScenario\": \"FALLBACK_GRANTED\"
  }"
```

정상이면 terminal에 `HTTP 201`이 출력되고 응답 body는 임시 파일에 저장된다. 실패하면
임시 응답 파일의 오류 body와 앱 로그에서 REST task mapping, DMN 평가 오류를
확인한다.

**조회:** 저장한 최종 응답의 업무 결과를 assertion한다.

```bash
jq -e '
  .processResponse.executionState == "COMPLETED"
  and .processResponse.policyEvaluationCount == 2
  and .processResponse.policyResult.status == "ALLOW"
  and .processResponse.policyResult.reasonCode == "FALLBACK_AUTH_GRANTED"
  and .processResponse.policyResult.reasonMessage
      == "CSMAUX005 대체 권한이 승인되었습니다."
' "$OCP_E2E_DIR/case04-process-response.json"
```

정상 출력은 `true`다. `false` 또는 `null`이면 전체 응답을 읽고 DMN/BPMN mapping을
확인한다.

**검증:** 같은 요청 ID의 Mock journal을 임시 파일에 저장한다.

```bash
curl --fail-with-body \
  --silent \
  --show-error \
  --output "$OCP_E2E_DIR/case04-journal.json" \
  "http://127.0.0.1:18094/mock/auth/calls/${OCP_TEST_REQUEST_ID}"
```

정상이면 journal JSON이 저장된다.

**조회:** 외부 호출 순서가 정확한지 assertion한다.

```bash
jq -e \
  '.calls == ["CSMAUX004", "CSMAUX005"]' \
  "$OCP_E2E_DIR/case04-journal.json"
```

정상 출력은 `true`다. `CSMAUX005`가 없으면 fallback gateway/loop 조건을,
순서가 다르거나 호출이 더 많으면 BPMN loop와 Mock journal 초기화를 확인한다.

앱 내부 오류를 확인할 때에는 Terminal D에서 다음 조회를 사용한다.

```bash
oc logs deployment/customer-rule-poc \
  -n "$APP_NS"
```

Mock 호출 또는 journal 오류는 다음 조회로 확인한다.

```bash
oc logs deployment/customer-rule-mock \
  -n "$APP_NS"
```

**Gate**

- 세 port-forward terminal이 연결된 상태로 유지됐다.
- liveness와 readiness assertion이 모두 `true`다.
- OpenAPI의 Case 01~04 endpoint assertion이 `true`다.
- Case 04 응답 assertion이 `true`이고 `policyEvaluationCount=2`다.
- exact journal assertion이 `true`이며 호출 순서는
  `CSMAUX004 → CSMAUX005`다.

검증이 끝나면 이번 E2E 디렉터리의 알려진 합성 응답 파일만 제거하고 빈
디렉터리를 닫는다. 예상하지 않은 파일이 있으면 `rmdir`가 실패하므로 강제로
재귀 삭제하지 않는다.

```bash
case "${OCP_E2E_DIR:-}" in
  /tmp/bamoe-ocp-e2e.*)
    if [ -d "$OCP_E2E_DIR" ] \
      && [ -O "$OCP_E2E_DIR" ] \
      && [ ! -L "$OCP_E2E_DIR" ]
    then
      for e2e_file in \
        liveness.json \
        readiness.json \
        openapi.json \
        case04-journal-empty.json \
        case04-process-response.json \
        case04-journal.json
      do
        if [ -f "$OCP_E2E_DIR/$e2e_file" ] \
          && [ ! -L "$OCP_E2E_DIR/$e2e_file" ]
        then
          unlink "$OCP_E2E_DIR/$e2e_file"
        fi
      done
      if rmdir "$OCP_E2E_DIR"; then
        unset OCP_E2E_DIR
        printf 'OCP_E2E_TEMP_CLEANUP_GATE=PASS\n'
      else
        printf 'REFUSE: unexpected files remain in the E2E directory\n' >&2
      fi
    else
      printf 'REFUSE: E2E temp ownership or path type mismatch\n' >&2
    fi
    ;;
  *)
    printf 'REFUSE: unexpected E2E temp path\n' >&2
    ;;
esac
```

Gate를 통과한 뒤 terminal A~C의 port-forward는 `Ctrl+C`로 종료해도 된다.

## 10. Business Service HTTPS Route

§9에서 Service 경로를 먼저 검증했으므로 이제 외부 DNS/TLS 계층을 추가한다.
Mock에는 외부 Route를 만들지 않고 Business Service의 HTTP port `8080`만 공개한다.
management `8081`도 외부에 공개하지 않는다.

### 10.1 Route 대상과 manifest 확인

**로컬 준비:** 배포 manifest가 있는 독립 작업 사본으로 이동한다.

```bash
cd "$GITHUB_WORK_DIR"
```

**조회:** Route가 연결할 Service가 존재하고 port 이름이 `http`인지 확인한다.

```bash
oc get service/customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,PORT_NAME:.spec.ports[0].name,PORT:.spec.ports[0].port,TARGET:.spec.ports[0].targetPort'
```

정상은 `NAME=customer-rule-poc`, `PORT_NAME=http`, `PORT=8080`,
`TARGET=http`다. 다르면 Route를 적용하기 전에
`deploy/openshift/base/application.yaml`과 실제 Service를 비교한다.

**조회:** 적용할 Route 파일의 대상 Service, target port, TLS 정책을 읽는다.

```bash
sed -n '1,160p' deploy/openshift/route.yaml
```

다음 계약이 보여야 한다.

| 필드 | 값 |
|---|---|
| `metadata.name` | `customer-rule-poc` |
| `spec.to.name` | `customer-rule-poc` |
| `spec.port.targetPort` | `http` |
| `spec.tls.termination` | `edge` |
| `spec.tls.insecureEdgeTerminationPolicy` | `Redirect` |

### 10.2 server-side validation과 Route 생성

> **외부 공개 전 확인:** 다음 Route에는 이 가이드가 별도 인증을 추가하지 않는다.
> 적용하면 인터넷에서 Business Service URL에 접근할 수 있으므로 합성 요청만
> 사용하고, 시연 종료 후 §17.3에서 Route를 제거한다. Mock Service와 management
> port `8081`은 계속 외부에 공개하지 않는다.

**검증:** API server에서 Route schema, 대상 namespace 권한을 검증한다. 아직
리소스는 만들지 않는다.

```bash
oc apply \
  --dry-run=server \
  -n "$APP_NS" \
  -f deploy/openshift/route.yaml
```

정상이면 `route.route.openshift.io/customer-rule-poc created (server dry run)`
또는 `configured (server dry run)`이 출력된다. `Forbidden`이면 §2 권한을,
target port 오류면 위 Service 계약을 확인한다.

**변경:** 검증한 동일 Route manifest를 적용한다.

```bash
oc apply \
  -n "$APP_NS" \
  -f deploy/openshift/route.yaml
```

**조회:** 생성 직후 Route의 host, Service, port, TLS termination을 확인한다.

```bash
oc get route customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,HOST:.spec.host,SERVICE:.spec.to.name,PORT:.spec.port.targetPort,TLS:.spec.tls.termination'
```

`SERVICE=customer-rule-poc`, `PORT=http`, `TLS=edge`이고 `HOST`가 비어 있지 않아야
한다. Route가 없으면 apply 출력과 namespace를 확인한다.

**조회:** ingress controller가 Route를 승인했는지 확인한다.

```bash
oc get route customer-rule-poc \
  -n "$APP_NS" \
  -o jsonpath='{.status.ingress[0].conditions[?(@.type=="Admitted")].status}{"\n"}'
```

정상 출력은 `True`다. 처음에 비어 있으면 자동 polling을 만들지 말고 잠시 뒤 이
조회 명령을 사람이 다시 실행한다. 계속 `False`거나 비어 있으면 다음 조회로
ingress 메시지를 확인한다.

```bash
oc describe route customer-rule-poc \
  -n "$APP_NS"
```

**조회:** Route 뒤의 Service endpoint가 여전히 Ready Pod를 가리키는지 확인한다.

```bash
oc get endpointslice \
  -n "$APP_NS" \
  -l kubernetes.io/service-name=customer-rule-poc \
  -o wide
```

`ENDPOINTS`에 Pod IP가 있어야 한다. Route는 `Admitted=True`인데 endpoint가
없다면 앱 readiness와 Service selector 문제다.

### 10.3 외부 URL을 사람이 확인하고 TLS 검증

**조회:** manifest에 선언했고 cluster가 승인한 Route host를 한 줄로 출력한다.

```bash
oc get route customer-rule-poc \
  -n "$APP_NS" \
  -o jsonpath='{.spec.host}{"\n"}'
```

현재 manifest는 host를 명시하므로 출력은
`customer-rule-poc.${OCP_ROUTE_DOMAIN}`이어야 한다. OpenShift가 namespace를
붙여 자동 생성한 이름이 아니다.

**로컬 준비:** 사람이 다시 입력해 오타를 만들지 않도록 같은 Route에서 host를
변수로 읽는다.

```bash
export APP_ROUTE_HOST="$(
  oc get route customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.spec.host}'
)"
```

**검증:** live Route가 현재 manifest 계약과 같은지 확인한다.

```bash
if [ "$APP_ROUTE_HOST" = "customer-rule-poc.${OCP_ROUTE_DOMAIN}" ]; then
  printf 'APP_ROUTE_HOST_GATE=PASS\n'
else
  printf 'APP_ROUTE_HOST_GATE=FAIL\n' >&2
fi
```

**로컬 준비:** 이후 GitHub Actions에서도 사용할 HTTPS base URL을 만든다.

```bash
export APP_BASE_URL="https://${APP_ROUTE_HOST}"
```

**조회:** scheme과 host에 오타가 없는지 확인한다.

```bash
printf 'APP_BASE_URL=%s\n' "$APP_BASE_URL"
```

반드시 `https://`로 시작하고 path나 마지막 `/` 없이 host에서 끝나야 한다.

**로컬 준비:** 이전 Route 응답과 섞이지 않는 새 임시 파일을 만든다.

```bash
export ROUTE_OPENAPI_FILE="$(
  mktemp /tmp/bamoe-route-openapi.XXXXXX
)"
```

**검증:** 일반적인 TLS trust를 사용해 외부 Mac에서 OpenAPI를 임시 파일에
저장한다.

```bash
curl --fail-with-body \
  --silent \
  --show-error \
  --output "$ROUTE_OPENAPI_FILE" \
  "${APP_BASE_URL}/v3/api-docs"
```

정상이면 출력 없이 종료되고 OpenAPI JSON이 저장된다. Route 생성 직후 DNS 전파가
끝나지 않았다면 잠시 뒤 이 명령을 사람이 다시 실행한다. 자동 retry loop를
만들지 않는다.

**조회:** 저장한 외부 OpenAPI가 실제 path를 포함하는지 assertion한다.

```bash
jq -e '.paths | length > 0' "$ROUTE_OPENAPI_FILE"
```

정상 출력은 `true`다.

실패 유형은 다음처럼 구분한다.

- 이름 해석 실패: `APP_ROUTE_HOST` 오타와 외부 DNS 전파 확인
- 인증서 오류: ingress 인증서 chain과 외부 trust 확인
- HTTP `503`: Route의 Service/port와 EndpointSlice 확인
- HTTP `404`: 요청 path와 앱 image의 OpenAPI 설정 확인

현재 앱 Route에는 인증이 없다. URL을 아는 외부 사용자가 호출할 수 있으므로:

- 고객 실데이터를 보내지 않는다.
- mock에는 Route를 만들지 않는다.
- 자동 배포를 사용하는 동안은 workflow의 외부 smoke test 때문에 앱 Route를
  유지한다.
- PoC 종료 시에는 §17에서 Route를 삭제한다.

위 검증에 `--insecure` 또는 `-k`를 추가하지 않는다. 인증서 오류라면 ingress
Route에 외부에서 신뢰 가능한 인증서를 구성해 달라고 플랫폼 관리자에게 요청한다.
GitHub-hosted runner도 같은 Route를 검증하므로 이 Gate를 우회한 상태에서는 자동
배포를 켜지 않는다. Mac에만 설치된 사내 CA로 통과한 경우도 있을 수 있으므로
§12.4에서 GitHub-hosted runner 전용 TLS preflight를 한 번 더 수행한다.

**Gate**

- Route 계약이 `customer-rule-poc → customer-rule-poc:http`, `edge`,
  `Redirect`로 확인됐다.
- Route status가 `Admitted=True`다.
- backend EndpointSlice에 Ready Pod IP가 있다.
- `${APP_BASE_URL}/v3/api-docs`가 `-k` 없이 외부 Mac에서 성공하고 `true`를
  출력한다.
- Mock과 management port에는 외부 Route를 만들지 않았다.

외부 OpenAPI 검증 파일은 prefix, 소유권, 일반 파일 여부를 확인한 뒤 제거한다.

```bash
case "${ROUTE_OPENAPI_FILE:-}" in
  /tmp/bamoe-route-openapi.*)
    if [ -f "$ROUTE_OPENAPI_FILE" ] \
      && [ -O "$ROUTE_OPENAPI_FILE" ] \
      && [ ! -L "$ROUTE_OPENAPI_FILE" ]
    then
      unlink "$ROUTE_OPENAPI_FILE"
      unset ROUTE_OPENAPI_FILE
      printf 'ROUTE_OPENAPI_TEMP_CLEANUP_GATE=PASS\n'
    else
      printf 'REFUSE: Route OpenAPI temp ownership or type mismatch\n' >&2
    fi
    ;;
  *)
    printf 'REFUSE: unexpected Route OpenAPI temp path\n' >&2
    ;;
esac
```

## 11. PAMOE Runtime Environment 직접 설치와 연결

Runtime도 Helm 없이 두 공식 image를 직접 배포한다.

```text
bamoe-runtime
├─ bamoe-management-console
│  ├─ Deployment
│  ├─ ClusterIP Service
│  └─ HTTPS Route
└─ bamoe-mcp-server
   ├─ Deployment
   └─ ClusterIP Service
```

Management Console은 브라우저 UI이므로 외부 Route가 필요하다. MCP Server는
Technology Preview이고 현재 인증을 끈 상태이므로 외부 Route를 만들지 않는다.

> **외부 공개 경계:** 이 PoC의 Management Console Route에도 사용자 인증이
> 없다. Management Console은 Business Service 연결과 process 관리 기능을 다루는
> 관리 UI이므로 합성 데이터만 사용하고 시연 시간에만 Route를 유지한다. 시연
> 종료 직후 §17.5에서 정확한 Route를 제거하며, 상시 환경이나 운영 전환 전에는
> OAuth proxy 또는 OIDC와 권한 모델을 먼저 구성한다.

### 11.1 Runtime manifest와 대상 Project 확인

새 terminal이라면 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

환경을 불러오고 현재 cluster를 검증한다.

```bash
source deploy/openshift/ocp-env.sh
```

```bash
bamoe_check_env
```

현재 로그인 API server를 다시 확인한다.

```bash
oc whoami --show-server
```

Runtime Project의 ownership을 확인한다.

```bash
oc get namespace "$RUNTIME_NS" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

`NAME=bamoe-runtime`, `STATUS=Active`, `OWNER=bamoe-poc-guide`가 아니면 중단한다.

Runtime Project의 quota와 기본 제한을 관찰한다.

```bash
oc get resourcequota,limitrange -n "$RUNTIME_NS"
```

Runtime 기본 요청량은 Management Console과 MCP를 합쳐 CPU 약 `750m`, memory 약
`1.5Gi`다. ResourceQuota가 더 작거나 LimitRange가 manifest와 충돌하면 적용 전에
플랫폼 관리자와 값을 조정한다.

Kustomization 입력을 읽는다.

```bash
sed -n '1,120p' deploy/openshift/products/runtime/kustomization.yaml
```

두 제품 파일이 있고 namespace가 `bamoe-runtime`인지 확인한다.

새 render 파일을 만든다.

```bash
export BAMOE_RUNTIME_RENDERED="$(mktemp /tmp/bamoe-runtime-direct.XXXXXX)"
```

Runtime manifest를 조립한다.

```bash
kustomize build deploy/openshift/products/runtime > "$BAMOE_RUNTIME_RENDERED"
```

조립 결과의 리소스 이름을 읽는다.

```bash
rg -n '^(kind:|  name:)' "$BAMOE_RUNTIME_RENDERED"
```

정상 계약:

| Kind | 이름 |
|---|---|
| Deployment | `bamoe-management-console` |
| Service | `bamoe-management-console` |
| Route | `bamoe-management-console` |
| Deployment | `bamoe-mcp-server` |
| Service | `bamoe-mcp-server` |

MCP Route가 render 결과에 없는지 확인한다.

```bash
if rg -n '^kind: Route$' deploy/openshift/products/runtime/mcp-server.yaml; then
  printf 'GATE=FAIL: unauthenticated MCP Route found\n'
else
  printf 'GATE=PASS: MCP remains internal\n'
fi
```

정상 출력은 `GATE=PASS`다.

두 image가 정확한지 확인한다.

```bash
test "$(
  awk '
    $1 == "image:" {print $2}
    $1 == "-" && $2 == "image:" {print $3}
  ' "$BAMOE_RUNTIME_RENDERED" | sort -u
)" = "$(
  printf '%s\n' \
    'quay.io/bamoe/management-console:9.5.0-ibm-0005' \
    'quay.io/bamoe/mcp-server:9.5.0-ibm-0005' \
    | sort -u
)"
```

정상이면 출력 없이 성공한다. 사람이 읽을 때에는 §4.3과 같은 `awk ... | sort -u`
명령으로 Management Console과 MCP Server 두 전체 문자열을 다시 표시할 수 있다.

### 11.2 Runtime dry-run과 적용

기존 Runtime 제품 리소스를 조회한다.

```bash
oc get deployment,service,route \
  -n "$RUNTIME_NS" \
  -l app.kubernetes.io/part-of=bamoe-runtime-environment
```

처음이면 `No resources found`가 정상이다. 기존 리소스가 있다면 아래 적용은
업데이트가 되므로 현재 image와 Route 소유자를 확인한다.

cluster 전체에서 Management Console host를 이미 쓰는지 확인한다.

```bash
oc get route -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOST:.spec.host' \
  | rg 'bamoe-management-console\.'
```

처음 설치라면 아무 출력이 없어야 한다. 다른 Project가 같은 host를
쓰면 적용하지 않는다.

API server에서 manifest를 저장 없이 검증한다.

```bash
oc apply \
  --dry-run=server \
  -n "$RUNTIME_NS" \
  -f "$BAMOE_RUNTIME_RENDERED"
```

모두 `created (server dry run)` 또는 `configured (server dry run)`이어야 한다.

적용 전 차이를 읽는다.

```bash
oc diff -n "$RUNTIME_NS" -f "$BAMOE_RUNTIME_RENDERED"
```

차이가 있으면 종료 코드 `1`이 정상이다. 이해하지 못한 삭제나 MCP Route 생성이
보이면 적용하지 않는다.

검증한 동일 파일을 한 번 적용한다.

```bash
oc apply -n "$RUNTIME_NS" -f "$BAMOE_RUNTIME_RENDERED"
```

Management Console rollout을 기다린다.

```bash
oc rollout status \
  deployment/bamoe-management-console \
  -n "$RUNTIME_NS" \
  --timeout=5m
```

MCP Server rollout을 기다린다.

```bash
oc rollout status \
  deployment/bamoe-mcp-server \
  -n "$RUNTIME_NS" \
  --timeout=8m
```

두 Deployment의 Ready와 image를 관찰한다.

```bash
oc get deployment \
  -n "$RUNTIME_NS" \
  -l app.kubernetes.io/part-of=bamoe-runtime-environment \
  -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas,IMAGE:.spec.template.spec.containers[0].image'
```

정상은 두 행 모두 `READY=1`, `AVAILABLE=1`이다.

실패했을 때에만 Event를 확인한다.

```bash
oc get events -n "$RUNTIME_NS" --sort-by=.lastTimestamp
```

실패한 Deployment 하나의 log를 확인한다.

```bash
export FAILED_RUNTIME_DEPLOYMENT='<실패한 실제 Deployment 이름>'
```

```bash
oc logs \
  deployment/"$FAILED_RUNTIME_DEPLOYMENT" \
  -n "$RUNTIME_NS" \
  --tail=200
```

정상 rollout이면 Event, 변수 설정, log의 세 실패 진단 명령은 실행하지 않아도
된다.

### 11.3 Management Console Route와 health 확인

Management Console Route 계약을 읽는다.

```bash
oc get route bamoe-management-console \
  -n "$RUNTIME_NS" \
  -o custom-columns='NAME:.metadata.name,HOST:.spec.host,SERVICE:.spec.to.name,PORT:.spec.port.targetPort,TLS:.spec.tls.termination,ADMITTED:.status.ingress[0].conditions[?(@.type=="Admitted")].status'
```

정상 계약은 `SERVICE=bamoe-management-console`, `PORT=http`, `TLS=edge`,
`ADMITTED=True`다.

Management Console Service가 Ready endpoint를 갖는지 확인한다.

```bash
oc get endpointslice \
  -n "$RUNTIME_NS" \
  -l kubernetes.io/service-name=bamoe-management-console \
  -o wide
```

MCP Service endpoint도 확인한다.

```bash
oc get endpointslice \
  -n "$RUNTIME_NS" \
  -l kubernetes.io/service-name=bamoe-mcp-server \
  -o wide
```

두 출력 모두 Pod 주소와 port가 있어야 한다.

Management Console URL을 만든다.

```bash
export MC_ROUTE_HOST="$(oc get route bamoe-management-console -n "$RUNTIME_NS" -o jsonpath='{.spec.host}')"
```

```bash
export MC_URL="https://${MC_ROUTE_HOST}"
```

```bash
printf 'MC_URL=%s\n' "$MC_URL"
```

외부 HTTPS와 인증서를 확인한다.

```bash
curl \
  --fail \
  --silent \
  --show-error \
  --output /dev/null \
  --write-out 'HTTP_STATUS=%{http_code}\n' \
  --retry 10 \
  --retry-delay 3 \
  "$MC_URL/"
```

정상은 `HTTP_STATUS=200`이며 인증서 오류가 없다. `-k`로 우회하지 않는다.

MCP Route가 실제로 없는지 exact-name으로 확인한다.

```bash
oc get route bamoe-mcp-server \
  -n "$RUNTIME_NS" \
  --ignore-not-found \
  -o name
```

정상 관찰값은 빈 출력이다.

### 11.4 Management Console에 Business Service 등록

현재 Business Service에는 Data Index, process persistence, database 구성이 없다.
이 단계는 Management Console에 Business Service URL을 사전 등록하고 브라우저
CORS를 연결하는 준비다. Process Definitions/Instances의 전체 운영 관리 기능이
완성됐다는 의미는 아니다.

Business Service Route를 조회한다.

```bash
oc get route customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,HOST:.spec.host,TLS:.spec.tls.termination'
```

외부 Business Service URL을 만든다.

```bash
export APP_ROUTE_HOST="$(oc get route customer-rule-poc -n "$APP_NS" -o jsonpath='{.spec.host}')"
```

```bash
export APP_BASE_URL="https://${APP_ROUTE_HOST}"
```

```bash
printf 'APP_BASE_URL=%s\n' "$APP_BASE_URL"
```

일반 TLS로 OpenAPI를 읽을 수 있는지 확인한다.

```bash
curl \
  --fail \
  --silent \
  --show-error \
  "${APP_BASE_URL}/v3/api-docs" \
  | jq -e '.paths | length > 0'
```

Management Console 연결값은 재적용 시 사라지는 수동 `oc set env`가 아니라
version 관리되는 `products/runtime/management-console.yaml`에 선언한다. manifest
값을 먼저 확인한다.

```bash
rg -n \
  'RUNTIME_TOOLS_MANAGEMENT_CONSOLE_MANAGED_BUSINESS_SERVICES|customer-rule-poc\\.apps\\.' \
  deploy/openshift/products/runtime/management-console.yaml
```

실제 Deployment의 등록값을 읽는다.

```bash
export LIVE_MANAGED_SERVICES_JSON="$(
  oc set env \
    deployment/bamoe-management-console \
    -n "$RUNTIME_NS" \
    --list \
  | sed -n \
      's/^RUNTIME_TOOLS_MANAGEMENT_CONSOLE_MANAGED_BUSINESS_SERVICES=//p'
)"
```

현재 Route URL과 정확히 같은 JSON인지 검증한다.

```bash
printf '%s\n' "$LIVE_MANAGED_SERVICES_JSON" \
  | jq -e \
      --arg app_url "$APP_BASE_URL" \
      '
        . == [
          {
            name: "SKT Customer Rule PoC",
            businessServiceUrl: $app_url
          }
        ]
      '
```

정상 출력은 `true`다. 다르면 live Deployment를 즉석 patch하지 않는다. version
관리되는 manifest의 URL을 실제 Route에 맞게 고친 뒤 Runtime Kustomize
server-side dry-run, apply, rollout 순서로 다시 반영한다.

### 11.5 MCP Server의 내부 OpenAPI 연결 검증

MCP는 서버에서 Business Service OpenAPI를 읽으므로 공개 Route가 아닌 내부 Service
DNS를 사용한다. Spring Boot의 OpenAPI 경로는 `/v3/api-docs`다.

manifest에 선언한 URL을 shell 변수로 만든다.

```bash
export APP_OPENAPI_INTERNAL_URL="http://customer-rule-poc.${APP_NS}.svc.cluster.local:8080/v3/api-docs"
```

Runtime Project 안에서 같은 URL을 검증할 진단 Pod가 남아 있는지 조회한다.

```bash
oc get pod runtime-openapi-check \
  -n "$RUNTIME_NS" \
  --ignore-not-found
```

같은 이름이 있으면 정확한 Pod 하나를 삭제한다.

```bash
oc delete pod runtime-openapi-check \
  -n "$RUNTIME_NS" \
  --ignore-not-found
```

내부 URL을 읽는 일회성 Pod를 만든다.

```bash
oc run runtime-openapi-check \
  -n "$RUNTIME_NS" \
  --image=registry.access.redhat.com/ubi9/ubi:9.6 \
  --restart=Never \
  --command -- \
  curl \
    --fail \
    --silent \
    --show-error \
    "$APP_OPENAPI_INTERNAL_URL"
```

Pod가 성공 종료할 때까지 기다린다.

```bash
oc wait pod/runtime-openapi-check \
  -n "$RUNTIME_NS" \
  --for=jsonpath='{.status.phase}'=Succeeded \
  --timeout=5m
```

OpenAPI endpoint 수를 확인한다.

```bash
oc logs pod/runtime-openapi-check \
  -n "$RUNTIME_NS" \
  | jq -e '.paths | length > 0'
```

진단 Pod를 삭제한다.

```bash
oc delete pod runtime-openapi-check -n "$RUNTIME_NS"
```

MCP Deployment에 저장된 연결 URL과 보안 상태만 읽는다.

```bash
oc set env \
  deployment/bamoe-mcp-server \
  -n "$RUNTIME_NS" \
  --list \
  | rg 'MCP_SERVER_(OPENAPI_URLS|SECURITY_ENABLED|SECURITY_AUTH_PERMISSION)'
```

정상값:

```text
MCP_SERVER_OPENAPI_URLS=http://customer-rule-poc.bamoe-poc.svc.cluster.local:8080/v3/api-docs
MCP_SERVER_SECURITY_ENABLED=false
MCP_SERVER_SECURITY_AUTH_PERMISSION=permit
```

MCP 시작 log에서 OpenAPI fetch 또는 parse 오류가 없는지 확인한다.

```bash
oc logs \
  deployment/bamoe-mcp-server \
  -n "$RUNTIME_NS" \
  --tail=200
```

MCP는 시작할 때 OpenAPI를 읽고 내부 상태를 자동 갱신하지 않는다. DMN/BPMN 또는
OpenAPI가 바뀐 뒤에는 다음 명령으로 MCP만 다시 시작한다.

```bash
oc rollout restart deployment/bamoe-mcp-server -n "$RUNTIME_NS"
```

```bash
oc rollout status \
  deployment/bamoe-mcp-server \
  -n "$RUNTIME_NS" \
  --timeout=8m
```

모델을 바꾸지 않았다면 위 restart 두 명령은 지금 실행하지 않아도 된다.

여기까지의 필수 Gate는 “MCP Pod가 Business Service OpenAPI를 읽고 시작했다”는
것을 검증한다. 실제 MCP client의 initialize와 tool discovery까지 검증했다는
뜻은 아니다. Tech Preview client 연동을 추가로 확인하고 싶을 때만 외부 Route를
만들지 않고 port-forward를 사용한다.

별도 terminal에서 내부 MCP Service를 Mac에 연결한다.

```bash
oc port-forward \
  service/bamoe-mcp-server \
  -n "$RUNTIME_NS" \
  18084:8080
```

Node.js가 준비된 또 다른 terminal에서 공식 MCP Inspector를 실행한다.

```bash
npx -y @modelcontextprotocol/inspector@latest
```

Inspector UI에서 transport를 **Streamable HTTP**, URL을
`http://127.0.0.1:18084/mcp`로 지정하고 initialize 후 tools 목록이 생성되는지만
확인한다. 이 단계에서는 Process tool을 실행하지 않는다. 확인이 끝나면
port-forward terminal에서 `Ctrl+C`를 누른다. Inspector는 선택 검증이며, 실패했다고
MCP Route를 공개하거나 보안을 끄는 설정을 추가하지 않는다.

### 11.6 Management Console origin만 앱 CORS에 허용

앱 CORS origin도 재적용 시 사라지는 live patch가 아니라
`base/configmap.yaml`에 선언한다. version 관리되는 값을 확인한다.

```bash
rg -n \
  'BAMOE_CORS_ALLOWED_ORIGIN_PATTERNS' \
  deploy/openshift/base/configmap.yaml
```

live ConfigMap 값을 변수로 읽는다.

```bash
export LIVE_APP_CORS_ORIGIN="$(
  oc get configmap customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.data.BAMOE_CORS_ALLOWED_ORIGIN_PATTERNS}'
)"
```

Management Console의 실제 origin과 비교한다.

```bash
if [ "$LIVE_APP_CORS_ORIGIN" = "$MC_URL" ]; then
  printf 'APP_CORS_WIRING_GATE=PASS\n'
else
  printf 'APP_CORS_WIRING_GATE=FAIL\n' >&2
fi
```

`FAIL`이면 즉석 `oc patch`로 우회하지 않는다. 실제 `MC_URL`에 맞게 version 관리
manifest를 고치고 §14.5의 현재 불변 image 보존 절차로 app manifest를
server-side dry-run/apply한 뒤 rollout을 확인한다.

브라우저에서 `MC_URL`을 열고 사전 등록된 `SKT Customer Rule PoC` 항목이 보이는지
확인한다. 현재 앱이 persistence 기반 Management Console 기능 전체를 제공하지
않는다는 범위는 고객에게 함께 설명한다.

**Gate**

- Management Console과 MCP Deployment가 `READY=1`, `AVAILABLE=1`이다.
- Management Console Route가 `Admitted=True`이고 일반 TLS로 열린다.
- Management Console 등록 URL과 앱 CORS origin이 정확히 일치한다.
- Runtime 진단 Pod에서 내부 OpenAPI `.paths` 검증이 성공한다.
- MCP 환경변수가 내부 Service URL을 사용하고 log에 fetch/parse 오류가 없다.
- Maven Repository와 MCP Server에는 외부 Route가 없다.
- 무인증 Management Console Route는 합성 데이터 PoC의 임시 노출이며 시연 종료
  즉시 제거할 대상으로 기록했다.
- MCP는 Technology Preview이고 현재 앱의 persistence 기반 process 관리는 범위
  밖임을 기록했다.

직접 배포 YAML을 다시 적용한 뒤에도 Management Console 등록값과 앱 CORS 값을
항상 다시 조회한다. Route domain이나 Business Service Route가 바뀌면 §11.4와
§11.6을 다시 수행한다.

§11에서 적용한 Runtime render 파일은 prefix, 소유권, 일반 파일 여부를 확인한 뒤
제거한다.

```bash
case "${BAMOE_RUNTIME_RENDERED:-}" in
  /tmp/bamoe-runtime-direct.*)
    if [ -f "$BAMOE_RUNTIME_RENDERED" ] \
      && [ -O "$BAMOE_RUNTIME_RENDERED" ] \
      && [ ! -L "$BAMOE_RUNTIME_RENDERED" ]
    then
      unlink "$BAMOE_RUNTIME_RENDERED"
      unset BAMOE_RUNTIME_RENDERED
      printf 'RUNTIME_RENDER_TEMP_CLEANUP_GATE=PASS\n'
    else
      printf 'REFUSE: Runtime render temp ownership or type mismatch\n' >&2
    fi
    ;;
  *)
    printf 'REFUSE: unexpected Runtime render temp path\n' >&2
    ;;
esac
```

## 12. GitHub Actions 자동 재배포 활성화

자동 배포는 `main` commit을 시험하고 두 이미지를 GHCR에 만든 다음,
`customer-rule-mock`과 `customer-rule-poc` Deployment의 image만 변경한다.
Kustomize, Route, RBAC 변경은 자동 적용하지 않는다.

이 섹션에서는 다음 세 scope를 구분한다.

| scope | 저장 항목 |
|---|---|
| repository variable | `OCP_AUTO_DEPLOY` |
| `ocp-poc` Environment variable | ownership marker, API URL, namespace, `oc` version, 앱 URL |
| `ocp-poc` Environment secret | 제한된 OpenShift token, 필요한 경우 API CA |

Secret 값은 `gh secret list`로 읽을 수 없다. 이름이 존재하는지와 실제 workflow가
인증에 성공하는지만 확인한다. token 명령 전후에 `set -x`를 사용하지 않는다.

추천 세션 F를 새 terminal에서 시작했다면 먼저 환경 파일이 있는 프로젝트 root로
이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

이 세션에서 사용할 namespace와 repository 변수를 다시 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

필수 값, `oc` client version, 로그인 API server를 검증한다.

```bash
bamoe_check_env
```

### 12.1 대상 repository와 자동 배포 현재 상태 조회

독립 GitHub 작업 사본으로 이동한다.

```bash
cd "$GITHUB_WORK_DIR"
```

현재 작업 사본이 의도한 GitHub repository에 연결됐는지 identity만 검증한다.

```bash
test "$(gh repo view --json nameWithOwner --jq '.nameWithOwner')" = "${GITHUB_OWNER}/${GITHUB_REPO}"
```

출력 없이 성공해야 한다. 실패하면 자동 배포 설정을 시작하지 않는다.

현재 branch를 조회한다.

```bash
git branch --show-current
```

repository가 private인지 조회한다.

```bash
gh repo view "${GITHUB_OWNER}/${GITHUB_REPO}" --json nameWithOwner,isPrivate,url
```

현재 `main` SHA를 기록한다.

```bash
git rev-parse HEAD
```

자동 배포 flag를 조회한다.

```bash
gh variable get OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

최초 설정 중에는 `false`여야 한다. repository, branch, private 여부 또는 flag가
기대와 다르면 중단한다.

### 12.2 GitHub Actions 최소 권한 RBAC 적용

`ServiceAccount`는 자동화가 사용할 OCP 신원이고, `Role`은 한 Project 안에서 허용할
동작의 목록이며, `RoleBinding`은 그 신원에 그 권한을 연결한다. 세 리소스 중
하나라도 빠지면 GitHub Actions는 의도한 권한으로 동작하지 않는다.

manifest가 만들 세 resource 이름을 조회한다.

```bash
oc create --dry-run=client -n "$APP_NS" -f deploy/openshift/github-actions-rbac.yaml -o name
```

기대값은 같은 이름의 ServiceAccount, Role, RoleBinding 세 개다.
이 repository의 manifest는 RoleBinding subject namespace를 `bamoe-poc`으로
고정하므로 다음 값도 반드시 같아야 한다.

```bash
printf 'APP_NS=%s\n' "$APP_NS"
```

현재 같은 이름의 resource가 있는지 이름과 ownership label로 조회한다.

```bash
oc get serviceaccount github-actions-deployer \
  -n "$APP_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,PART_OF:.metadata.labels.app\.kubernetes\.io/part-of'
```

```bash
oc get role github-actions-deployer \
  -n "$APP_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,PART_OF:.metadata.labels.app\.kubernetes\.io/part-of'
```

```bash
oc get rolebinding github-actions-deployer \
  -n "$APP_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,PART_OF:.metadata.labels.app\.kubernetes\.io/part-of,ROLE:.roleRef.name,SUBJECT:.subjects[0].name,SUBJECT_NS:.subjects[0].namespace'
```

없으면 빈 출력이 정상이다. 하나라도 존재하면 `PART_OF`가
`bamoe-customer-rule-poc`이고 RoleBinding은
`Role/github-actions-deployer`를 같은 namespace의
`ServiceAccount/github-actions-deployer`에 연결해야 한다.

ownership과 RoleBinding 계약을 기계적으로 검사한다.

```bash
ACTIONS_NAMESPACE_OWNER="$(
  oc get namespace "$APP_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)"
ACTIONS_SA_NAME="$(
  oc get serviceaccount github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.name}'
)"
ACTIONS_SA_PART_OF="$(
  oc get serviceaccount github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}'
)"
ACTIONS_ROLE_NAME="$(
  oc get role github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.name}'
)"
ACTIONS_ROLE_PART_OF="$(
  oc get role github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}'
)"
ACTIONS_BINDING_NAME="$(
  oc get rolebinding github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.name}'
)"
ACTIONS_BINDING_PART_OF="$(
  oc get rolebinding github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}'
)"
ACTIONS_BINDING_CONTRACT='absent'

if [ -n "$ACTIONS_BINDING_NAME" ]; then
  if oc get rolebinding github-actions-deployer \
      -n "$APP_NS" \
      -o json \
    | jq -e \
        --arg namespace "$APP_NS" \
        '
          .roleRef.kind == "Role"
          and .roleRef.name == "github-actions-deployer"
          and (.subjects | length) == 1
          and .subjects[0].kind == "ServiceAccount"
          and .subjects[0].name == "github-actions-deployer"
          and .subjects[0].namespace == $namespace
        ' \
    >/dev/null
  then
    ACTIONS_BINDING_CONTRACT='valid'
  else
    ACTIONS_BINDING_CONTRACT='invalid'
  fi
fi

if [ "$ACTIONS_NAMESPACE_OWNER" = 'bamoe-poc-guide' ] \
  && { [ -z "$ACTIONS_SA_NAME" ] \
    || [ "$ACTIONS_SA_PART_OF" = 'bamoe-customer-rule-poc' ]; } \
  && { [ -z "$ACTIONS_ROLE_NAME" ] \
    || [ "$ACTIONS_ROLE_PART_OF" = 'bamoe-customer-rule-poc' ]; } \
  && { [ -z "$ACTIONS_BINDING_NAME" ] \
    || { [ "$ACTIONS_BINDING_PART_OF" = 'bamoe-customer-rule-poc' ] \
      && [ "$ACTIONS_BINDING_CONTRACT" = 'valid' ]; }; }
then
  export ACTIONS_RBAC_OWNERSHIP_OK=true
  printf 'ACTIONS_RBAC_OWNERSHIP_GATE=PASS\n'
else
  export ACTIONS_RBAC_OWNERSHIP_OK=false
  printf 'ACTIONS_RBAC_OWNERSHIP_GATE=FAIL\n' >&2
fi
```

`FAIL`이면 같은 이름의 기존 리소스를 덮어쓰지 않고 소유자를 확인한다.

API server에서 manifest를 검증한다.

```bash
oc apply --dry-run=server -n "$APP_NS" -f deploy/openshift/github-actions-rbac.yaml
```

검증된 manifest 한 개는 ownership Gate가 같은 terminal에서 `PASS`였을 때만
적용한다.

```bash
if [ "$ACTIONS_RBAC_OWNERSHIP_OK" = true ]; then
  oc apply \
    -n "$APP_NS" \
    -f deploy/openshift/github-actions-rbac.yaml
else
  printf 'REFUSE: GitHub Actions RBAC ownership was not validated\n' >&2
fi
```

ServiceAccount를 관찰한다.

```bash
oc get serviceaccount github-actions-deployer -n "$APP_NS" -o wide
```

Role 규칙을 관찰한다.

```bash
oc describe role github-actions-deployer -n "$APP_NS"
```

RoleBinding의 subject와 Role을 관찰한다.

```bash
oc describe rolebinding github-actions-deployer -n "$APP_NS"
```

권한을 대신 검사하려면 현재 사용자에게 ServiceAccount impersonation 권한이
필요하다. 먼저 그 권한만 조회한다.

```bash
oc auth can-i impersonate serviceaccounts/github-actions-deployer -n "$APP_NS"
```

결과가 `no`이면 Role이 틀렸다는 뜻이 아니다. 다음 `--as` 명령을 실행하지 말고
플랫폼 관리자에게 같은 여덟 검사를 요청한다. 결과가 `yes`일 때만 아래를 하나씩
실행한다.

```bash
export ACTIONS_SA="system:serviceaccount:${APP_NS}:github-actions-deployer"
```

Deployment 조회 권한:

```bash
oc auth can-i get deployments.apps -n "$APP_NS" --as="$ACTIONS_SA"
```

Deployment 목록 권한:

```bash
oc auth can-i list deployments.apps -n "$APP_NS" --as="$ACTIONS_SA"
```

Deployment watch 권한:

```bash
oc auth can-i watch deployments.apps -n "$APP_NS" --as="$ACTIONS_SA"
```

앱 Deployment patch 권한:

```bash
oc auth can-i patch deployment/customer-rule-poc -n "$APP_NS" --as="$ACTIONS_SA"
```

Mock Deployment patch 권한:

```bash
oc auth can-i patch deployment/customer-rule-mock -n "$APP_NS" --as="$ACTIONS_SA"
```

새 Deployment 생성 거부:

```bash
oc auth can-i create deployments.apps -n "$APP_NS" --as="$ACTIONS_SA"
```

Deployment 삭제 거부:

```bash
oc auth can-i delete deployments.apps -n "$APP_NS" --as="$ACTIONS_SA"
```

Secret 조회 거부:

```bash
oc auth can-i get secrets -n "$APP_NS" --as="$ACTIONS_SA"
```

기대 순서는 다음과 같다.

```text
yes
yes
yes
yes
yes
no
no
no
```

실제 Actions 배포 성공은 positive 권한을 확인하지만 `create/delete/secret=no`
경계까지 증명하지는 않는다. impersonation이 불가능하면 관리자 확인을 생략하지
않는다.

**Gate**

- ServiceAccount, Role, RoleBinding의 이름과 연결 대상이 manifest와 같다.
- 플랫폼 관리자 또는 impersonation 가능한 사용자가
  `yes yes yes yes yes no no no`를 확인했다.
- Actions 계정은 두 Deployment의 image patch 외에 생성·삭제·Secret 조회를 할 수
  없다.

### 12.3 GitHub Environment와 비밀이 아닌 값 등록

`ocp-poc` Environment의 존재 여부와 이 가이드의 ownership marker를 함께
확인한다. 이름이 같다는 이유만으로 기존 Environment를 인수하지 않는다.

```bash
if gh api \
  "repos/${GITHUB_OWNER}/${GITHUB_REPO}/environments/ocp-poc" \
  >/dev/null 2>&1
then
  export OCP_ENV_CREATED_NOW=false
  printf 'OCP_ENVIRONMENT=EXISTS\n'
else
  export OCP_ENV_CREATED_NOW=true
  printf 'OCP_ENVIRONMENT=ABSENT\n'
fi
```

현재 marker를 읽는다. 아직 없으면 빈 문자열이 정상이다.

```bash
export OCP_ENV_OWNER_MARKER="$(
  gh variable get BAMOE_GUIDE_OWNER \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc \
    2>/dev/null \
  || true
)"
```

Environment가 없었을 때만 생성하고 marker를 기록한다. 이미 존재하며 marker가
정확하면 재사용한다. 그 외에는 아무것도 덮어쓰지 않는다.

```bash
if [ "$OCP_ENV_CREATED_NOW" = true ]; then
  gh api \
    --method PUT \
    "repos/${GITHUB_OWNER}/${GITHUB_REPO}/environments/ocp-poc" \
    >/dev/null
  gh variable set BAMOE_GUIDE_OWNER \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc \
    --body bamoe-poc-guide
  export OCP_ENV_OWNER_MARKER='bamoe-poc-guide'
  printf 'OCP_ENVIRONMENT_OWNERSHIP_GATE=PASS (created)\n'
elif [ "$OCP_ENV_OWNER_MARKER" = 'bamoe-poc-guide' ]; then
  printf 'OCP_ENVIRONMENT_OWNERSHIP_GATE=PASS (owned reuse)\n'
else
  printf 'OCP_ENVIRONMENT_OWNERSHIP_GATE=FAIL (existing unowned environment)\n' >&2
fi
```

`FAIL`이면 아래 variable/secret 등록으로 이동하지 않는다. 먼저
`gh variable list ... --env ocp-poc`와 `gh secret list ... --env ocp-poc`로 이름만
확인하고 repository 관리자에게 소유자를 확인한다. 이 전용 PoC가 이전 실습에서
만든 Environment임을 확인받은 경우에만 `BAMOE_GUIDE_OWNER=bamoe-poc-guide`
marker를 명시적으로 등록한 뒤 이 절을 다시 시작한다.

현재 앱 Route를 조회한다.

```bash
oc get route customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,HOST:.spec.host,TLS:.spec.tls.termination'
```

Route host를 변수로 읽는다.

```bash
export APP_ROUTE_HOST="$(oc get route customer-rule-poc -n "$APP_NS" -o jsonpath='{.spec.host}')"
```

앱 URL을 만든다.

```bash
export APP_BASE_URL="https://${APP_ROUTE_HOST}"
```

cluster minor version을 조회한다.

```bash
oc get clusterversion version -o custom-columns='VERSION:.status.desired.version'
```

workflow에 설치할 `oc` minor를 만든다.

```bash
export OPENSHIFT_OC_VERSION="$(
  oc get clusterversion version \
    -o jsonpath='{.status.desired.version}' \
    | awk -F. '{print $1 "." $2}'
)"
```

현재 Environment variable 이름과 값을 조회한다. 출력에
`BAMOE_GUIDE_OWNER=bamoe-poc-guide`가 있어야 한다.

```bash
gh variable list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

API server variable 한 개를 등록한다.

```bash
gh variable set OPENSHIFT_SERVER --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc --body "$OCP_API_SERVER"
```

namespace variable 한 개를 등록한다.

```bash
gh variable set OPENSHIFT_NAMESPACE --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc --body "$APP_NS"
```

`oc` minor variable 한 개를 등록한다.

```bash
gh variable set OPENSHIFT_OC_VERSION \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --env ocp-poc \
  --body "$OPENSHIFT_OC_VERSION"
```

외부 앱 URL variable 한 개를 등록한다.

```bash
gh variable set APP_BASE_URL --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc --body "$APP_BASE_URL"
```

marker와 네 연결값을 관찰한다.

```bash
gh variable list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

이 가이드는 scope 혼동을 막기 위해 연결 variable과 Secret을 모두
`ocp-poc` Environment에만 등록한다. GitHub plan이나 조직 정책 때문에
Environment variable/secret을 사용할 수 없다면 repository scope로 조용히
fallback하지 말고 여기서 중단한다. workflow와 cleanup 절차를 같은 scope 계약으로
별도 review한 뒤 문서를 함께 바꿔야 한다.

**Gate**

- `OPENSHIFT_SERVER`가 현재 API server와 같다.
- `OPENSHIFT_NAMESPACE`가 `bamoe-poc`이다.
- `OPENSHIFT_OC_VERSION`이 cluster minor와 같다.
- `APP_BASE_URL`이 현재 HTTPS Route다.
- `BAMOE_GUIDE_OWNER`가 `bamoe-poc-guide`다.

### 12.4 GitHub-hosted runner의 Route TLS 확인

Mac과 GitHub-hosted runner의 trust store는 다를 수 있다. 자동 배포를 켜기 전에
runner에서 공개 Route를 한 번 검증한다.

현재 remote `main`의 전체 SHA를 기록한다. 이후 다른 과거 run을 잘못 선택하지
않기 위한 기준값이다.

```bash
export ROUTE_TLS_EXPECTED_SHA="$(
  gh api \
    "repos/${GITHUB_OWNER}/${GITHUB_REPO}/commits/main" \
    --jq '.sha'
)"
```

workflow를 한 번 실행한다. 이 명령은 배포를 변경하지 않고 Route만 조회한다.

```bash
gh workflow run route-tls-preflight.yml --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --ref main
```

최근 실행을 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow route-tls-preflight.yml \
  --event workflow_dispatch \
  --branch main \
  --limit 5
```

GitHub가 새 run을 목록에 반영하는 데 몇 초 걸릴 수 있다. 방금 실행한 행이 아직
없으면 workflow를 다시 시작하지 말고 같은 `gh run list` 명령만 잠시 후
재실행한다.

방금 실행한 행의 database ID를 직접 복사해 기록한다.

```bash
export ROUTE_TLS_RUN_ID='<방금 실행한 route-tls-preflight run ID>'
```

숫자 ID인지 먼저 확인한다.

```bash
if printf '%s\n' "$ROUTE_TLS_RUN_ID" | rg -q -x '[0-9]+'; then
  printf 'ROUTE_TLS_RUN_ID_GATE=PASS\n'
else
  printf 'ROUTE_TLS_RUN_ID_GATE=FAIL\n' >&2
fi
```

해당 run 하나를 관찰한다.

```bash
gh run watch "$ROUTE_TLS_RUN_ID" --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --exit-status
```

결론을 다시 조회한다.

```bash
gh run view "$ROUTE_TLS_RUN_ID" --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --json headSha,status,conclusion,url
```

같은 run의 SHA·상태·결론뿐 아니라 workflow 이름, 수동 실행 event, 정확한 job을
기계적으로 검증한다.

```bash
ROUTE_TLS_RUN_JSON="$(
  gh run view "$ROUTE_TLS_RUN_ID" \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --json headSha,status,conclusion,event,workflowName,jobs,url
)"

if printf '%s\n' "$ROUTE_TLS_RUN_JSON" \
  | jq -e \
      --arg sha "$ROUTE_TLS_EXPECTED_SHA" \
      '
        .headSha == $sha
        and .status == "completed"
        and .conclusion == "success"
        and .event == "workflow_dispatch"
        and .workflowName == "Verify public OpenShift Route TLS"
        and (
          [
            .jobs[]
            | select(
                .name == "Verify Route from a GitHub-hosted runner"
                and .conclusion == "success"
              )
          ]
          | length
        ) == 1
      ' \
    >/dev/null
then
  printf 'ROUTE_TLS_RUN_IDENTITY_GATE=PASS\n'
else
  printf 'ROUTE_TLS_RUN_IDENTITY_GATE=FAIL\n' >&2
fi
```

실패하면 log를 조회한다.

```bash
gh run view "$ROUTE_TLS_RUN_ID" --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --log-failed
```

DNS 또는 인증서 오류가 있으면 ingress Route에 public certificate를 구성한다.
`curl -k`나 TLS 검증 비활성화로 통과시키지 않는다.

**Gate:** 숫자 run ID이며 같은 run에서 예상 SHA, workflow 이름,
`workflow_dispatch`, 완료·성공, 정확한 Route 검증 job 성공이 확인된다.

### 12.5 OpenShift API TLS와 CA 선택

현재 cluster는 §1에서 일반 trust로 API TLS 검증이 성공했다. 따라서 ordinary
public trust 경로를 본문 기본값으로 사용한다.

API 인증서가 일반 trust로 검증되는지 다시 조회한다.

```bash
curl --silent --show-error --output /dev/null --connect-timeout 10 "${OCP_API_SERVER}/version"
```

이 명령이 인증서 오류 없이 끝나면 `OPENSHIFT_CA_DATA`는 필요 없다. 먼저
Environment secret 이름만 조회한다.

```bash
gh secret list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

`OPENSHIFT_CA_DATA`가 없다면 정상이며 다음 repository-scope 조회로 이동한다.
있다면 같은 이름만 보고 바로 삭제하지 않는다. 이 가이드가 과거에 만든
Environment secret임을 repository 관리자에게 확인한 뒤에만 다음 확인값을
`yes`로 바꾼다.

```bash
export CONFIRM_REMOVE_GUIDE_CA='no'
```

존재 여부, Environment ownership, 명시적 확인을 삭제와 같은 조건문에서
검사한다.

```bash
CA_SECRET_PRESENT="$(
  gh secret list \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc \
    --json name \
    --jq '.[] | select(.name == "OPENSHIFT_CA_DATA") | .name'
)"
OCP_ENV_OWNER_MARKER="$(
  gh variable get BAMOE_GUIDE_OWNER \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc \
    2>/dev/null \
  || true
)"

if [ -z "$CA_SECRET_PRESENT" ]; then
  printf 'OPENSHIFT_CA_DATA=ABSENT\n'
elif [ "$OCP_ENV_OWNER_MARKER" != 'bamoe-poc-guide' ]; then
  printf 'REFUSE: ocp-poc Environment is not owned by this guide\n' >&2
elif [ "$CONFIRM_REMOVE_GUIDE_CA" = 'yes' ]; then
  gh secret delete OPENSHIFT_CA_DATA \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc
  printf 'OPENSHIFT_CA_DATA=REMOVED_FROM_OWNED_ENVIRONMENT\n'
else
  printf 'REFUSE: confirm the existing CA secret owner before deletion\n' >&2
fi
```

repository-level Secret 이름도 별도로 조회한다.

```bash
gh secret list --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

이 가이드는 repository-level `OPENSHIFT_CA_DATA`를 만들거나 삭제하지 않는다.
그 scope에 같은 이름이 보이면 다른 workflow가 사용할 수 있으므로 자동 배포를
켜지 말고 repository 관리자와 소유자를 확인한다. Secret 값은 어느 단계에서도
출력하지 않는다.

#### private CA cluster에서만 사용하는 조건부 분기

향후 다른 cluster에서 ordinary trust 검사가 인증서 오류로 실패할 때만 이 분기를
사용한다. `insecure_skip_tls_verify`를 사용하지 않는다.

현재 kubeconfig의 API CA base64를 변수로 읽는다.

```bash
export OCP_CA_DATA_BASE64="$(
  oc config view \
    --raw \
    --flatten \
    -o json \
    | jq -r \
        --arg server "$OCP_API_SERVER" \
        '[.clusters[] | select(.cluster.server == $server) | .cluster["certificate-authority-data"]][0] // empty'
)"
```

값이 비어 있지 않은지 확인한다.

```bash
test -n "$OCP_CA_DATA_BASE64"
```

PEM을 shell 변수로 decode한다. CA 인증서는 비밀키가 아니지만 출력하지 않는다.

```bash
export OCP_CA_PEM="$(printf '%s' "$OCP_CA_DATA_BASE64" | openssl base64 -d -A)"
```

PEM이 유효한 인증서인지 subject만 확인한다.

```bash
printf '%s' "$OCP_CA_PEM" | openssl x509 -noout -subject
```

PEM을 Environment secret으로 직접 전달한다.

```bash
printf '%s' "$OCP_CA_PEM" | gh secret set OPENSHIFT_CA_DATA --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

메모리의 CA 변수 두 개를 지운다.

```bash
unset OCP_CA_PEM OCP_CA_DATA_BASE64
```

등록된 이름만 확인한다.

```bash
gh secret list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

등록 후 `BAMOE_GUIDE_OWNER=bamoe-poc-guide` marker가 여전히 있는지 확인한다.
Environment secret을 사용할 수 없다면 repository scope로 fallback하지 않고
§12.3의 scope 계약을 다시 review한다.

### 12.6 제한된 OpenShift token 등록

ServiceAccount가 존재하는지 조회한다.

```bash
oc get serviceaccount github-actions-deployer -n "$APP_NS"
```

token 요청 권한을 조회한다.

```bash
oc auth can-i create serviceaccounts/token -n "$APP_NS"
```

결과가 `yes`여야 한다. 기존 GitHub secret 이름과 Environment ownership을
조회한다.

```bash
gh secret list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

```bash
export OCP_ENV_OWNER_MARKER="$(
  gh variable get BAMOE_GUIDE_OWNER \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc \
    2>/dev/null \
  || true
)"
```

기존 `OPENSHIFT_TOKEN`이 없으면 첫 등록으로 진행한다. 이미 있다면 이번 가이드가
관리하는 자동 배포 token을 의도적으로 교체하는 경우에만 다음 값을 `yes`로
바꾼다.

```bash
export CONFIRM_REPLACE_GUIDE_TOKEN='no'
```

다음 한 명령은 zsh의 `pipefail`을 켠 별도 shell에서 token을 GitHub로 바로
전달한다. token은 화면, 현재 shell 변수, 파일에 저장되지 않는다. token 생성과
GitHub 저장 중 하나라도 실패하면 명령 전체가 실패한다. 실행할 때마다 새 bearer
token이 생기며, GitHub secret을 덮어써도 이전 token은 자동 폐기되지 않고 자체
만료까지 유효할 수 있으므로 불필요하게 반복하지 않는다.

```bash
TOKEN_SECRET_PRESENT="$(
  gh secret list \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc \
    --json name \
    --jq '.[] | select(.name == "OPENSHIFT_TOKEN") | .name'
)"

if [ "$OCP_ENV_OWNER_MARKER" != 'bamoe-poc-guide' ]; then
  printf 'REFUSE: ocp-poc Environment is not owned by this guide\n' >&2
elif [ -n "$TOKEN_SECRET_PRESENT" ] \
  && [ "$CONFIRM_REPLACE_GUIDE_TOKEN" != 'yes' ]
then
  printf 'REFUSE: confirm intentional replacement of the existing guide token\n' >&2
else
  zsh -o pipefail -c \
    'oc create token github-actions-deployer -n "$APP_NS" --duration=720h |
     gh secret set OPENSHIFT_TOKEN --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc'
fi
```

명령이 실패하면 자동 배포를 켜지 말고 token 요청 권한과 `gh` 인증을 각각
확인한다.

`720h`는 요청값이며 cluster 정책이 더 짧은 만료를 적용할 수 있다. 인증 만료가
발생하면 같은 명령으로 교체하고, 유출 시에는 GitHub secret 삭제와 함께
ServiceAccount를 삭제·재생성해 기존 token을 무효화한다. 운영 전환 시에는 장기
token 대신 GitHub OIDC federation을 설계한다.

등록된 이름만 관찰한다.

```bash
gh secret list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

Environment secret을 사용할 수 없으면 repository scope에 같은 이름을 추가하지
않는다. §12.3의 단일 scope 계약을 다시 review한다.

**Gate**

- `OPENSHIFT_TOKEN` 이름이 존재한다.
- ordinary public trust cluster에서는 `OPENSHIFT_CA_DATA`가 없다.
- private CA 분기를 사용한 cluster에서만 `OPENSHIFT_CA_DATA`가 존재한다.
- token 값 자체는 terminal, 문서, 채팅, 파일에 나타나지 않았다.

### 12.7 자동 배포를 켜고 한 번 검증

workflow는 변경 전에 현재 앱·Mock image를 읽고 두 reference가 모두
`sha-<40자리 commit>@sha256:<64자리 digest>` 형식이며 같은 commit 쌍인지
검사한다. 이 Gate를 통과해야만 실패 시 복구할 `previous_*` 값으로 사용하고
첫 `oc set image`를 실행한다. 현재 배포가 `latest`, digest 없는 tag, 서로 다른
commit 또는 예상 밖 registry라면 workflow는 OCP를 바꾸기 전에 실패한다.

현재 repository-level flag를 조회한다.

```bash
gh variable get OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

현재 `main` SHA를 기록한다.

```bash
export AUTO_EXPECTED_SHA="$(
  gh api \
    "repos/${GITHUB_OWNER}/${GITHUB_REPO}/commits/main" \
    --jq '.sha'
)"
```

```bash
printf 'AUTO_EXPECTED_SHA=%s\n' "$AUTO_EXPECTED_SHA"
```

concurrency 대기열에 같은 workflow가 있는지 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --status queued \
  --limit 5
```

이미 실행 중인 같은 workflow도 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --status in_progress \
  --limit 5
```

queued 또는 in-progress run이 하나라도 있으면 새 run을 만들지 말고 먼저 완료
결과를 확인한다. workflow의 concurrency는 실행 중인 run을 자동 취소하지 않으므로,
대기 중인 run도 나중에 배포될 수 있다.

필수 RBAC, variable, TLS, Secret Gate가 모두 통과했고 위 두 run 목록이 모두
비어 있을 때만 flag 한 개를 켠다.

```bash
gh variable set OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --body true
```

저장된 값을 관찰한다.

```bash
gh variable get OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

`true`가 아니면 중단한다. 이 지점 이후 terminal을 닫았다면 재개할 때 바로
workflow를 실행하지 않는다. 먼저 queued/in-progress 목록을 다시 확인하고,
이번 배포를 계속하지 않을 생각이면 §14.6의 명령으로 flag를 `false`로 되돌린다.

build/deploy workflow를 `main`에서 한 번 실행한다. 이 명령은 새 image를 만들고
성공하면 OCP Deployment 두 개를 변경하므로 반복 실행하지 않는다.

```bash
gh workflow run build-images.yml --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --ref main
```

최근 workflow를 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --event workflow_dispatch \
  --branch main \
  --limit 5
```

방금 실행한 행이 아직 없으면 새 workflow를 만들지 말고 같은 조회 명령만 잠시 후
재실행한다.

방금 실행한 행의 database ID를 직접 복사한다.

```bash
export AUTO_RUN_ID='<방금 실행한 build-images run ID>'
```

숫자 run ID인지 확인한다.

```bash
if printf '%s\n' "$AUTO_RUN_ID" | rg -q -x '[0-9]+'; then
  printf 'AUTO_RUN_ID_GATE=PASS\n'
else
  printf 'AUTO_RUN_ID_GATE=FAIL\n' >&2
fi
```

정확한 run 하나를 관찰한다.

```bash
gh run watch "$AUTO_RUN_ID" --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --exit-status
```

run의 commit과 job 결과를 조회한다.

```bash
gh run view "$AUTO_RUN_ID" --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --json headSha,status,conclusion,jobs,url
```

같은 run에서 `headSha`, 전체 결론, build/deploy 두 job을 기계적으로 검증한다.

```bash
AUTO_RUN_JSON="$(
  gh run view "$AUTO_RUN_ID" \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --json headSha,status,conclusion,jobs,url
)"

printf '%s\n' "$AUTO_RUN_JSON" \
  | jq -e \
      --arg sha "$AUTO_EXPECTED_SHA" \
      '
        .headSha == $sha
        and .status == "completed"
        and .conclusion == "success"
        and (
          [.jobs[] | select(.name == "build" and .conclusion == "success")]
          | length
        ) == 1
        and (
          [
            .jobs[]
            | select(
                .name == "Deploy immutable images to OpenShift"
                and .conclusion == "success"
              )
          ]
          | length
        ) == 1
      '
```

정상 출력은 `true`다. `false`면 과거 run을 잘못 골랐거나 build/deploy 중 하나가
실패한 것이므로 OCP 상태를 성공으로 판단하지 않는다.

배포된 image를 관찰한다.

```bash
oc get deployment/customer-rule-mock \
  deployment/customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas'
```

container 이름으로 두 reference를 읽고 방금 성공한 run의 commit과 같은지
검증한다.

```bash
AUTO_APP_IMAGE="$(
  oc get deployment/customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="application")].image}'
)"
AUTO_MOCK_IMAGE="$(
  oc get deployment/customer-rule-mock \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="mock")].image}'
)"

if printf '%s\n' "$AUTO_APP_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-poc:sha-${AUTO_EXPECTED_SHA}@sha256:[0-9a-f]{64}" \
  && printf '%s\n' "$AUTO_MOCK_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-mock:sha-${AUTO_EXPECTED_SHA}@sha256:[0-9a-f]{64}"
then
  printf 'AUTO_DEPLOY_IMAGE_IDENTITY_GATE=PASS\n'
else
  printf 'AUTO_DEPLOY_IMAGE_IDENTITY_GATE=FAIL\n' >&2
fi
```

두 image 모두 다음 형태여야 하며 `sha-` 뒤의 40자리 commit이 같다.

```text
ghcr.io/.../customer-rule-poc:sha-<Git commit>@sha256:...
ghcr.io/.../customer-rule-mock:sha-<같은 Git commit>@sha256:...
```

외부 OpenAPI를 관찰한다.

```bash
curl \
  --fail \
  --silent \
  --show-error \
  --retry 12 \
  --retry-delay 5 \
  --retry-all-errors \
  "${APP_BASE_URL}/v3/api-docs" \
  | jq -e '.paths | length > 0'
```

실패하면 자동 배포를 먼저 끈다.

```bash
gh variable set OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --body false
```

실패 log를 조회한다.

```bash
gh run view "$AUTO_RUN_ID" --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --log-failed
```

workflow는 mock digest, 앱 digest 순서로 배포한다. 그 뒤 OpenAPI만 여는 데서
끝내지 않고 고유한 합성 requestId로 Case 04 `FALLBACK_GRANTED` Process POST를
실행해 `policyEvaluationCount=2`, `ALLOW`, `FALLBACK_AUTH_GRANTED`와 비어 있지
않은 `reasonMessage`를 assertion한다. rollout 또는 이 smoke가 실패하면 두
Deployment의 직전 image를 복원한다. 실패 후에는 실제 image와 Ready 상태를 직접
확인하고 원인을 해결한 뒤에만 flag를 다시 켠다.

**Gate**

- RBAC 결과가 `yes yes yes yes yes no no no`다.
- Route TLS preflight가 성공했다.
- 수동 workflow의 build와 deploy가 모두 성공했다.
- run `headSha`가 현재 `main` SHA와 같다.
- 두 Deployment image가 같은 commit의 `@sha256:` digest다.
- `APP_BASE_URL/v3/api-docs`가 계속 성공한다.
- workflow의 Case 04 fallback Process assertion이 성공했다.

참고:

- [Red Hat OpenShift CLI 설치 Action](https://github.com/redhat-actions/openshift-tools-installer)
- [Red Hat OpenShift Login Action](https://github.com/redhat-actions/oc-login)
- [GitHub deployment environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)

## 13. Canvas에서 Deploy 버튼 시연

Canvas Deploy는 본선 Spring Boot Deployment를 갱신하지 않는다.
이 repository의 사용자 정의 옵션으로 현재 작업공간 전체를 `bamoe-sandbox`의
임시 JDK 21 Pod에 upload하고 Spring Boot를 실행하는 별도 시연 경로다.

추천 세션 G를 새 terminal에서 시작했다면 먼저 환경 파일이 있는 프로젝트 root로
이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

Canvas와 sandbox에 사용할 환경값을 다시 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

필수 값과 현재 OpenShift 연결을 검증한다.

```bash
bamoe_check_env
```

### 13.1 사용자 정의 배포 계약과 지원 image 사전검증

이 프로젝트에 `.bamoe/dev-deployments`가 있으므로 Canvas의 기본
`Quarkus Blank App`과 `Custom Image` 대신 repository가 정의한 옵션만 표시된다.
먼저 UI가 읽을 실제 값을 확인한다.

```bash
jq '{
  specVersion,
  name,
  image: .parameters.containerImage.defaultValue,
  port: .parameters.containerPort.defaultValue,
  command: .parameters.command.defaultValue,
  healthStatusUrlTemplate,
  deploymentAccessUrlTemplate
}' .bamoe/dev-deployments/openshift/option.json
```

현재 repository와 BAMOE 9.5 accelerator 산출물의 `specVersion`은 `"1"`이다.
일부 공개 문서 예시의 `"0.1"`과 다르더라도 임의로 바꾸지 않는다. 실제 배포에
사용하는 동일 fix pack의 Canvas UI가 이 descriptor를 validation하고
**OpenShift Spring Boot PoC** 카드를 표시하는지를 최종 Gate로 삼는다. UI가
거부하면 오류를 기록하고 같은 Canvas/Accelerator가 새로 생성한 descriptor
schema와 비교한다.

정확한 옵션 이름을 검증한다.

```bash
test "$(
  jq -r '.name' .bamoe/dev-deployments/openshift/option.json
)" = 'OpenShift Spring Boot PoC'
```

JDK 21 지원 image를 정확한 전체 문자열로 검증한다.

```bash
test "$(
  jq -r '.parameters.containerImage.defaultValue' \
    .bamoe/dev-deployments/openshift/option.json
)" = 'quay.io/bamoe/canvas-dev-deployment-base:9.5.0-ibm-0005-jdk21'
```

지원 image에는 `/home/app/mvnw`와 Maven Wrapper가 들어 있다. 전역 `mvn`은
보장되지 않으므로 `./mvnw`를 사용하되, 이 프로젝트에 없는 `development`
profile은 지정하지 않는다.

```bash
test "$(
  jq -r '.parameters.command.defaultValue' \
    .bamoe/dev-deployments/openshift/option.json
)" = './mvnw --settings config/settings-bamoe-openshift.xml -U spring-boot:run -Dspring-boot.run.arguments=--server.address=0.0.0.0'
```

OpenShift 전용 Maven 설정은 Mac의 절대 경로나 localhost가 아니라 Dev Project의
내부 Maven Repository Service를 사용한다.

```bash
rg -n \
  'http://bamoe-maven-repository\.bamoe-devtools\.svc\.cluster\.local:8080/' \
  config/settings-bamoe-openshift.xml
```

```bash
if rg -n '(/Users/|localhost|127\.0\.0\.1|<localRepository>)' \
  config/settings-bamoe-openshift.xml
then
  printf 'GATE=FAIL: local-only Maven setting found\n'
else
  printf 'GATE=PASS: OpenShift Maven setting is portable\n'
fi
```

정상 출력은 URL 행과 `GATE=PASS`다.

sandbox의 quota와 기본 limit를 확인한다.

```bash
oc get resourcequota,limitrange -n "$SANDBOX_NS"
```

사용자 정의 Deployment는 CPU `500m`, memory `1024Mi`를 요청하고 CPU `2`,
memory `2048Mi`를 limit으로 쓰는 Pod 하나를 만든다. quota의 남은 자원이
부족하거나 LimitRange가 이 값과 충돌하면 UI 배포 전에 플랫폼 관리자와 조정한다.

같은 이름의 pull-test Pod가 남아 있는지 조회한다.

```bash
oc get pod canvas-dev-base-pull-test \
  -n "$SANDBOX_NS" \
  --ignore-not-found
```

있으면 정확한 임시 Pod 하나만 삭제한다.

```bash
oc delete pod canvas-dev-base-pull-test \
  -n "$SANDBOX_NS" \
  --ignore-not-found
```

실제 sandbox worker가 지원 image를 pull하고 non-root로 실행할 수 있는지, image가
제공하는 Maven Wrapper가 실제로 기동되는지 확인하는 임시 Pod를 만든다. 프로젝트는
upload하지 않는다.

```bash
oc run canvas-dev-base-pull-test \
  -n "$SANDBOX_NS" \
  --image=quay.io/bamoe/canvas-dev-deployment-base:9.5.0-ibm-0005-jdk21 \
  --restart=Never \
  --command -- \
  sh -c 'cd /home/app && ./mvnw --version && sleep 300'
```

image pull과 Pod 준비를 기다린다.

```bash
oc wait pod/canvas-dev-base-pull-test \
  -n "$SANDBOX_NS" \
  --for=condition=Ready \
  --timeout=5m
```

실제 image와 image ID를 관찰한다.

```bash
oc get pod canvas-dev-base-pull-test \
  -n "$SANDBOX_NS" \
  -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image,IMAGE_ID:.status.containerStatuses[0].imageID'
```

`READY=true`, 정확한 `-jdk21` tag와 `@sha256:` image ID가 보여야 한다. Maven
Wrapper가 출력한 Java/Maven version도 확인한다.

```bash
oc logs pod/canvas-dev-base-pull-test \
  -n "$SANDBOX_NS"
```

로그에 Maven version과 Java 21이 보여야 한다. 단순 파일 존재가 아니라 wrapper
실행까지 성공한 것이다.

확인이 끝난 임시 Pod를 삭제한다.

```bash
oc delete pod canvas-dev-base-pull-test -n "$SANDBOX_NS"
```

sandbox에서 내부 Maven Repository에 접근 가능한지도 별도 진단 Pod로 확인한다.

```bash
oc delete pod canvas-maven-repository-check \
  -n "$SANDBOX_NS" \
  --ignore-not-found
```

```bash
oc run canvas-maven-repository-check \
  -n "$SANDBOX_NS" \
  --image=registry.access.redhat.com/ubi9/ubi:9.6 \
  --restart=Never \
  --command -- \
  curl \
    --fail \
    --silent \
    --show-error \
    --output /dev/null \
    http://bamoe-maven-repository.bamoe-devtools.svc.cluster.local:8080/
```

성공 종료를 기다린다.

```bash
oc wait pod/canvas-maven-repository-check \
  -n "$SANDBOX_NS" \
  --for=jsonpath='{.status.phase}'=Succeeded \
  --timeout=5m
```

진단 Pod를 삭제한다.

```bash
oc delete pod canvas-maven-repository-check -n "$SANDBOX_NS"
```

**Gate:** 사용자 정의 옵션, JDK 21 image, Maven 명령과 내부 repository URL이
정확하고 두 임시 Pod 검증을 통과한 뒤 모두 삭제했다.

### 13.2 sandbox의 Mock Service alias

현재 BPMN은 `http://customer-rule-mock:8091~8094`를 호출한다. sandbox에서도
같은 짧은 이름이 해석되도록 `ExternalName` Service 하나를 만든다.

sandbox ownership을 조회한다.

```bash
oc get namespace "$SANDBOX_NS" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

기존 같은 이름의 Service를 조회한다.

```bash
oc get service customer-rule-mock -n "$SANDBOX_NS" --ignore-not-found -o wide
```

API server에서 alias manifest를 검증한다.

```bash
oc apply --dry-run=server -n "$SANDBOX_NS" -f deploy/openshift/canvas-sandbox-mock-alias.yaml
```

Service 한 개를 적용한다.

```bash
oc apply -n "$SANDBOX_NS" -f deploy/openshift/canvas-sandbox-mock-alias.yaml
```

type, 실제 대상, port를 관찰한다.

```bash
oc get service customer-rule-mock \
  -n "$SANDBOX_NS" \
  -o custom-columns='NAME:.metadata.name,TYPE:.spec.type,EXTERNAL_NAME:.spec.externalName,PORTS:.spec.ports[*].port'
```

`TYPE=ExternalName`, 대상이
`customer-rule-mock.bamoe-poc.svc.cluster.local`, port가 `8091~8094`여야 한다.

이전에 남은 진단 Pod를 조회한다.

```bash
oc get pod canvas-mock-alias-test -n "$SANDBOX_NS" --ignore-not-found
```

같은 이름의 Pod가 있으면 하나만 삭제한다.

```bash
oc delete pod canvas-mock-alias-test -n "$SANDBOX_NS" --ignore-not-found
```

alias를 통해 Mock health를 읽는 일회성 Pod를 만든다.

```bash
oc run canvas-mock-alias-test \
  -n "$SANDBOX_NS" \
  --image=registry.access.redhat.com/ubi9/ubi:9.6 \
  --restart=Never \
  --command -- \
  curl \
    --fail \
    --silent \
    --show-error \
    http://customer-rule-mock:8093/health
```

성공 종료까지 관찰한다.

```bash
oc wait pod/canvas-mock-alias-test -n "$SANDBOX_NS" --for=jsonpath='{.status.phase}'=Succeeded --timeout=5m
```

health 결과를 검증한다.

```bash
oc logs pod/canvas-mock-alias-test -n "$SANDBOX_NS" | jq -e '.status == "UP"'
```

진단 Pod 하나를 삭제한다.

```bash
oc delete pod canvas-mock-alias-test -n "$SANDBOX_NS"
```

**Gate:** alias의 type/대상/port가 정확하고 sandbox Pod의 health 검증이
`true`다.

### 13.3 Canvas 전용 OpenShift 계정

Canvas에는 `kube:admin`이나 개인 사용자 token을 넣지 않는다. `edit`
ClusterRole도 Secret 접근 등 현재 baseline에 필요 없는 권한이 넓으므로 사용하지
않는다. `canvas-sandbox-rbac.yaml`은 다음 자원만 허용한다.

- Deployment와 Service와 Route: 조회 및 생성·수정·삭제
- ReplicaSet, Pod, Pod log, Event: 상태 조회
- Secret: 권한 없음
- 다른 Project: 권한 없음

manifest를 먼저 읽는다.

```bash
sed -n '1,240p' deploy/openshift/canvas-sandbox-rbac.yaml
```

기존 넓은 RoleBinding이 남아 있는지 role과 subject까지 조회한다.

```bash
oc get rolebinding bamoe-canvas-deployer-edit \
  -n "$SANDBOX_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,ROLE_KIND:.roleRef.kind,ROLE:.roleRef.name,SUBJECT_KIND:.subjects[0].kind,SUBJECT:.subjects[0].name,SUBJECT_NS:.subjects[0].namespace'
```

이전 가이드가 만든 `ClusterRole/edit`가 정확히 같은 sandbox ServiceAccount를
가리키고 namespace도 이 가이드 소유인 경우에만 같은 조건문 안에서 제거한다.
다른 대상을 가리키면 보존하고 소유자를 확인한다.

```bash
legacy_canvas_role_kind="$(
  oc get rolebinding bamoe-canvas-deployer-edit \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
    -o jsonpath='{.roleRef.kind}'
)"
legacy_canvas_role_name="$(
  oc get rolebinding bamoe-canvas-deployer-edit \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
    -o jsonpath='{.roleRef.name}'
)"
legacy_canvas_subject_kind="$(
  oc get rolebinding bamoe-canvas-deployer-edit \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
    -o jsonpath='{.subjects[0].kind}'
)"
legacy_canvas_subject_name="$(
  oc get rolebinding bamoe-canvas-deployer-edit \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
    -o jsonpath='{.subjects[0].name}'
)"
legacy_canvas_subject_namespace="$(
  oc get rolebinding bamoe-canvas-deployer-edit \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
    -o jsonpath='{.subjects[0].namespace}'
)"
canvas_namespace_owner="$(
  oc get namespace "$SANDBOX_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)"

if [ -z "$legacy_canvas_role_name" ]; then
  printf 'LEGACY_CANVAS_EDIT_BINDING=ABSENT\n'
elif [ "$legacy_canvas_role_kind" = 'ClusterRole' ] \
  && [ "$legacy_canvas_role_name" = 'edit' ] \
  && [ "$legacy_canvas_subject_kind" = 'ServiceAccount' ] \
  && [ "$legacy_canvas_subject_name" = 'bamoe-canvas-deployer' ] \
  && [ "$legacy_canvas_subject_namespace" = "$SANDBOX_NS" ] \
  && [ "$canvas_namespace_owner" = 'bamoe-poc-guide' ]
then
  oc delete rolebinding bamoe-canvas-deployer-edit -n "$SANDBOX_NS"
else
  printf 'REFUSE: legacy-named RoleBinding ownership or contract mismatch\n' >&2
fi
```

같은 이름의 새 최소권한 리소스가 이미 있다면 이 가이드 소유인지 검사한다.
RoleBinding은 정확히 `bamoe-sandbox`의 ServiceAccount를 가리켜야 한다.

```bash
canvas_rbac_owned_or_absent() {
  resource_kind="$1"
  resource_name="$(
    oc get "$resource_kind" bamoe-canvas-deployer \
      -n "$SANDBOX_NS" \
      --ignore-not-found \
      -o jsonpath='{.metadata.name}'
  )"
  resource_part_of="$(
    oc get "$resource_kind" bamoe-canvas-deployer \
      -n "$SANDBOX_NS" \
      --ignore-not-found \
      -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}'
  )"

  [ -z "$resource_name" ] \
    || [ "$resource_part_of" = 'bamoe-customer-rule-poc' ]
}

canvas_binding_name="$(
  oc get rolebinding bamoe-canvas-deployer \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.name}'
)"
canvas_binding_contract=true

if [ -n "$canvas_binding_name" ]; then
  if ! oc get rolebinding bamoe-canvas-deployer \
      -n "$SANDBOX_NS" \
      -o json \
    | jq -e \
        --arg namespace "$SANDBOX_NS" \
        '
          .roleRef.kind == "Role"
          and .roleRef.name == "bamoe-canvas-deployer"
          and (.subjects | length) == 1
          and .subjects[0].kind == "ServiceAccount"
          and .subjects[0].name == "bamoe-canvas-deployer"
          and .subjects[0].namespace == $namespace
        ' \
    >/dev/null
  then
    canvas_binding_contract=false
  fi
fi

if [ "$canvas_namespace_owner" = 'bamoe-poc-guide' ] \
  && canvas_rbac_owned_or_absent serviceaccount \
  && canvas_rbac_owned_or_absent role \
  && canvas_rbac_owned_or_absent rolebinding \
  && [ "$canvas_binding_contract" = true ]
then
  export CANVAS_RBAC_OWNERSHIP_OK=true
  printf 'CANVAS_RBAC_OWNERSHIP_GATE=PASS\n'
else
  export CANVAS_RBAC_OWNERSHIP_OK=false
  printf 'CANVAS_RBAC_OWNERSHIP_GATE=FAIL\n' >&2
fi
```

`FAIL`이면 같은 이름의 기존 리소스를 덮어쓰지 않는다.

현재 API server에서 새 최소권한 manifest를 검증한다.

```bash
oc apply \
  --dry-run=server \
  -n "$SANDBOX_NS" \
  -f deploy/openshift/canvas-sandbox-rbac.yaml
```

server dry-run이 정상이고 ownership Gate가 같은 terminal에서 `PASS`일 때만
ServiceAccount, Role, RoleBinding 세 리소스를 적용한다.

```bash
if [ "$CANVAS_RBAC_OWNERSHIP_OK" = true ]; then
  oc apply \
    -n "$SANDBOX_NS" \
    -f deploy/openshift/canvas-sandbox-rbac.yaml
else
  printf 'REFUSE: Canvas RBAC ownership was not validated\n' >&2
fi
```

subject와 Role 연결을 관찰한다.

```bash
oc get serviceaccount,role,rolebinding \
  -n "$SANDBOX_NS" \
  -l app.kubernetes.io/name=bamoe-canvas-deployer \
  -o wide
```

현재 사용자의 impersonation 가능 여부를 조회한다.

```bash
oc auth can-i impersonate serviceaccounts/bamoe-canvas-deployer -n "$SANDBOX_NS"
```

결과가 `no`이면 아래 `--as` 명령을 실행하지 말고 플랫폼 관리자에게 같은 여섯
검사를 요청한다. `yes`일 때만 아래를 하나씩 실행한다.

```bash
export CANVAS_SA="system:serviceaccount:${SANDBOX_NS}:bamoe-canvas-deployer"
```

sandbox Deployment 생성 권한:

```bash
oc auth can-i create deployments.apps -n "$SANDBOX_NS" --as="$CANVAS_SA"
```

sandbox Service 생성 권한:

```bash
oc auth can-i create services -n "$SANDBOX_NS" --as="$CANVAS_SA"
```

sandbox Route 생성 권한:

```bash
oc auth can-i create routes.route.openshift.io -n "$SANDBOX_NS" --as="$CANVAS_SA"
```

본선 Project Deployment 생성 거부:

```bash
oc auth can-i create deployments.apps -n "$APP_NS" --as="$CANVAS_SA"
```

sandbox Secret 조회 거부:

```bash
oc auth can-i get secrets -n "$SANDBOX_NS" --as="$CANVAS_SA"
```

sandbox Pod 직접 생성 거부:

```bash
oc auth can-i create pods -n "$SANDBOX_NS" --as="$CANVAS_SA"
```

기대 순서는 `yes`, `yes`, `yes`, `no`, `no`, `no`다. 세 negative 결과까지
확인하기 전에는 token을 Canvas UI에 넣지 않는다.

token 요청 권한을 확인한다.

```bash
oc auth can-i create serviceaccounts/token -n "$SANDBOX_NS"
```

결과가 `yes`일 때 zsh `pipefail`을 적용해 24시간 token 하나를 clipboard에
복사한다. token 생성과 `pbcopy` 중 하나라도 실패하면 명령 전체가 실패하며
화면에는 token이 출력되지 않는다.

```bash
zsh -o pipefail -c 'oc create token bamoe-canvas-deployer -n "$SANDBOX_NS" --duration=24h | pbcopy'
```

명령이 실패하면 clipboard를 비우고 원인을 해결한 뒤 새 token을 한 번 다시
발급한다.

이 명령을 반복하면 새 bearer token이 추가로 생기며 기존 token은 자체 만료까지
유효할 수 있다. 한 번만 실행하고 다음 UI 단계에서 즉시 사용한다.

**Gate**

- RoleBinding subject가 `bamoe-sandbox:bamoe-canvas-deployer`이고 RoleRef가
  namespace Role `bamoe-canvas-deployer`다.
- 권한 경계가 `yes yes yes no no no`다.
- token pipeline 명령이 성공했다.
- token 값은 terminal, 파일, 문서, 채팅에 출력되지 않았다.

### 13.4 Canvas UI에 OpenShift 연결

Canvas Route를 조회한다.

```bash
oc get route \
  -n "$DEV_NS" \
  -o custom-columns='NAME:.metadata.name,SERVICE:.spec.to.name,HOST:.spec.host,TLS:.spec.tls.termination'
```

Canvas를 가리키는 행의 실제 host를 복사한다.

```bash
export CANVAS_ROUTE_HOST='<실제 Canvas Route host>'
```

URL을 확인한다.

```bash
printf 'CANVAS_URL=https://%s\n' "$CANVAS_ROUTE_HOST"
```

Canvas는 현재 인터넷에서 접근 가능하고 별도 중앙 로그인을 붙이지 않았다. 공용
PC나 공유 browser profile을 사용하지 않는다.

1. `https://<CANVAS_ROUTE_HOST>`를 브라우저로 연다.
2. **Profile/Accounts → Connect to an Account**를 선택한다.
3. Cloud provider로 **OpenShift**를 선택한다.
4. Server/API URL에는 `OCP_API_SERVER`를 입력한다.
5. Namespace/Project에는 `bamoe-sandbox`를 입력한다.
6. Token에는 직전에 clipboard로 복사한 24시간 token을 붙여 넣는다.
7. TLS 검증을 비활성화하지 않는다.
8. 연결 후 대상 Project가 `bamoe-sandbox`인지 다시 확인한다.

붙여 넣기가 끝나면 clipboard를 즉시 비운다.

```bash
printf '' | pbcopy
```

화면 label은 9.5 patch에 따라 조금 다를 수 있지만 API URL, namespace, token의
의미는 같다.

### 13.5 Canvas UI에 GitHub 연결

GHCR read token과 별도의 GitHub fine-grained PAT를 사용한다.

- repository: `jihunkeom/bamoe-customer-rule-poc`
- permission: 해당 repository의 Contents read/write
- 불필요한 organization, package, administration 권한 제외
- 만료일을 PoC 기간에 맞게 설정

Canvas에서:

1. **Connect to an Account → GitHub**를 선택한다.
2. GitHub PAT를 입력한다.
3. private repository를 import한다.
4. `main`이 아니라 `canvas-demo` 같은 별도 branch에서 먼저 수정한다.
5. 검토 후 `main`에 merge하면 본선 GitHub Actions가 자동 재배포한다.

PAT를 terminal, 문서, 채팅에 붙여 넣지 않는다.

### 13.6 Deploy 버튼으로 임시 배포

1. import한 프로젝트를 연다.
2. 저장되지 않은 모델 오류가 없는지 validation한다.
3. **Deploy** 또는 **Dev Deployments**를 선택한다.
4. Cloud provider가 `bamoe-sandbox` 계정인지 확인한다.
5. **OpenShift Spring Boot PoC**를 선택한다.
6. **Container Image**가
   `quay.io/bamoe/canvas-dev-deployment-base:9.5.0-ibm-0005-jdk21`인지 확인한다.
7. **Container Port**가 `8080`인지 확인한다.
8. **Command**가 §13.1에서 검증한 `./mvnw --settings ... spring-boot:run ...`
   명령과 같은지 확인한다.
9. **Confirm**을 눌러 upload와 build를 시작한다.
10. Dev Deployment 카드가 성공 상태가 될 때까지 기다린다.

5번에서 카드가 없거나 descriptor validation 오류가 보이면 Deploy를 진행하지
않는다. `specVersion`을 추측해서 바꾸지 말고 브라우저 오류, Canvas log, 같은
fix pack Accelerator가 생성한 option을 함께 비교한다. 카드가 정상 표시되고 세
parameter가 위 값과 일치하는 것이 실제 Canvas UI 호환성 Gate다.

이 사용자 정의 옵션의 계약:

- Canvas가 Java, DMN, BPMN, `pom.xml`, `config/`를 포함한 작업공간 전체를 올린다.
- 임시 Pod 안에서 Spring Boot를 Maven으로 빌드하고 실행한다.
- BAMOE artifact는 cluster 내부 Maven Repository에서 해석한다.
- 모델 또는 Java compile 오류가 하나라도 있으면 배포가 실패한다.
- 이 옵션에는 DMN Form Webapp sidecar가 없다. DMN과 BPMN은 Swagger UI 또는
  REST endpoint로 검증한다.
- 본선 `bamoe-poc` Deployment는 이 버튼으로 변경되지 않는다.

Canvas 카드에 표시된 이번 배포의 고유 이름을 기록한다.

```bash
export CANVAS_DEMO_NAME='<Canvas 카드에 표시된 이번 배포 이름>'
```

빈 값이 아닌지 먼저 확인한다.

```bash
test -n "$CANVAS_DEMO_NAME"
```

이번 이름에 해당하는 Deployment metadata를 읽는다.

```bash
oc get deployment "$CANVAS_DEMO_NAME" \
  -n "$SANDBOX_NS" \
  -o json \
  | jq '{
      name: .metadata.name,
      createdBy: .metadata.labels["tools.kie.org/created-by"],
      workspaceId: .metadata.annotations["tools.kie.org/workspace-id"],
      workspaceName: .metadata.annotations["tools.kie.org/workspace-name"]
    }'
```

Canvas가 만든 이번 workspace인지 강제 검증한다.

```bash
oc get deployment "$CANVAS_DEMO_NAME" \
  -n "$SANDBOX_NS" \
  -o json \
  | jq -e '
      .metadata.labels["tools.kie.org/created-by"] == "kie-tools"
      and (.metadata.annotations["tools.kie.org/workspace-id"] | length > 0)
      and (.metadata.annotations["tools.kie.org/workspace-name"] | length > 0)
    '
```

검증이 실패하면 다른 사용자의 리소스일 수 있으므로 시연과 삭제를 중단한다.
배포 후 sandbox resource 전체도 관찰한다.

```bash
oc get deployment -n "$SANDBOX_NS" -o wide
```

```bash
oc get pod -n "$SANDBOX_NS" -o wide
```

```bash
oc get service -n "$SANDBOX_NS" -o wide
```

```bash
oc get route -n "$SANDBOX_NS" -o wide
```

이번 Route에서 URL을 만든다.

```bash
export CANVAS_DEMO_URL="https://$(
  oc get route "$CANVAS_DEMO_NAME" \
    -n "$SANDBOX_NS" \
    -o jsonpath='{.spec.host}'
)"
```

Spring Boot health를 확인한다.

```bash
curl \
  --fail \
  --silent \
  --show-error \
  "${CANVAS_DEMO_URL}/actuator/health" \
  | jq -e '.status == "UP"'
```

Canvas의 Dev Deployment 카드를 열거나
`${CANVAS_DEMO_URL}/swagger-ui/index.html`로 이동한다. 이 repository의 Case 04
BPMN을 함께 배포했다면 `POST /Case04FallbackProcess`가 보여야 한다.
**Try it out**에서 다음 합성 payload를 사용한다.

```json
{
  "requestId": "CANVAS-C04-FALLBACK",
  "customerId": "C001",
  "mockScenario": "FALLBACK_GRANTED"
}
```

정상 결과:

- HTTP status가 `201`
- `processResponse.executionState`가 `COMPLETED`
- `processResponse.policyEvaluationCount`가 `2`
- `processResponse.policyResult.status`가 `ALLOW`
- `processResponse.policyResult.reasonCode`가 `FALLBACK_AUTH_GRANTED`

Swagger UI에 endpoint가 없으면 배포한 branch에
`Case04FallbackProcess.bpmn`과 필요한 DMN이 포함됐는지 확인한다. HTTP `500`이면
sandbox의 `customer-rule-mock` alias와 Dev Deployment Pod log를 확인한다.

시연이 끝나면 Canvas UI의 Dev Deployment 목록에서
`CANVAS_DEMO_NAME`과 같은 항목 하나만 **Delete**한다. **Delete all**은 다른
workspace의 시연까지 지울 수 있으므로 사용하지 않는다. 그 뒤 이번 이름의 세
리소스가 사라졌는지 exact name으로 확인한다.

```bash
oc get \
  deployment/"$CANVAS_DEMO_NAME" \
  service/"$CANVAS_DEMO_NAME" \
  route/"$CANVAS_DEMO_NAME" \
  -n "$SANDBOX_NS" \
  --ignore-not-found \
  -o name
```

정상 출력은 비어 있다. `customer-rule-mock` ExternalName Service는 다음
시연에도 쓰므로 이 단계에서는 남겨 둔다.

**Gate**

- Canvas 계정은 sandbox에서만 write 가능하다.
- 사용자 정의 Spring Boot Dev Deployment가 성공했다.
- 생성된 Case 04 BPMN endpoint가 Mock alias와 함께 동작했다.
- 본선 `bamoe-poc` image가 바뀌지 않았다.
- Canvas metadata로 소유권을 확인한 이번 임시 Dev Deployment만 UI에서 삭제했다.

참고:

- [BAMOE Canvas Dev Deployments](https://www.ibm.com/docs/en/ibamoe/9.5.0?topic=canvas-dev-deployments)
- [BAMOE Dev Environment 설치](https://www.ibm.com/docs/en/ibamoe/9.5.0?topic=installing-dev-environment)

## 14. 일상 개발과 자동 배포 흐름

메인 개발 경로는 Canvas Deploy가 아니라 독립 GitHub 작업 사본이다. UI에서도
bootstrap 원본인 `SOURCE_DIR`가 아니라 아래 폴더를 프로젝트로 연다.

```text
/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/bamoe-customer-rule-poc
```

`SOURCE_DIR`는 로컬 Maven Repository와 Maven settings를 재사용하기 위한
bootstrap 원본이다. 그 폴더에서 모델을 수정해도 GitHub 작업 사본에는 자동
반영되지 않는다.

### 14.1 변경 전 현재 위치와 branch 조회

환경값을 읽는다.

```bash
source /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/deploy/openshift/ocp-env.sh
```

GitHub 작업 사본으로 이동한다.

```bash
cd "$GITHUB_WORK_DIR"
```

실제 경로를 조회한다.

```bash
pwd -P
```

기대값은 `GITHUB_WORK_DIR`다.

현재 branch를 조회한다.

```bash
git branch --show-current
```

일상 자동 배포 절차는 `main`에서만 진행하므로 명시적으로 검증한다.

```bash
test "$(git branch --show-current)" = 'main'
```

아무 출력 없이 성공해야 한다. `canvas-demo` 등 다른 branch라면 이 절차의
`pull`, `commit`, `push`를 실행하지 말고 먼저 의도한 변경을 검토해 `main`에
merge하는 흐름을 선택한다.

작업 전 변경 상태를 조회한다.

```bash
git status --short
```

미확인 변경이 있으면 pull 전에 그 소유자와 목적을 확인한다.

현재 작업 사본이 의도한 GitHub repository에 연결됐는지 identity만 검증한다.

```bash
test "$(gh repo view --json nameWithOwner --jq '.nameWithOwner')" = "${GITHUB_OWNER}/${GITHUB_REPO}"
```

출력 없이 성공해야 한다. 실패하면 pull이나 push를 실행하지 않는다.

새 terminal에서도 배포 후 smoke test에 사용할 Route host를 다시 조회한다.

```bash
oc get route customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,HOST:.spec.host,TLS:.spec.tls.termination'
```

조회한 host를 변수로 읽는다.

```bash
export APP_ROUTE_HOST="$(
  oc get route customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.spec.host}'
)"
```

HTTPS base URL을 복구한다.

```bash
export APP_BASE_URL="https://${APP_ROUTE_HOST}"
```

```bash
printf 'APP_BASE_URL=%s\n' "$APP_BASE_URL"
```

Route가 없거나 host가 비어 있으면 자동 배포 smoke test가 실패하므로 §10을 먼저
복구한다.

fast-forward로만 최신 `main`을 받는다.

```bash
git pull --ff-only origin main
```

`--ff-only`가 실패하면 강제로 덮어쓰지 말고 local/remote branch 차이를 먼저
정리한다.

### 14.2 UI 편집 후 로컬 검증

BAMOE Maven Repository container의 현재 상태를 조회한다.

```bash
docker compose -f "$SOURCE_DIR/compose.bamoe-dev.yaml" ps maven-repository
```

필요하면 service 한 개를 시작한다.

```bash
docker compose -f "$SOURCE_DIR/compose.bamoe-dev.yaml" up -d maven-repository
```

repository HTTP 응답을 관찰한다.

```bash
curl --fail --silent --show-error http://127.0.0.1:10099/ >/dev/null
```

UI에서 DMN/BPMN을 수정한 뒤 먼저 파일 이름만 조회한다. 잘못 저장한 token이나
Secret 내용을 terminal에 출력하지 않기 위한 순서다.

```bash
git diff --name-status
```

변경량도 내용 없이 확인한다.

```bash
git diff --stat
```

의도하지 않은 파일, 고객 PDF, token, 로컬 settings가 보이면 content diff를
열거나 commit하지 않는다. 파일 목록이 안전하다고 확인한 뒤 BAMOE UI 또는 IDE의
diff 화면에서 의도한 DMN/BPMN 내용을 검토한다.

SCESIM을 포함한 전체 검증을 한 번 실행한다.

```bash
mvn -s "$SOURCE_DIR/config/settings-bamoe-container.xml" -B -ntp clean verify
```

**Gate:** Maven 결과가 `BUILD SUCCESS`다.

### 14.3 검토한 파일만 commit하고 push

현재 변경 파일을 다시 조회한다.

```bash
git status --short
```

아래는 예시다. 실제로 검토한 정확한 파일 경로 하나를 지정한다.

```bash
git add -- src/main/resources/dmn/Case01ServiceStatusChange.dmn
```

stage된 파일 이름을 다시 관찰한다.

```bash
git diff --cached --name-status
```

stage된 변경량을 확인한다.

```bash
git diff --cached --stat
```

의도한 파일만 있고 UI/IDE에서 실제 내용까지 검토했을 때 commit 한 개를 만든다.

```bash
git commit -m 'Describe the verified rule change'
```

push할 commit을 조회한다.

```bash
git log -1 --oneline
```

`main` push는 자동 배포가 켜져 있으면 실제 OCP Deployment를 변경한다. 이
절의 나머지 Gate는 실제 자동 재배포를 검증하므로 flag가 `true`인 경로만
진행한다. build-only push를 원하면 이 지점에서 멈추고 별도 작업으로 진행한다.
먼저 현재 flag를 조회한다.

```bash
gh variable get OCP_AUTO_DEPLOY \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

값이 정확히 `true`인지 명령으로 검증한다.

```bash
test "$(gh variable get OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}")" = 'true'
```

출력 없이 성공해야 한다. 실패하면 이 절에서는 push하지 않는다.

같은 workflow의 대기 중인 run이 없는지 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --status queued \
  --limit 5
```

실행 중인 run도 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --status in_progress \
  --limit 5
```

두 목록이 모두 비어 있어야 한다. 기존 run이 있으면 완료를 관찰하고 실제
Deployment image를 확인한 뒤 다시 시작한다.

의도한 동작을 확인한 뒤 push를 한 번 실행한다.

```bash
git push origin main
```

push된 SHA를 기록한다.

```bash
export PUSHED_SHA="$(git rev-parse HEAD)"
```

해당 commit의 workflow를 조회한다.

```bash
gh run list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --workflow build-images.yml --commit "$PUSHED_SHA" --limit 5
```

push 직후에는 해당 SHA의 run이 아직 보이지 않을 수 있다. 이 경우 다시 push하지
말고 같은 `gh run list` 명령만 잠시 후 재실행한다.

방금 push에 대응하는 run ID를 직접 복사한다.

```bash
export PUSH_RUN_ID='<PUSHED_SHA와 같은 행의 run ID>'
```

placeholder를 그대로 두거나 다른 열을 복사하지 않았는지 확인한다.

```bash
case "$PUSH_RUN_ID" in
  ''|*[!0-9]*)
    printf 'PUSH_RUN_ID_GATE=FAIL\n' >&2
    false
    ;;
  *)
    printf 'PUSH_RUN_ID_GATE=PASS (%s)\n' "$PUSH_RUN_ID"
    ;;
esac
```

정확한 run 하나를 관찰한다.

```bash
gh run watch "$PUSH_RUN_ID" --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --exit-status
```

run의 실제 SHA와 job 결과를 JSON으로 저장한다.

```bash
export PUSH_RUN_JSON="$(
  gh run view "$PUSH_RUN_ID" \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --json headSha,event,workflowName,status,conclusion,jobs,url
)"
```

사람이 먼저 전체 결과를 읽는다.

```bash
printf '%s\n' "$PUSH_RUN_JSON" | jq .
```

그 다음 같은 JSON을 기계적으로 검증한다. `build`와 이름이 지정된 deploy job이
각각 정확히 하나이고 둘 다 성공해야 한다.

```bash
printf '%s\n' "$PUSH_RUN_JSON" \
  | jq -e \
      --arg pushed_sha "$PUSHED_SHA" \
      '
        .headSha == $pushed_sha
        and .event == "push"
        and .workflowName == "Build and publish PoC images"
        and .status == "completed"
        and .conclusion == "success"
        and (
          [.jobs[]
            | select(
                .name == "build"
                and .conclusion == "success"
              )]
          | length
        ) == 1
        and (
          [.jobs[]
            | select(
                .name == "Deploy immutable images to OpenShift"
                and .conclusion == "success"
              )]
          | length
        ) == 1
      '
```

출력이 `true`가 아니면 아래 OCP 결과를 이번 push의 성공으로 해석하지 않는다.

두 Deployment가 Ready인지 container 이름으로 관찰한다.

```bash
oc rollout status deployment/customer-rule-mock \
  -n "$APP_NS" \
  --timeout=5m
```

```bash
oc rollout status deployment/customer-rule-poc \
  -n "$APP_NS" \
  --timeout=8m
```

실제 image도 배열 순서가 아니라 container 이름으로 읽는다.

```bash
export PUSH_MOCK_IMAGE="$(
  oc get deployment/customer-rule-mock \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="mock")].image}'
)"
```

```bash
export PUSH_APP_IMAGE="$(
  oc get deployment/customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="application")].image}'
)"
```

```bash
printf 'MOCK_IMAGE=%s\nAPP_IMAGE=%s\n' \
  "$PUSH_MOCK_IMAGE" \
  "$PUSH_APP_IMAGE"
```

두 reference가 방금 push한 40자리 SHA와 전체 digest를 포함하는지 exact
검증한다.

```bash
if printf '%s\n' "$PUSH_MOCK_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-mock:sha-${PUSHED_SHA}@sha256:[0-9a-f]{64}" \
  && printf '%s\n' "$PUSH_APP_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-poc:sha-${PUSHED_SHA}@sha256:[0-9a-f]{64}"
then
  printf 'PUSH_IMAGE_GATE=PASS\n'
else
  printf 'PUSH_IMAGE_GATE=FAIL\n' >&2
  false
fi
```

외부 OpenAPI를 확인한다.

```bash
curl --fail --silent --show-error "${APP_BASE_URL}/v3/api-docs" | jq -e '.paths | length > 0'
```

**Gate**

- run `headSha`가 `PUSHED_SHA`와 같다.
- run event와 workflow 이름이 각각 `push`,
  `Build and publish PoC images`다.
- build와 deploy job이 모두 성공했다.
- 두 OCP image의 `sha-<commit>`이 `PUSHED_SHA`와 같다.
- 두 image가 digest로 고정됐고 Deployment가 Ready다.
- 외부 OpenAPI가 성공한다.
- workflow의 Case 04 fallback Process assertion이 성공한다.

### 14.4 Case 05·06을 OCP 범위로 승격하는 Gate

Case 05·06도 최종적으로 같은 Business Service image와 Mock image를 사용하지만,
파일을 rsync 제외 목록에서 지우는 것만으로는 동작하지 않는다. 현재 Case 05
BPMN 초안은 로컬 loopback URL을 포함하고, `run_all.py`와 OCP Service는
8091~8094만 실행·노출한다. 다음 항목을 **모두** 완료한 뒤에만 OCP 범위에
포함한다.

1. BAMOE UI에서 BPMN의 모든 REST Task URL을
   `http://customer-rule-mock:8095/...` 또는 `:8096/...`로 저장한다.
2. Business Rule Task의 DMN Input/Output Name이 모델 계약과 같은지 확인한다.
   현재 Case 05 초안은 Output Name `Response`를 `Result`로 UI에서 교정해야 한다.
3. 각 Python Mock은 `0.0.0.0`에 bind하고, 로컬 안내 출력만
   `127.0.0.1`을 사용한다.
4. `mock-server/run_all.py`의 `MOCKS`에 완성된 Case script를 추가한다.
5. `mock-server/Containerfile`의 `EXPOSE`, Mock Deployment container port,
   `customer-rule-mock` Service port를 함께 추가한다.
6. `canvas-sandbox-mock-alias.yaml`에도 같은 port를 추가한다.
7. source 복사 시 Case별 BPMN/DMN/SCESIM/Mock 제외 규칙을 제거한다.
8. `clean verify`, Mock `/health`, Process OpenAPI, happy/error Process POST와
   exact journal assertion을 로컬에서 통과시킨다.
9. Kustomize render에 새 port가 Deployment·Service·ExternalName alias 세 곳에
   모두 있는지 검사하고 `--dry-run=server`를 통과시킨다.
10. OCP에서 Process POST와 Mock 호출 순서를 다시 검증한 뒤 현재 범위 표를
   Case 01~05 또는 01~06으로 갱신한다.

어느 하나라도 빠지면 기존 Case 01~04 배포만 유지한다. 특히 BPMN에
`localhost`/`127.0.0.1`이 남거나 `run_all.py`에 server가 등록되지 않은 상태는
build가 성공해도 runtime에서 연결 실패한다.

### 14.5 애플리케이션 manifest를 안전하게 변경하는 원칙

`Deployment`, `Service`, `ConfigMap`, port를 바꾸는 commit은 Actions가 자동으로
적용하지 않는다. 원본 PAMOE overlay에는 직접 적용 방지 placeholder가 있으므로
다음 순서를 사용한다.

1. `OCP_AUTO_DEPLOY=false`로 자동 image 변경을 잠시 멈춘다.
2. manifest와 코드 변경을 review하고 `clean verify` 및 Actions build를 통과시킨다.
3. 코드도 바뀌었다면 §7.4처럼 새 SHA tag를 worker가 pull하게 한 뒤 실제
   `imageID` digest를 추출한다. manifest만 바뀌었다면 현재 두 Deployment의
   container 이름별 전체 `tag@digest` reference를 조회한다.
4. 원본 overlay가 아니라 §8.2의 새 임시 작업 사본에 두 불변 reference를
   `kustomize edit set image`로 주입한다.
5. render에 `latest`와 `DO_NOT_APPLY_SET_IMMUTABLE_REF`가 없고 앱·Mock image가
   각각 한 번만 있는지 확인한다.
6. server dry-run, 실제 apply, 두 rollout, OpenAPI와 Case 04 E2E를 차례로
   통과시킨다.
7. 성공한 manifest와 image commit 관계를 기록한 뒤 자동 배포를 다시 켠다.

현재 image를 조회할 때 배열의 첫 container라고 가정하지 않고 이름으로 선택한다.

```bash
export CURRENT_APP_IMAGE="$(
  oc get deployment/customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="application")].image}'
)"
```

```bash
export CURRENT_MOCK_IMAGE="$(
  oc get deployment/customer-rule-mock \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="mock")].image}'
)"
```

두 값이 owner, 40자리 SHA tag, digest를 모두 포함하고 **같은 commit**인지
확인한다.

```bash
CURRENT_APP_SHA="$(
  printf '%s\n' "$CURRENT_APP_IMAGE" \
  | sed -E 's#^.*:sha-([0-9a-f]{40})@sha256:[0-9a-f]{64}$#\1#'
)"
CURRENT_MOCK_SHA="$(
  printf '%s\n' "$CURRENT_MOCK_IMAGE" \
  | sed -E 's#^.*:sha-([0-9a-f]{40})@sha256:[0-9a-f]{64}$#\1#'
)"

if printf '%s\n' "$CURRENT_APP_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-poc:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}" \
  && printf '%s\n' "$CURRENT_MOCK_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-mock:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}" \
  && [ "$CURRENT_APP_SHA" = "$CURRENT_MOCK_SHA" ]
then
  printf 'LIVE_IMAGE_PRESERVATION_GATE=PASS\n'
else
  printf 'LIVE_IMAGE_PRESERVATION_GATE=FAIL\n' >&2
fi
```

`PASS`가 아니면 두 image가 서로 다른 시점일 수 있으므로 원본 overlay를
apply하지 않는다. 이후 §8.2에서
`APP_IMAGE=$CURRENT_APP_IMAGE`, `MOCK_IMAGE=$CURRENT_MOCK_IMAGE`로 사용한다.

### 14.6 자동 배포를 즉시 멈추는 방법

현재 flag를 조회한다.

```bash
gh variable get OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

장애 조사나 장기 작업 전에는 flag 한 개를 끈다.

```bash
gh variable set OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --body false
```

저장 결과를 관찰한다.

```bash
gh variable get OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

`false`는 이후 deploy job을 skip시킨다. build와 GHCR image 생성은 계속될 수
있다.

## 15. 고객에게 보여 줄 수 있는 기능 범위

현재 PoC에서 실제로 보여 줄 수 있는 것:

- Canvas에서 DMN/BPMN 시각적 편집과 validation
- GitHub를 통한 변경 이력과 협업
- SCESIM 자동 회귀 테스트
- BPMN이 외부 Mock API를 호출하고 DMN이 다음 행동을 결정하는 구조
- Case 04의 조건부 fallback 호출 순서
- commit 식별 SHA tag와 실제 content digest를 함께 기록한 불변 배포 reference
- OCP rolling deployment와 실패 시 image rollback
- Management Console에 Business Service 연결 항목 사전 구성
  (실제 process 관리 기능은 후속 범위)
- MCP Server Tech Preview가 Spring Boot OpenAPI를 읽는 연결
- Canvas Deploy 버튼을 통한 임시 개발 배포

현재 앱만으로 과장하면 안 되는 것:

- 재시작 후에도 유지되는 장기 실행 process instance
- User Task inbox와 사용자/그룹 권한
- timer/job 복구
- Data Index 기반 전체 process 조회
- DB 기반 감사 이력
- multi-replica process consistency

이 기능을 시연하려면 persistence, database, Jobs Service/Data Index 또는 9.5
권장 add-on, 인증/인가, eventing을 포함하는 별도 Business Service가 필요하다.
플랫폼 UI를 설치한 것만으로 현재 straight-through 프로세스가 장기 실행
프로세스가 되지는 않는다.

## 16. 장애 진단과 안전한 rollback

rollback은 상태를 변경하는 작업이다. 먼저 자동 배포를 끄고, 정확한 대상과
revision을 조회한 뒤 resource 하나씩 실행한다. revision 번호가 같다는 이유만으로
앱과 Mock이 같은 commit이라고 가정하지 않는다.

### 16.1 자동 배포 중지와 기본 진단

새 terminal에서 시작했다면 환경 파일이 있는 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

namespace와 GitHub repository 변수를 다시 읽는다.

```bash
source deploy/openshift/ocp-env.sh
```

필수 값, `oc` client version, 로그인 API server를 검증한다.

```bash
bamoe_check_env
```

변경 대상 API server를 사람이 한 번 더 읽는다.

```bash
oc whoami --show-server
```

rollback 대상 앱 Project와 ownership label을 확인한다.

```bash
oc get namespace "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

`NAME=bamoe-poc`, `STATUS=Active`, `OWNER=bamoe-poc-guide`가 아니면 중단한다.

GitHub 작업 사본으로 이동한다.

```bash
cd "$GITHUB_WORK_DIR"
```

현재 작업 사본이 의도한 GitHub repository인지 identity만 검증한다.

```bash
test "$(gh repo view --json nameWithOwner --jq '.nameWithOwner')" = "${GITHUB_OWNER}/${GITHUB_REPO}"
```

출력 없이 성공해야 한다. 실패하면 자동 배포 flag와 OCP image를 변경하지 않는다.

rollback 뒤 smoke test에 사용할 현재 Route host를 읽는다.

```bash
export APP_ROUTE_HOST="$(
  oc get route customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.spec.host}'
)"
```

```bash
export EXPECTED_APP_BASE_URL="https://customer-rule-poc.${OCP_ROUTE_DOMAIN}"

if [ -n "$APP_ROUTE_HOST" ]; then
  export APP_BASE_URL="https://${APP_ROUTE_HOST}"
else
  unset APP_BASE_URL
fi
```

`EXPECTED_APP_BASE_URL`은 현재 cluster domain으로 manifest 의미를 검증하는
계약값이고, `APP_BASE_URL`은 실제 live Route가 있을 때만 존재하는 관찰값이다.
host가 비어 있으면 rollback 자체는 진행할 수 있지만 마지막 외부 smoke test는
수행할 수 없다. 먼저 Route 상태와 장애 범위를 기록한다. 두 값을 서로 대신
사용하지 않는다.

자동 배포를 끈다.

```bash
gh variable set OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --body false
```

저장 결과를 확인한다.

```bash
gh variable get OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

`false`는 앞으로 시작될 deploy job만 막는다. 이미 대기 중인 run을 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --status queued \
  --limit 10
```

이미 실행 중인 run도 별도로 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --status in_progress \
  --limit 10
```

두 목록이 모두 비어 있어야 rollback을 시작한다. run이 있으면 취소를 추측해
실행하지 말고 정확한 run ID를 `gh run watch`로 끝까지 관찰한 뒤 실제 Deployment
image를 다시 조회한다.

Pod 상태를 조회한다.

```bash
oc get pod -n "$APP_NS" -o wide
```

최근 event를 조회한다.

```bash
oc get events -n "$APP_NS" --sort-by=.lastTimestamp
```

앱 Deployment 상태를 조회한다.

```bash
oc describe deployment customer-rule-poc -n "$APP_NS"
```

Mock Deployment 상태를 조회한다.

```bash
oc describe deployment customer-rule-mock -n "$APP_NS"
```

앱 log를 조회한다.

```bash
oc logs deployment/customer-rule-poc -n "$APP_NS" --tail=200
```

Mock log를 조회한다.

```bash
oc logs deployment/customer-rule-mock -n "$APP_NS" --tail=200
```

| 증상 | 먼저 볼 것 |
|---|---|
| `ImagePullBackOff` | GHCR token `read:packages`, `ghcr-pull`, image tag/digest |
| Quay pull 실패 | worker DNS/egress/registry allowlist |
| 앱 readiness 실패 | management port `8081`, actuator log |
| Process HTTP 500 | 앱 log, REST task mapping, Mock journal |
| Route 503 | Pod readiness, Service endpoint |
| Canvas Deploy 실패 | sandbox 권한, 모델 validation, Quay pull |
| MCP가 tool을 못 찾음 | 내부 OpenAPI URL과 MCP log |

### 16.2 Dev/Runtime 제품의 두 가지 rollback

직접 배포에는 Helm release history나 `--atomic`이 없다. 따라서 장애 범위에 따라
rollback 방법을 구분한다.

| 장애 범위 | 우선 복구 방법 | 이후 해야 할 일 |
|---|---|---|
| Deployment의 image/env/probe 한 개 | 해당 Deployment의 `oc rollout undo` | Git manifest를 같은 상태로 맞춤 |
| Service, Route, 여러 Deployment, 보안 설정 | 이전 Git manifest 재적용 + 추가 리소스 exact-name 정리 | 모든 rollout과 wiring 재검증 |

`oc rollout undo`는 Deployment revision만 되돌린다. Service나 Route는 되돌리지
않으며 Git 파일도 바꾸지 않는다. 긴급 복구 뒤 Git을 맞추지 않으면 다음
`oc apply`가 장애 상태를 다시 적용할 수 있다.

#### 16.2.1 Deployment 하나만 긴급 rollback

먼저 정확한 namespace와 Deployment를 선택한다. 아래 예시는 Canvas다. 다른
구성요소라면 두 값 모두 실제 대상으로 바꾼다.

```bash
export PRODUCT_NS="$DEV_NS"
```

```bash
export PRODUCT_DEPLOYMENT='bamoe-canvas'
```

대상이 존재하는지 확인한다.

```bash
oc get deployment "$PRODUCT_DEPLOYMENT" -n "$PRODUCT_NS"
```

revision history를 읽는다.

```bash
oc rollout history \
  deployment/"$PRODUCT_DEPLOYMENT" \
  -n "$PRODUCT_NS"
```

되돌릴 revision의 상세를 직접 확인한다.

```bash
export PRODUCT_REVISION_TO_INSPECT='<확인할 revision 숫자>'
```

```bash
oc rollout history \
  deployment/"$PRODUCT_DEPLOYMENT" \
  -n "$PRODUCT_NS" \
  --revision="$PRODUCT_REVISION_TO_INSPECT"
```

image와 변경 원인이 기대한 정상 상태일 때만 revision을 기록한다.

```bash
export PRODUCT_ROLLBACK_REVISION='<검증한 revision 숫자>'
```

정확한 Deployment 하나를 되돌린다.

```bash
oc rollout undo \
  deployment/"$PRODUCT_DEPLOYMENT" \
  -n "$PRODUCT_NS" \
  --to-revision="$PRODUCT_ROLLBACK_REVISION"
```

새 rollout을 관찰한다.

```bash
oc rollout status \
  deployment/"$PRODUCT_DEPLOYMENT" \
  -n "$PRODUCT_NS" \
  --timeout=8m
```

복구된 image와 Ready를 확인한다.

```bash
oc get deployment "$PRODUCT_DEPLOYMENT" \
  -n "$PRODUCT_NS" \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas'
```

복구 뒤에는 해당 제품 YAML의 image, env, probe를 실제 정상 상태와 맞추고 review한
commit을 만든다. 긴급 `rollout undo`만 수행한 상태를 장기 정상 상태로 간주하지
않는다.

#### 16.2.2 제품 묶음을 검증된 Git commit으로 복구

현재 독립 repository인지 확인한다.

```bash
test "$(gh repo view --json nameWithOwner --jq '.nameWithOwner')" = "${GITHUB_OWNER}/${GITHUB_REPO}"
```

제품 manifest 변경 이력을 읽는다.

```bash
git log \
  --oneline \
  --decorate \
  -- deploy/openshift/products
```

되돌릴 commit의 전체 SHA를 기록한다.

```bash
export PRODUCT_ROLLBACK_COMMIT='<검증한 전체 Git commit SHA>'
```

실제 commit인지 검증한다.

```bash
git cat-file -e "${PRODUCT_ROLLBACK_COMMIT}^{commit}"
```

그 commit의 제품 변경 내역을 읽는다.

```bash
git show \
  --stat \
  --oneline \
  "$PRODUCT_ROLLBACK_COMMIT" \
  -- deploy/openshift/products
```

현재 작업 파일을 덮어쓰지 않도록 임시 디렉터리를 만든다.

```bash
export PRODUCT_ROLLBACK_DIR="$(mktemp -d /tmp/bamoe-product-rollback.XXXXXX)"
```

선택한 commit의 제품 디렉터리만 임시 위치에 푼다.

```bash
git archive \
  "$PRODUCT_ROLLBACK_COMMIT" \
  deploy/openshift/products \
  | tar -x -C "$PRODUCT_ROLLBACK_DIR"
```

Dev 복구 manifest 파일을 만든다.

```bash
export DEV_ROLLBACK_RENDERED="$(mktemp /tmp/bamoe-dev-rollback.XXXXXX)"
```

선택한 commit의 Dev manifest를 조립한다.

```bash
kustomize build \
  "$PRODUCT_ROLLBACK_DIR/deploy/openshift/products/dev" \
  > "$DEV_ROLLBACK_RENDERED"
```

Runtime 복구 manifest 파일도 만든다.

```bash
export RUNTIME_ROLLBACK_RENDERED="$(mktemp /tmp/bamoe-runtime-rollback.XXXXXX)"
```

선택한 commit의 Runtime manifest를 조립한다.

```bash
kustomize build \
  "$PRODUCT_ROLLBACK_DIR/deploy/openshift/products/runtime" \
  > "$RUNTIME_ROLLBACK_RENDERED"
```

두 render가 비어 있지 않은지 확인한다.

```bash
wc -l "$DEV_ROLLBACK_RENDERED" "$RUNTIME_ROLLBACK_RENDERED"
```

API server는 문자열이 오래된 다른 cluster host여도 YAML 형식만 맞으면 허용한다.
따라서 server dry-run 전에 현재 Route domain, Business Service URL, 내부 MCP URL,
앱 CORS와 과거 render의 의미 계약을 비교한다.

```bash
export EXPECTED_CANVAS_URL="https://bamoe-canvas.${OCP_ROUTE_DOMAIN}"
export EXPECTED_CANVAS_EXTENDED_URL="https://bamoe-extended-services.${OCP_ROUTE_DOMAIN}"
export EXPECTED_CANVAS_CORS_PROXY_URL="https://bamoe-cors-proxy.${OCP_ROUTE_DOMAIN}"
export EXPECTED_MC_URL="https://bamoe-management-console.${OCP_ROUTE_DOMAIN}"
export EXPECTED_INTERNAL_OPENAPI_URL="http://customer-rule-poc.${APP_NS}.svc.cluster.local:8080/v3/api-docs"
export EXPECTED_CANVAS_BASE_IMAGE='quay.io/bamoe/canvas-dev-deployment-base:9.5.0-ibm-0005-jdk21'
export OCP_API_HOST="${OCP_API_SERVER#https://}"
export OCP_API_HOST="${OCP_API_HOST%%:*}"
export EXPECTED_CORS_ALLOWED_HOSTS="github.com,*.github.com,*.githubusercontent.com,${OCP_API_HOST},*.${OCP_ROUTE_DOMAIN}"
export ROLLBACK_LIVE_APP_CORS="$(
  oc get configmap customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.data.BAMOE_CORS_ALLOWED_ORIGIN_PATTERNS}'
)"
```

두 render를 Kubernetes object JSON으로 변환해 정확한 image 집합과 환경변수를
꺼낸다. 단순 문자열 검색과 달리 주석이나 다른 필드가 우연히 일치해도 통과하지
않는다.

```bash
export ROLLBACK_PRODUCTS_JSON="$(
  oc create \
    --dry-run=client \
    -f "$DEV_ROLLBACK_RENDERED" \
    -f "$RUNTIME_ROLLBACK_RENDERED" \
    -o json \
  | jq -s '
      {
        items: [
          .[]
          | if .kind == "List" then .items[] else . end
        ]
      }
    '
)"
export EXPECTED_PRODUCT_IMAGES="$(
  jq -nc '
    [
      {
        deployment: "bamoe-canvas",
        container: "canvas",
        image: "quay.io/bamoe/canvas:9.5.0-ibm-0005"
      },
      {
        deployment: "bamoe-cors-proxy",
        container: "cors-proxy",
        image: "quay.io/bamoe/cors-proxy:9.5.0-ibm-0005"
      },
      {
        deployment: "bamoe-extended-services",
        container: "extended-services",
        image: "quay.io/bamoe/extended-services:9.5.0-ibm-0005"
      },
      {
        deployment: "bamoe-management-console",
        container: "management-console",
        image: "quay.io/bamoe/management-console:9.5.0-ibm-0005"
      },
      {
        deployment: "bamoe-maven-repository",
        container: "maven-repository",
        image: "quay.io/bamoe/maven-repository:9.5.0-ibm-0005"
      },
      {
        deployment: "bamoe-mcp-server",
        container: "mcp-server",
        image: "quay.io/bamoe/mcp-server:9.5.0-ibm-0005"
      }
    ]
    | sort_by(.deployment, .container)
  '
)"
export ROLLBACK_PRODUCT_IMAGES="$(
  jq -c '
    [
      .items[]
      | select(.kind == "Deployment")
      | .metadata.name as $deployment
      | .spec.template.spec.containers[]
      | {
          deployment: $deployment,
          container: .name,
          image: .image
        }
    ]
    | sort_by(.deployment, .container)
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
```

Canvas·CORS Proxy의 연결값도 정확한 Deployment/container/env 위치에서 읽는다.

```bash
export ROLLBACK_CANVAS_EXTENDED_URL="$(
  jq -r '
    .items[]
    | select(
        .kind == "Deployment"
        and .metadata.name == "bamoe-canvas"
      )
    | .spec.template.spec.containers[]
    | select(.name == "canvas")
    | .env[]
    | select(.name == "KIE_SANDBOX_EXTENDED_SERVICES_URL")
    | .value
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
export ROLLBACK_CANVAS_CORS_PROXY_URL="$(
  jq -r '
    .items[]
    | select(
        .kind == "Deployment"
        and .metadata.name == "bamoe-canvas"
      )
    | .spec.template.spec.containers[]
    | select(.name == "canvas")
    | .env[]
    | select(.name == "KIE_SANDBOX_CORS_PROXY_URL")
    | .value
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
export ROLLBACK_CANVAS_BASE_IMAGE="$(
  jq -r '
    .items[]
    | select(
        .kind == "Deployment"
        and .metadata.name == "bamoe-canvas"
      )
    | .spec.template.spec.containers[]
    | select(.name == "canvas")
    | .env[]
    | select(.name == "KIE_SANDBOX_DEV_DEPLOYMENT_BASE_IMAGE_URL")
    | .value
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
export ROLLBACK_CORS_ALLOWED_ORIGINS="$(
  jq -r '
    .items[]
    | select(
        .kind == "Deployment"
        and .metadata.name == "bamoe-cors-proxy"
      )
    | .spec.template.spec.containers[]
    | select(.name == "cors-proxy")
    | .env[]
    | select(.name == "CORS_PROXY_ALLOWED_ORIGINS")
    | .value
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
export ROLLBACK_CORS_ALLOWED_HOSTS="$(
  jq -r '
    .items[]
    | select(
        .kind == "Deployment"
        and .metadata.name == "bamoe-cors-proxy"
      )
    | .spec.template.spec.containers[]
    | select(.name == "cors-proxy")
    | .env[]
    | select(.name == "CORS_PROXY_ALLOWED_HOSTS")
    | .value
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
```

Management Console, MCP Server, 네 Route 계약도 object의 정확한 위치에서
추출한다.

```bash
export EXPECTED_MC_SERVICES="$(
  jq -ncS \
    --arg url "$EXPECTED_APP_BASE_URL" \
    '[{
      name: "SKT Customer Rule PoC",
      businessServiceUrl: $url
    }]'
)"
export ROLLBACK_MC_SERVICES="$(
  jq -cS '
    .items[]
    | select(
        .kind == "Deployment"
        and .metadata.name == "bamoe-management-console"
      )
    | .spec.template.spec.containers[]
    | select(.name == "management-console")
    | .env[]
    | select(
        .name
          == "RUNTIME_TOOLS_MANAGEMENT_CONSOLE_MANAGED_BUSINESS_SERVICES"
      )
    | .value
    | fromjson
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
export ROLLBACK_MCP_OPENAPI_URL="$(
  jq -r '
    .items[]
    | select(
        .kind == "Deployment"
        and .metadata.name == "bamoe-mcp-server"
      )
    | .spec.template.spec.containers[]
    | select(.name == "mcp-server")
    | .env[]
    | select(.name == "MCP_SERVER_OPENAPI_URLS")
    | .value
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
export ROLLBACK_MCP_SECURITY_ENABLED="$(
  jq -r '
    .items[]
    | select(
        .kind == "Deployment"
        and .metadata.name == "bamoe-mcp-server"
      )
    | .spec.template.spec.containers[]
    | select(.name == "mcp-server")
    | .env[]
    | select(.name == "MCP_SERVER_SECURITY_ENABLED")
    | .value
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
export ROLLBACK_MCP_AUTH_PERMISSION="$(
  jq -r '
    .items[]
    | select(
        .kind == "Deployment"
        and .metadata.name == "bamoe-mcp-server"
      )
    | .spec.template.spec.containers[]
    | select(.name == "mcp-server")
    | .env[]
    | select(.name == "MCP_SERVER_SECURITY_AUTH_PERMISSION")
    | .value
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
export EXPECTED_PRODUCT_ROUTES="$(
  jq -ncS \
    --arg domain "$OCP_ROUTE_DOMAIN" \
    '[
      {
        name: "bamoe-canvas",
        host: ("bamoe-canvas." + $domain),
        service: "bamoe-canvas",
        targetPort: "http",
        termination: "edge",
        insecurePolicy: "Redirect"
      },
      {
        name: "bamoe-cors-proxy",
        host: ("bamoe-cors-proxy." + $domain),
        service: "bamoe-cors-proxy",
        targetPort: "http",
        termination: "edge",
        insecurePolicy: "Redirect"
      },
      {
        name: "bamoe-extended-services",
        host: ("bamoe-extended-services." + $domain),
        service: "bamoe-extended-services",
        targetPort: "http",
        termination: "edge",
        insecurePolicy: "Redirect"
      },
      {
        name: "bamoe-management-console",
        host: ("bamoe-management-console." + $domain),
        service: "bamoe-management-console",
        targetPort: "http",
        termination: "edge",
        insecurePolicy: "Redirect"
      }
    ]
    | sort_by(.name)'
)"
export ROLLBACK_PRODUCT_ROUTES="$(
  jq -cS '
    [
      .items[]
      | select(.kind == "Route")
      | {
          name: .metadata.name,
          host: .spec.host,
          service: .spec.to.name,
          targetPort: .spec.port.targetPort,
          termination: .spec.tls.termination,
          insecurePolicy: .spec.tls.insecureEdgeTerminationPolicy
        }
    ]
    | sort_by(.name)
  ' <<<"$ROLLBACK_PRODUCTS_JSON"
)"
```

과거 render에 현재 domain과 다른 `apps.*` host가 있는지도 수집한다.

```bash
UNEXPECTED_ROLLBACK_HOSTS="$(
  rg -n 'apps\\.' \
    "$DEV_ROLLBACK_RENDERED" \
    "$RUNTIME_ROLLBACK_RENDERED" \
  | rg -v -F "$OCP_ROUTE_DOMAIN" \
  || true
)"
```

필수 URL, 현재 CORS, 예상 밖 host를 한 Gate에서 검사한다.

```bash
if [ -n "$EXPECTED_APP_BASE_URL" ] \
  && [ -z "$UNEXPECTED_ROLLBACK_HOSTS" ] \
  && [ "$ROLLBACK_PRODUCT_IMAGES" = "$EXPECTED_PRODUCT_IMAGES" ] \
  && [ "$ROLLBACK_CANVAS_EXTENDED_URL" = \
    "$EXPECTED_CANVAS_EXTENDED_URL" ] \
  && [ "$ROLLBACK_CANVAS_CORS_PROXY_URL" = \
    "$EXPECTED_CANVAS_CORS_PROXY_URL" ] \
  && [ "$ROLLBACK_CANVAS_BASE_IMAGE" = "$EXPECTED_CANVAS_BASE_IMAGE" ] \
  && [ "$ROLLBACK_CORS_ALLOWED_ORIGINS" = "$EXPECTED_CANVAS_URL" ] \
  && [ "$ROLLBACK_CORS_ALLOWED_HOSTS" = \
    "$EXPECTED_CORS_ALLOWED_HOSTS" ] \
  && [ "$ROLLBACK_MC_SERVICES" = "$EXPECTED_MC_SERVICES" ] \
  && [ "$ROLLBACK_MCP_OPENAPI_URL" = \
    "$EXPECTED_INTERNAL_OPENAPI_URL" ] \
  && [ "$ROLLBACK_MCP_SECURITY_ENABLED" = 'false' ] \
  && [ "$ROLLBACK_MCP_AUTH_PERMISSION" = 'permit' ] \
  && [ "$ROLLBACK_PRODUCT_ROUTES" = "$EXPECTED_PRODUCT_ROUTES" ] \
  && [ "$ROLLBACK_LIVE_APP_CORS" = "$EXPECTED_MC_URL" ]
then
  export PRODUCT_ROLLBACK_SEMANTIC_OK=true
  printf 'PRODUCT_ROLLBACK_SEMANTIC_GATE=PASS\n'
else
  export PRODUCT_ROLLBACK_SEMANTIC_OK=false
  printf 'PRODUCT_ROLLBACK_SEMANTIC_GATE=FAIL\n' >&2
  printf '%s\n' "$UNEXPECTED_ROLLBACK_HOSTS"
fi
```

`FAIL`이면 과거 commit을 그대로 적용하지 않는다. 현재 cluster용 host와 연결값을
review한 새 복구 commit으로 forward-fix하거나, 장애가 난 단일 Deployment만
16.2.1로 되돌린다.

`oc apply`는 이전 manifest에 없는 새 리소스를 자동 삭제하지 않는다. 그래서
적용 전에 현재 inventory와 이전 commit의 inventory를 비교한다. `--prune`은
사용하지 않고 삭제 후보를 사람이 exact name으로 확인한다.

현재 Dev 제품 inventory를 저장한다.

```bash
export CURRENT_DEV_INVENTORY="$(mktemp /tmp/bamoe-current-dev-inventory.XXXXXX)"
```

```bash
oc get deployment,service,route,configmap,serviceaccount,secret,persistentvolumeclaim,networkpolicy,role,rolebinding \
  -n "$DEV_NS" \
  -l app.kubernetes.io/part-of=bamoe-dev-environment \
  -o name \
  | sort \
  > "$CURRENT_DEV_INVENTORY"
```

이전 commit이 기대하는 Dev inventory도 저장한다.

```bash
export EXPECTED_DEV_INVENTORY="$(mktemp /tmp/bamoe-expected-dev-inventory.XXXXXX)"
```

```bash
oc create \
  --dry-run=client \
  -f "$DEV_ROLLBACK_RENDERED" \
  -o name \
  | sort \
  > "$EXPECTED_DEV_INVENTORY"
```

현재에는 있지만 이전 commit에는 없는 Dev 리소스를 확인한다.

```bash
comm -23 "$CURRENT_DEV_INVENTORY" "$EXPECTED_DEV_INVENTORY"
```

출력된 각 행은 자동 삭제 대상이 아니라 **검토 대상**이다. bad change가 새로 만든
제품 리소스임을 확인한 항목만 뒤의 exact-name 삭제 절차에 사용한다.

Runtime 현재 inventory를 저장한다.

```bash
export CURRENT_RUNTIME_INVENTORY="$(mktemp /tmp/bamoe-current-runtime-inventory.XXXXXX)"
```

```bash
oc get deployment,service,route,configmap,serviceaccount,secret,persistentvolumeclaim,networkpolicy,role,rolebinding \
  -n "$RUNTIME_NS" \
  -l app.kubernetes.io/part-of=bamoe-runtime-environment \
  -o name \
  | sort \
  > "$CURRENT_RUNTIME_INVENTORY"
```

이전 commit의 Runtime inventory를 저장한다.

```bash
export EXPECTED_RUNTIME_INVENTORY="$(mktemp /tmp/bamoe-expected-runtime-inventory.XXXXXX)"
```

```bash
oc create \
  --dry-run=client \
  -f "$RUNTIME_ROLLBACK_RENDERED" \
  -o name \
  | sort \
  > "$EXPECTED_RUNTIME_INVENTORY"
```

현재에만 있는 Runtime 리소스를 확인한다.

```bash
comm -23 "$CURRENT_RUNTIME_INVENTORY" "$EXPECTED_RUNTIME_INVENTORY"
```

Dev 복구안을 저장 없이 검증한다.

```bash
oc apply \
  --dry-run=server \
  -n "$DEV_NS" \
  -f "$DEV_ROLLBACK_RENDERED"
```

Runtime 복구안도 저장 없이 검증한다.

```bash
oc apply \
  --dry-run=server \
  -n "$RUNTIME_NS" \
  -f "$RUNTIME_ROLLBACK_RENDERED"
```

Dev 차이를 읽는다.

```bash
oc diff -n "$DEV_NS" -f "$DEV_ROLLBACK_RENDERED"
```

Runtime 차이를 읽는다.

```bash
oc diff -n "$RUNTIME_NS" -f "$RUNTIME_ROLLBACK_RENDERED"
```

두 diff에서 복구 대상 외의 삭제나 namespace 변경이 없고 semantic Gate가 같은
terminal에서 `PASS`일 때만 적용한다. 먼저 Dev 묶음을 적용한다.

```bash
if [ "$PRODUCT_ROLLBACK_SEMANTIC_OK" = true ]; then
  oc apply -n "$DEV_NS" -f "$DEV_ROLLBACK_RENDERED"
else
  printf 'REFUSE: product rollback semantic contract was not validated\n' >&2
fi
```

Dev 네 Deployment를 하나씩 확인한다.

```bash
oc rollout status deployment/bamoe-extended-services -n "$DEV_NS" --timeout=8m
```

```bash
oc rollout status deployment/bamoe-cors-proxy -n "$DEV_NS" --timeout=5m
```

```bash
oc rollout status deployment/bamoe-maven-repository -n "$DEV_NS" --timeout=5m
```

```bash
oc rollout status deployment/bamoe-canvas -n "$DEV_NS" --timeout=5m
```

Dev가 정상이고 같은 semantic Gate가 `PASS`일 때 Runtime 묶음을 적용한다.

```bash
if [ "$PRODUCT_ROLLBACK_SEMANTIC_OK" = true ]; then
  oc apply -n "$RUNTIME_NS" -f "$RUNTIME_ROLLBACK_RENDERED"
else
  printf 'REFUSE: product rollback semantic contract was not validated\n' >&2
fi
```

Runtime 두 Deployment를 확인한다.

```bash
oc rollout status deployment/bamoe-management-console -n "$RUNTIME_NS" --timeout=5m
```

```bash
oc rollout status deployment/bamoe-mcp-server -n "$RUNTIME_NS" --timeout=8m
```

`comm -23`에서 검증된 추가 Dev 리소스가 있었다면 정확한 `kind/name` 한 개를
기록한다. 출력이 없었다면 이 삭제 절차는 건너뛴다.

```bash
export EXTRA_DEV_RESOURCE='<검증한 Dev kind/name 한 개>'
```

삭제 전에 namespace와 ownership label만 다시 확인한다. inventory에는 `Secret`도
포함될 수 있으므로 generic `-o yaml`/`-o json`을 사용해 본문을 출력하지 않는다.

```bash
oc get "$EXTRA_DEV_RESOURCE" \
  -n "$DEV_NS" \
  -o custom-columns='KIND:.kind,NAME:.metadata.name,NAMESPACE:.metadata.namespace,PART_OF:.metadata.labels.app\.kubernetes\.io/part-of'
```

현재-only inventory 포함 여부와 제품 ownership label을 같은 변경 블록 안에서
검증한 뒤에만 삭제한다. 어느 조건이든 실패하면 삭제하지 않고 `REFUSE`를
출력한다.

```bash
if
  test -n "$EXTRA_DEV_RESOURCE" \
  && comm -23 "$CURRENT_DEV_INVENTORY" "$EXPECTED_DEV_INVENTORY" \
    | rg --fixed-strings --line-regexp -- "$EXTRA_DEV_RESOURCE" >/dev/null \
  && test "$(
    oc get "$EXTRA_DEV_RESOURCE" \
      -n "$DEV_NS" \
      -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}'
  )" = 'bamoe-dev-environment'
then
  oc delete "$EXTRA_DEV_RESOURCE" -n "$DEV_NS"
else
  printf 'REFUSE: resource is not a verified Dev rollback extra\n' >&2
fi
```

검증된 Dev 추가 리소스가 더 있으면 변수 설정, 조회, label Gate, 삭제를 하나씩
반복한다.

Runtime 추가 리소스도 있을 때에만 정확한 한 항목을 기록한다.

```bash
export EXTRA_RUNTIME_RESOURCE='<검증한 Runtime kind/name 한 개>'
```

삭제 전 namespace와 ownership label만 확인한다. `Secret`일 가능성이 있으므로
본문이 포함되는 YAML/JSON 출력은 금지한다.

```bash
oc get "$EXTRA_RUNTIME_RESOURCE" \
  -n "$RUNTIME_NS" \
  -o custom-columns='KIND:.kind,NAME:.metadata.name,NAMESPACE:.metadata.namespace,PART_OF:.metadata.labels.app\.kubernetes\.io/part-of'
```

Runtime도 현재-only inventory 포함 여부와 ownership label을 삭제 명령과 같은
조건부 블록에서 확인한다.

```bash
if
  test -n "$EXTRA_RUNTIME_RESOURCE" \
  && comm -23 "$CURRENT_RUNTIME_INVENTORY" "$EXPECTED_RUNTIME_INVENTORY" \
    | rg --fixed-strings --line-regexp -- "$EXTRA_RUNTIME_RESOURCE" >/dev/null \
  && test "$(
    oc get "$EXTRA_RUNTIME_RESOURCE" \
      -n "$RUNTIME_NS" \
      -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}'
  )" = 'bamoe-runtime-environment'
then
  oc delete "$EXTRA_RUNTIME_RESOURCE" -n "$RUNTIME_NS"
else
  printf 'REFUSE: resource is not a verified Runtime rollback extra\n' >&2
fi
```

검증된 Runtime 추가 리소스가 더 있으면 같은 네 단계를 반복한다. inventory에
표시되지 않은 리소스나 ownership label이 다른 리소스는 삭제하지 않는다.

삭제 후 같은 kind 목록의 현재 inventory를 다시 만들어 차이가 비었는지 확인한다.

```bash
oc get deployment,service,route,configmap,serviceaccount,secret,persistentvolumeclaim,networkpolicy,role,rolebinding \
  -n "$DEV_NS" \
  -l app.kubernetes.io/part-of=bamoe-dev-environment \
  -o name \
  | sort \
  > "$CURRENT_DEV_INVENTORY"

oc get deployment,service,route,configmap,serviceaccount,secret,persistentvolumeclaim,networkpolicy,role,rolebinding \
  -n "$RUNTIME_NS" \
  -l app.kubernetes.io/part-of=bamoe-runtime-environment \
  -o name \
  | sort \
  > "$CURRENT_RUNTIME_INVENTORY"

if [ -z "$(
  comm -23 "$CURRENT_DEV_INVENTORY" "$EXPECTED_DEV_INVENTORY"
)" ] \
  && [ -z "$(
    comm -23 "$CURRENT_RUNTIME_INVENTORY" "$EXPECTED_RUNTIME_INVENTORY"
  )" ]
then
  printf 'PRODUCT_ROLLBACK_INVENTORY_GATE=PASS\n'
else
  printf 'PRODUCT_ROLLBACK_INVENTORY_GATE=FAIL\n' >&2
fi
```

이 kind 목록은 현재 제품 manifest 계약에 맞춘 것이다. 향후 StatefulSet, Job,
PDB 또는 다른 kind를 제품 manifest에 추가할 때에는 배포 review에서 이 current
inventory 조회 목록과 rollback 절차도 함께 확장해야 한다. 그렇지 않으면 “정확한
manifest 복원”을 주장하지 않는다.

Route와 실제 image를 다시 읽는다.

```bash
oc get deployment,route \
  -n "$DEV_NS" \
  -l app.kubernetes.io/part-of=bamoe-dev-environment
```

```bash
oc get deployment,route \
  -n "$RUNTIME_NS" \
  -l app.kubernetes.io/part-of=bamoe-runtime-environment
```

제품 manifest 복구 전 Gate는 version 관리된 Management Console 등록 URL과 현재
앱 CORS의 계약을 확인한다. 실제 브라우저 동작과 MCP OpenAPI 해석까지 대신하지는
않으므로 §11.4의 등록값, §11.5의 MCP URL/log, §11.6의 CORS를 다시 확인한다.

복구와 검증이 끝나면 이번 절이 만든 `/tmp` 자산만 정리한다. 아래 조건부 블록은
일곱 경로가 모두 기대한 prefix이고 실제 파일/디렉터리일 때만 삭제한다.

```bash
if (
  case "${PRODUCT_ROLLBACK_DIR:-}" in
    /tmp/bamoe-product-rollback.*) ;;
    *) exit 1 ;;
  esac
  case "${DEV_ROLLBACK_RENDERED:-}" in
    /tmp/bamoe-dev-rollback.*) ;;
    *) exit 1 ;;
  esac
  case "${RUNTIME_ROLLBACK_RENDERED:-}" in
    /tmp/bamoe-runtime-rollback.*) ;;
    *) exit 1 ;;
  esac
  case "${CURRENT_DEV_INVENTORY:-}" in
    /tmp/bamoe-current-dev-inventory.*) ;;
    *) exit 1 ;;
  esac
  case "${EXPECTED_DEV_INVENTORY:-}" in
    /tmp/bamoe-expected-dev-inventory.*) ;;
    *) exit 1 ;;
  esac
  case "${CURRENT_RUNTIME_INVENTORY:-}" in
    /tmp/bamoe-current-runtime-inventory.*) ;;
    *) exit 1 ;;
  esac
  case "${EXPECTED_RUNTIME_INVENTORY:-}" in
    /tmp/bamoe-expected-runtime-inventory.*) ;;
    *) exit 1 ;;
  esac
  test -d "$PRODUCT_ROLLBACK_DIR" || exit 1
  test -f "$DEV_ROLLBACK_RENDERED" || exit 1
  test -f "$RUNTIME_ROLLBACK_RENDERED" || exit 1
  test -f "$CURRENT_DEV_INVENTORY" || exit 1
  test -f "$EXPECTED_DEV_INVENTORY" || exit 1
  test -f "$CURRENT_RUNTIME_INVENTORY" || exit 1
  test -f "$EXPECTED_RUNTIME_INVENTORY" || exit 1
)
then
  unlink "$DEV_ROLLBACK_RENDERED"
  unlink "$RUNTIME_ROLLBACK_RENDERED"
  unlink "$CURRENT_DEV_INVENTORY"
  unlink "$EXPECTED_DEV_INVENTORY"
  unlink "$CURRENT_RUNTIME_INVENTORY"
  unlink "$EXPECTED_RUNTIME_INVENTORY"
  rm -R -- "$PRODUCT_ROLLBACK_DIR"
  unset \
    PRODUCT_ROLLBACK_DIR \
    DEV_ROLLBACK_RENDERED \
    RUNTIME_ROLLBACK_RENDERED \
    CURRENT_DEV_INVENTORY \
    EXPECTED_DEV_INVENTORY \
    CURRENT_RUNTIME_INVENTORY \
    EXPECTED_RUNTIME_INVENTORY
else
  printf 'REFUSE: unexpected rollback temporary path\n' >&2
fi
```

**Gate**

- 긴급 rollback이면 정확한 Deployment와 성공 revision만 되돌렸다.
- 묶음 rollback이면 검증된 Git commit의 제품 디렉터리만 임시 위치에 풀었다.
- 이전 manifest에 없는 현재 리소스를 inventory로 비교하고, 검증된 추가 리소스만
  exact name으로 정리했다.
- Dev와 Runtime 복구안을 각각 server dry-run하고 diff를 읽었다.
- 관련 Deployment가 모두 Ready다.
- Route, Management Console 등록, MCP OpenAPI, 앱 CORS를 다시 확인했다.
- prefix를 검증한 rollback 임시 자산을 정리했다.
- 긴급 rollback 상태와 Git manifest 사이에 장기 drift를 남기지 않았다.

### 16.3 앱과 Mock image rollback

앱 history를 조회한다.

```bash
oc rollout history deployment/customer-rule-poc -n "$APP_NS"
```

Mock history를 조회한다.

```bash
oc rollout history deployment/customer-rule-mock -n "$APP_NS"
```

앱에서 되돌릴 revision을 직접 기록한다.

```bash
export APP_ROLLBACK_REVISION='<검증한 앱 revision 숫자>'
```

Mock에서 되돌릴 revision을 직접 기록한다.

```bash
export MOCK_ROLLBACK_REVISION='<검증한 Mock revision 숫자>'
```

앱 revision 상세를 조회한다.

```bash
oc rollout history deployment/customer-rule-poc -n "$APP_NS" --revision="$APP_ROLLBACK_REVISION"
```

Mock revision 상세를 조회한다.

```bash
oc rollout history deployment/customer-rule-mock -n "$APP_NS" --revision="$MOCK_ROLLBACK_REVISION"
```

두 revision의 ReplicaSet에서 container 이름으로 target image를 직접 읽는다.

```bash
export APP_ROLLBACK_IMAGES_JSON="$(
  oc get replicaset \
    -n "$APP_NS" \
    -l app.kubernetes.io/name=customer-rule-poc \
    -o json \
  | jq -c \
      --arg revision "$APP_ROLLBACK_REVISION" \
      '
        [
          .items[]
          | select(
              .metadata.annotations["deployment.kubernetes.io/revision"]
              == $revision
            )
          | .spec.template.spec.containers[]
          | select(.name == "application")
          | .image
        ]
        | unique
      '
)"
export APP_ROLLBACK_IMAGE_COUNT="$(
  jq 'length' <<<"$APP_ROLLBACK_IMAGES_JSON"
)"
export APP_ROLLBACK_IMAGE="$(
  jq -r 'if length == 1 then .[0] else empty end' \
    <<<"$APP_ROLLBACK_IMAGES_JSON"
)"
```

```bash
export MOCK_ROLLBACK_IMAGES_JSON="$(
  oc get replicaset \
    -n "$APP_NS" \
    -l app.kubernetes.io/name=customer-rule-mock \
    -o json \
  | jq -c \
      --arg revision "$MOCK_ROLLBACK_REVISION" \
      '
        [
          .items[]
          | select(
              .metadata.annotations["deployment.kubernetes.io/revision"]
              == $revision
            )
          | .spec.template.spec.containers[]
          | select(.name == "mock")
          | .image
        ]
        | unique
      '
)"
export MOCK_ROLLBACK_IMAGE_COUNT="$(
  jq 'length' <<<"$MOCK_ROLLBACK_IMAGES_JSON"
)"
export MOCK_ROLLBACK_IMAGE="$(
  jq -r 'if length == 1 then .[0] else empty end' \
    <<<"$MOCK_ROLLBACK_IMAGES_JSON"
)"
```

각 revision이 서로 다른 image를 여러 개 가리키지 않고 정확히 한 후보만
만들었는지, 승인된 owner의 `tag@digest` 형식인지, 두 tag의 40자리 commit이
같은지 검사한다. 결과를 이후 모든 변경 블록이 재사용할 boolean으로 저장한다.

```bash
APP_ROLLBACK_SHA="$(
  printf '%s\n' "$APP_ROLLBACK_IMAGE" \
  | sed -nE 's#^.*:sha-([0-9a-f]{40})@sha256:[0-9a-f]{64}$#\1#p'
)"
MOCK_ROLLBACK_SHA="$(
  printf '%s\n' "$MOCK_ROLLBACK_IMAGE" \
  | sed -nE 's#^.*:sha-([0-9a-f]{40})@sha256:[0-9a-f]{64}$#\1#p'
)"

if [ "$APP_ROLLBACK_IMAGE_COUNT" -eq 1 ] \
  && [ "$MOCK_ROLLBACK_IMAGE_COUNT" -eq 1 ] \
  && printf '%s\n' "$APP_ROLLBACK_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-poc:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}" \
  && printf '%s\n' "$MOCK_ROLLBACK_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-mock:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}" \
  && [ "$APP_ROLLBACK_SHA" = "$MOCK_ROLLBACK_SHA" ]
then
  export ROLLBACK_TARGET_PAIR_OK=true
  printf 'ROLLBACK_TARGET_PAIR_GATE=PASS (%s)\n' "$APP_ROLLBACK_SHA"
else
  export ROLLBACK_TARGET_PAIR_OK=false
  printf 'ROLLBACK_TARGET_PAIR_GATE=FAIL\n' >&2
fi
```

`PASS`가 아니면 rollback하지 않는다.

현재 image를 마지막으로 조회한다.

```bash
oc get deployment/customer-rule-mock \
  deployment/customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas'
```

보상 복구에 사용할 현재 image는 출력에서 복사하지 않고 container 이름으로
직접 읽는다.

```bash
export PRE_ROLLBACK_MOCK_IMAGE="$(
  oc get deployment/customer-rule-mock \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="mock")].image}'
)"
export PRE_ROLLBACK_APP_IMAGE="$(
  oc get deployment/customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="application")].image}'
)"

printf 'PRE_MOCK=%s\nPRE_APP=%s\n' \
  "$PRE_ROLLBACK_MOCK_IMAGE" \
  "$PRE_ROLLBACK_APP_IMAGE"
```

보상 reference도 승인된 owner와 전체 digest를 포함하는지 검사한다.

```bash
PRE_APP_SHA="$(
  printf '%s\n' "$PRE_ROLLBACK_APP_IMAGE" \
  | sed -nE 's#^.*:sha-([0-9a-f]{40})@sha256:[0-9a-f]{64}$#\1#p'
)"
PRE_MOCK_SHA="$(
  printf '%s\n' "$PRE_ROLLBACK_MOCK_IMAGE" \
  | sed -nE 's#^.*:sha-([0-9a-f]{40})@sha256:[0-9a-f]{64}$#\1#p'
)"

if printf '%s\n' "$PRE_ROLLBACK_APP_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-poc:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}" \
  && printf '%s\n' "$PRE_ROLLBACK_MOCK_IMAGE" \
    | rg -q -x \
      "ghcr\\.io/${GITHUB_OWNER}/customer-rule-mock:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}" \
  && [ "$PRE_APP_SHA" = "$PRE_MOCK_SHA" ]
then
  export ROLLBACK_COMPENSATION_IMAGE_OK=true
  printf 'ROLLBACK_COMPENSATION_IMAGE_GATE=PASS\n'
else
  export ROLLBACK_COMPENSATION_IMAGE_OK=false
  printf 'ROLLBACK_COMPENSATION_IMAGE_GATE=FAIL\n' >&2
fi
```

두 image Gate가 모두 `PASS`일 때 Mock image 하나를 먼저 바꾼다. 여기서는
`oc rollout undo`를 사용하지 않는다. 그것은 선택한 revision의 env, probe,
resources 등 전체 Pod template까지 되돌릴 수 있기 때문이다. 검증한 image
reference만 `oc set image`로 변경한다.

```bash
if [ "$ROLLBACK_TARGET_PAIR_OK" = true ] \
  && [ "$ROLLBACK_COMPENSATION_IMAGE_OK" = true ]
then
  if oc set image deployment/customer-rule-mock \
    "mock=${MOCK_ROLLBACK_IMAGE}" \
    -n "$APP_NS"
  then
    export MOCK_ROLLBACK_MUTATION_OK=true
  else
    export MOCK_ROLLBACK_MUTATION_OK=false
  fi
else
  export MOCK_ROLLBACK_MUTATION_OK=false
  printf 'REFUSE: Mock rollback target pair is not validated\n' >&2
fi
```

Mock rollout을 관찰한다.

```bash
if [ "$MOCK_ROLLBACK_MUTATION_OK" = true ] \
  && oc rollout status deployment/customer-rule-mock \
    -n "$APP_NS" \
    --timeout=5m
then
  export MOCK_ROLLBACK_READY=true
else
  export MOCK_ROLLBACK_READY=false
  printf 'STOP: Mock rollback is not Ready; use compensation below\n' >&2
fi
```

Mock이 Ready일 때 앱 하나를 rollback한다.

```bash
if [ "$ROLLBACK_TARGET_PAIR_OK" = true ] \
  && [ "$ROLLBACK_COMPENSATION_IMAGE_OK" = true ] \
  && [ "$MOCK_ROLLBACK_READY" = true ]
then
  if oc set image deployment/customer-rule-poc \
    "application=${APP_ROLLBACK_IMAGE}" \
    -n "$APP_NS"
  then
    export APP_ROLLBACK_MUTATION_OK=true
  else
    export APP_ROLLBACK_MUTATION_OK=false
  fi
else
  export APP_ROLLBACK_MUTATION_OK=false
  printf 'REFUSE: application rollback target pair is not validated\n' >&2
fi
```

앱 rollout을 관찰한다.

```bash
if [ "$APP_ROLLBACK_MUTATION_OK" = true ] \
  && oc rollout status deployment/customer-rule-poc \
    -n "$APP_NS" \
    --timeout=8m
then
  export APP_ROLLBACK_READY=true
else
  export APP_ROLLBACK_READY=false
  printf 'STOP: application rollback is not Ready; use compensation below\n' >&2
fi
```

**실패 시에만 실행:** Mock 또는 앱 rollback 중 하나라도 실패하면 mixed commit
상태에서 테스트를 계속하지 않는다. 아래 한 블록은 보상 image 형식과 같은
commit을 **다시 검증한 조건문 안에서만** 시작 전 image 쌍을 복원한다.

```bash
if [ "$ROLLBACK_COMPENSATION_IMAGE_OK" = true ] \
  && {
    [ "${MOCK_ROLLBACK_READY:-false}" != true ] \
      || [ "${APP_ROLLBACK_READY:-false}" != true ]
  }
then
  oc set image deployment/customer-rule-mock \
    "mock=${PRE_ROLLBACK_MOCK_IMAGE}" \
    -n "$APP_NS" \
  && oc rollout status deployment/customer-rule-mock \
    -n "$APP_NS" \
    --timeout=5m \
  && oc set image deployment/customer-rule-poc \
    "application=${PRE_ROLLBACK_APP_IMAGE}" \
    -n "$APP_NS" \
  && oc rollout status deployment/customer-rule-poc \
    -n "$APP_NS" \
    --timeout=8m
else
  printf 'REFUSE: compensation is unneeded or image validation failed\n' >&2
fi
```

이 보상 명령은 rollback이 모두 성공했다면 실행하지 않는다. 보상도 실패하면
추가 변경을 멈추고 두 Deployment의 현재 image, ReplicaSet, Event를 기록한다.

복원된 두 image를 조회한다.

```bash
oc get deployment/customer-rule-mock \
  deployment/customer-rule-poc \
  -n "$APP_NS" \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas'
```

사람이 표를 읽는 것과 별도로 live container image가 검증한 rollback target과
정확히 같은지 기계적으로 확인한다.

```bash
export LIVE_ROLLBACK_MOCK_IMAGE="$(
  oc get deployment/customer-rule-mock \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="mock")].image}'
)"
```

```bash
export LIVE_ROLLBACK_APP_IMAGE="$(
  oc get deployment/customer-rule-poc \
    -n "$APP_NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="application")].image}'
)"
```

```bash
if [ "${MOCK_ROLLBACK_READY:-false}" = true ] \
  && [ "${APP_ROLLBACK_READY:-false}" = true ] \
  && [ "$LIVE_ROLLBACK_MOCK_IMAGE" = "$MOCK_ROLLBACK_IMAGE" ] \
  && [ "$LIVE_ROLLBACK_APP_IMAGE" = "$APP_ROLLBACK_IMAGE" ]
then
  printf 'LIVE_ROLLBACK_IMAGE_GATE=PASS\n'
else
  printf 'LIVE_ROLLBACK_IMAGE_GATE=FAIL\n' >&2
  false
fi
```

외부 OpenAPI를 확인한다.

```bash
if [ -n "${APP_BASE_URL:-}" ]; then
  curl --fail --silent --show-error \
    "${APP_BASE_URL}/v3/api-docs" \
  | jq -e '.paths | length > 0'
else
  printf 'SKIP: live Business Service Route is absent\n'
fi
```

**Gate**

- 자동 배포가 `false`다.
- rollback한 두 image가 같은 Git commit 쌍이다.
- Mock과 앱 rollout이 차례대로 성공했다.
- live container image가 두 rollback target reference와 exact 일치한다.
- live Business Service Route가 있으면 외부 OpenAPI가 성공한다.
- Route가 없어서 위 검사가 `SKIP`이면 rollback image 검증과 Route 복구를
  별도 단계로 기록하고, 외부 접근까지 복구하기 전에는 전체 rollback 완료로
  판정하지 않는다.

## 17. PoC 종료 시 안전한 정리

이 섹션은 Project 전체를 삭제하지 않는다. 외부 노출, 자동 배포 권한, 임시
Canvas 계정만 정확한 이름으로 하나씩 제거한다. 앱/Mock Pod와 내부 Service,
Dev/Runtime 제품 Deployment와 내부 Service는 보존한다.

`--ignore-not-found`는 재실행 시 없는 대상을 허용할 뿐, 잘못된 대상을 안전하게
만들어 주지 않는다. 모든 삭제 전에 같은 이름을 먼저 조회한다.

새 terminal에서 시작했다면 먼저 환경 파일이 있는 프로젝트 root로 이동한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

정리 대상 namespace와 repository 값을 다시 불러온다.

```bash
source deploy/openshift/ocp-env.sh
```

필수 값과 `oc` client를 검증한다.

```bash
bamoe_check_env
```

정리 대상 네 Project의 실제 이름과 ownership label을 한 번에 조회한다.

```bash
oc get namespace \
  "$DEV_NS" \
  "$RUNTIME_NS" \
  "$APP_NS" \
  "$SANDBOX_NS" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

네 행 모두 `STATUS=Active`, `OWNER=bamoe-poc-guide`여야 한다. 하나라도 다르면 해당
Project의 삭제 단계는 실행하지 않는다.

GitHub 작업 사본으로 이동한다.

```bash
cd "$GITHUB_WORK_DIR"
```

삭제 전에 현재 GitHub repository와 OpenShift API server를 각각 확인한다.

```bash
gh repo view "${GITHUB_OWNER}/${GITHUB_REPO}" --json nameWithOwner,isPrivate,url
```

```bash
oc whoami --show-server
```

repository가 예상한 private repository가 아니거나 출력된 API server가
`OCP_API_SERVER`와 다르면 정리 명령을 실행하지 않는다.

### 17.1 자동 배포와 GitHub의 OpenShift Secret 제거

자동 배포를 끈다.

```bash
gh variable set OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --body false
```

결과를 관찰한다.

```bash
gh variable get OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

대기 중인 build/deploy run을 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --status queued \
  --limit 10
```

실행 중인 run을 조회한다.

```bash
gh run list \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --workflow build-images.yml \
  --status in_progress \
  --limit 10
```

두 목록이 모두 비어 있어야 Secret과 RBAC를 삭제한다. 이미 시작한 run은
`OCP_AUTO_DEPLOY=false`로 중단되지 않으므로, 남아 있다면 정확한 run을 끝까지
관찰하고 OCP image 상태를 확인한 뒤 정리를 재개한다.

Environment ownership marker와 secret 이름을 조회한다.

```bash
gh variable get BAMOE_GUIDE_OWNER \
  --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
  --env ocp-poc
```

```bash
gh secret list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

이 가이드는 `BAMOE_GUIDE_OWNER=bamoe-poc-guide`인 `ocp-poc` Environment만
관리한다. marker, 존재 여부, 삭제를 같은 조건문에서 검사한다.

```bash
cleanup_env_owner="$(
  gh variable get BAMOE_GUIDE_OWNER \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc \
    2>/dev/null \
  || true
)"
cleanup_token_present="$(
  gh secret list \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc \
    --json name \
    --jq '.[] | select(.name == "OPENSHIFT_TOKEN") | .name'
)"
cleanup_ca_present="$(
  gh secret list \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --env ocp-poc \
    --json name \
    --jq '.[] | select(.name == "OPENSHIFT_CA_DATA") | .name'
)"

if [ "$cleanup_env_owner" != 'bamoe-poc-guide' ]; then
  printf 'REFUSE: ocp-poc Environment is not owned by this guide\n' >&2
else
  if [ -n "$cleanup_token_present" ]; then
    gh secret delete OPENSHIFT_TOKEN \
      --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
      --env ocp-poc
  else
    printf 'ALREADY_ABSENT: Environment secret OPENSHIFT_TOKEN\n'
  fi

  if [ -n "$cleanup_ca_present" ]; then
    gh secret delete OPENSHIFT_CA_DATA \
      --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
      --env ocp-poc
  else
    printf 'ALREADY_ABSENT: Environment secret OPENSHIFT_CA_DATA\n'
  fi
fi
```

repository-level Secret은 이 가이드의 관리 scope가 아니다. 이름만 조회하고
같은 이름이 있어도 삭제하지 않는다.

```bash
gh secret list --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

Environment 목록에서 두 이름이 사라졌는지 관찰한다.

```bash
gh secret list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

repository 목록에 `OPENSHIFT_TOKEN`이나 `OPENSHIFT_CA_DATA`가 남아 있다면 이
가이드가 만든 것이 아니므로 보존하고 repository 관리자에게 소유자를 확인한다.

### 17.2 GitHub Actions RBAC 제거

세 리소스의 ownership label과 RoleBinding 계약을 조회한다.

```bash
oc get serviceaccount github-actions-deployer \
  -n "$APP_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,PART_OF:.metadata.labels.app\.kubernetes\.io/part-of'
```

```bash
oc get role github-actions-deployer \
  -n "$APP_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,PART_OF:.metadata.labels.app\.kubernetes\.io/part-of'
```

```bash
oc get rolebinding github-actions-deployer \
  -n "$APP_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,PART_OF:.metadata.labels.app\.kubernetes\.io/part-of,ROLE:.roleRef.name,SUBJECT:.subjects[0].name,SUBJECT_NS:.subjects[0].namespace'
```

namespace ownership, 각 `part-of` label, RoleBinding의 roleRef와 subject를 삭제와
같은 조건문에서 다시 검사한다. 세 리소스 중 일부만 이미 없어도 나머지가 모두
정확한 계약이면 정리할 수 있다.

```bash
cleanup_actions_owned_or_absent() {
  resource_kind="$1"
  resource_name="$(
    oc get "$resource_kind" github-actions-deployer \
      -n "$APP_NS" \
      --ignore-not-found \
      -o jsonpath='{.metadata.name}'
  )"
  resource_part_of="$(
    oc get "$resource_kind" github-actions-deployer \
      -n "$APP_NS" \
      --ignore-not-found \
      -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}'
  )"

  [ -z "$resource_name" ] \
    || [ "$resource_part_of" = 'bamoe-customer-rule-poc' ]
}

cleanup_actions_sa_name="$(
  oc get serviceaccount github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.name}'
)"
cleanup_actions_role_name="$(
  oc get role github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.name}'
)"
cleanup_actions_binding_name="$(
  oc get rolebinding github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.metadata.name}'
)"
cleanup_actions_binding_contract=true

if [ -n "$cleanup_actions_binding_name" ]; then
  if ! oc get rolebinding github-actions-deployer \
      -n "$APP_NS" \
      -o json \
    | jq -e \
        --arg namespace "$APP_NS" \
        '
          .roleRef.kind == "Role"
          and .roleRef.name == "github-actions-deployer"
          and (.subjects | length) == 1
          and .subjects[0].kind == "ServiceAccount"
          and .subjects[0].name == "github-actions-deployer"
          and .subjects[0].namespace == $namespace
        ' \
    >/dev/null
  then
    cleanup_actions_binding_contract=false
  fi
fi

if [ -z "${cleanup_actions_sa_name}${cleanup_actions_role_name}${cleanup_actions_binding_name}" ]; then
  printf 'ALREADY_ABSENT: GitHub Actions RBAC\n'
elif [ "$(
  oc get namespace "$APP_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)" = 'bamoe-poc-guide' ] \
  && cleanup_actions_owned_or_absent serviceaccount \
  && cleanup_actions_owned_or_absent role \
  && cleanup_actions_owned_or_absent rolebinding \
  && [ "$cleanup_actions_binding_contract" = true ]
then
  oc delete rolebinding github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found
  oc delete role github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found
  oc delete serviceaccount github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found
else
  printf 'REFUSE: GitHub Actions RBAC ownership or contract mismatch\n' >&2
fi
```

ServiceAccount가 삭제되면 그 계정에 발급된 token도 무효화되는 폐기 경계다.
세 이름이 모두 비어 있는지 확인한다.

```bash
for resource_kind in serviceaccount role rolebinding; do
  oc get "$resource_kind" github-actions-deployer \
    -n "$APP_NS" \
    --ignore-not-found \
    -o name
done
```

### 17.3 Business Service 외부 Route 제거

삭제할 Route의 Service와 host를 조회한다.

```bash
oc get route customer-rule-poc \
  -n "$APP_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,SERVICE:.spec.to.name,HOST:.spec.host,TLS:.spec.tls.termination'
```

namespace ownership과 `SERVICE=customer-rule-poc`을 삭제와 같은 조건문에서
확인한다.

```bash
app_route_service="$(
  oc get route customer-rule-poc \
    -n "$APP_NS" \
    --ignore-not-found \
    -o jsonpath='{.spec.to.name}'
)"

if [ -z "$app_route_service" ]; then
  printf 'ALREADY_ABSENT: route/customer-rule-poc\n'
elif [ "$(
  oc get namespace "$APP_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)" = 'bamoe-poc-guide' ] \
  && [ "$app_route_service" = 'customer-rule-poc' ]
then
  oc delete route customer-rule-poc -n "$APP_NS"
else
  printf 'REFUSE: Business Service Route ownership or target mismatch\n' >&2
fi
```

출력이 비어 있는지 관찰한다.

```bash
oc get route customer-rule-poc -n "$APP_NS" --ignore-not-found -o name
```

Mock API에는 처음부터 외부 Route가 없어야 한다.

```bash
oc get route -n "$APP_NS" -o custom-columns='NAME:.metadata.name,SERVICE:.spec.to.name,HOST:.spec.host'
```

### 17.4 Canvas 계정과 Mock alias 제거

Canvas 계정을 지우기 전에 Canvas가 만든 sandbox Deployment와 workspace
metadata를 조회한다.

```bash
oc get deployment \
  -n "$SANDBOX_NS" \
  -l 'tools.kie.org/created-by=kie-tools' \
  -o json \
  | jq -r '
      .items[]
      | [
          .metadata.name,
          .metadata.annotations["tools.kie.org/workspace-id"],
          .metadata.annotations["tools.kie.org/workspace-name"]
        ]
      | @tsv
    '
```

§13.6에서 기록한 이번 PoC workspace만 Canvas UI의 Dev Deployments 목록에서
이름을 대조해 하나씩 삭제한다. **Delete all**이나 CLI의 `--all`은 같은
namespace를 쓰는 다른 Canvas 작업까지 지울 수 있으므로 사용하지 않는다.

삭제 후 같은 목록을 다시 조회한다.

```bash
oc get deployment \
  -n "$SANDBOX_NS" \
  -l 'tools.kie.org/created-by=kie-tools' \
  -o json \
  | jq -r '
      .items[]
      | [
          .metadata.name,
          .metadata.annotations["tools.kie.org/workspace-id"],
          .metadata.annotations["tools.kie.org/workspace-name"]
        ]
      | @tsv
    '
```

이번 PoC 이름이 없어야 한다. 다른 workspace의 행이 남아 있으면 소유자 확인 없이
삭제하지 않는다. sandbox의 전체 resource는 조회만 한다.

```bash
oc get deployment,pod,service,route -n "$SANDBOX_NS"
```

Canvas 최소권한 ServiceAccount·Role·RoleBinding을 이름과 label만 조회한다.

```bash
oc get \
  serviceaccount/bamoe-canvas-deployer \
  role/bamoe-canvas-deployer \
  rolebinding/bamoe-canvas-deployer \
  -n "$SANDBOX_NS" \
  --ignore-not-found \
  -o custom-columns='KIND:.kind,NAME:.metadata.name,PART_OF:.metadata.labels.app\.kubernetes\.io/part-of'
```

namespace ownership, 각 리소스의 PoC label, RoleBinding이 가리키는 Role과
ServiceAccount subject를 삭제와 같은 블록에서 확인한다. 세 리소스가 전부
없으면 `ALREADY_ABSENT`로 기록한다. 이전 삭제가 중간에 끊겨 일부만 남았어도
남은 각 리소스의 ownership이 맞고, RoleBinding이 남아 있다면 전체 연결 계약까지
맞을 때만 exact name으로 재개한다. 삭제는 `&&`로 연결해 첫 실패에서 즉시
멈추며, 재실행하면 같은 검증 뒤 남은 리소스만 정리한다.

```bash
CANVAS_RBAC_JSON="$(
  oc get \
    serviceaccount/bamoe-canvas-deployer \
    role/bamoe-canvas-deployer \
    rolebinding/bamoe-canvas-deployer \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
    -o json \
  | jq -s '
      {
        items: [
          .[]
          | if .kind == "List" then .items[] else . end
        ]
      }
    '
)"
CANVAS_RBAC_COUNT="$(jq '.items | length' <<<"$CANVAS_RBAC_JSON")"

if [ "$CANVAS_RBAC_COUNT" -eq 0 ]; then
  printf 'ALREADY_ABSENT: Canvas 최소권한 리소스 3개\n'
elif [ "$(
  oc get namespace "$SANDBOX_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)" != 'bamoe-poc-guide' ]; then
  printf 'REFUSE: sandbox namespace ownership mismatch\n' >&2
elif ! jq -e '
  all(
    .items[];
    .metadata.labels["app.kubernetes.io/part-of"]
      == "bamoe-customer-rule-poc"
  )
' <<<"$CANVAS_RBAC_JSON" >/dev/null; then
  printf 'REFUSE: Canvas RBAC ownership label mismatch\n' >&2
elif ! jq -e \
  --arg namespace "$SANDBOX_NS" \
  '
  (
    [.items[] | select(.kind == "RoleBinding")]
    | length
  ) as $bindingCount
  | $bindingCount == 0
    or (
      [
        .items[]
        | select(.kind == "RoleBinding")
        | select(
            .roleRef.apiGroup == "rbac.authorization.k8s.io"
            and .roleRef.kind == "Role"
            and .roleRef.name == "bamoe-canvas-deployer"
            and (.subjects | length) == 1
            and .subjects[0].kind == "ServiceAccount"
            and .subjects[0].name == "bamoe-canvas-deployer"
            and .subjects[0].namespace == $namespace
          )
      ]
      | length == 1
    )
' \
  <<<"$CANVAS_RBAC_JSON" \
  >/dev/null
then
  printf 'REFUSE: Canvas RoleBinding contract mismatch\n' >&2
else
  oc delete rolebinding/bamoe-canvas-deployer \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
  && oc delete role/bamoe-canvas-deployer \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
  && oc delete serviceaccount/bamoe-canvas-deployer \
    -n "$SANDBOX_NS" \
    --ignore-not-found
fi
```

세 리소스가 사라졌는지 확인한다.

```bash
oc get \
  serviceaccount/bamoe-canvas-deployer \
  role/bamoe-canvas-deployer \
  rolebinding/bamoe-canvas-deployer \
  -n "$SANDBOX_NS" \
  --ignore-not-found \
  -o name
```

Mock alias의 type과 대상을 조회한다.

```bash
oc get service customer-rule-mock \
  -n "$SANDBOX_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,TYPE:.spec.type,EXTERNAL_NAME:.spec.externalName'
```

namespace ownership, Service type, 정확한 ExternalName target을 삭제와 같은
조건문에서 다시 검증한다.

```bash
sandbox_alias_type="$(
  oc get service customer-rule-mock \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
    -o jsonpath='{.spec.type}'
)"
sandbox_alias_target="$(
  oc get service customer-rule-mock \
    -n "$SANDBOX_NS" \
    --ignore-not-found \
    -o jsonpath='{.spec.externalName}'
)"

if [ -z "$sandbox_alias_type" ]; then
  printf 'ALREADY_ABSENT: service/customer-rule-mock\n'
elif [ "$(
  oc get namespace "$SANDBOX_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)" = 'bamoe-poc-guide' ] \
  && [ "$sandbox_alias_type" = 'ExternalName' ] \
  && [ "$sandbox_alias_target" = "customer-rule-mock.${APP_NS}.svc.cluster.local" ]
then
  oc delete service customer-rule-mock -n "$SANDBOX_NS"
else
  printf 'REFUSE: sandbox mock alias contract does not match\n' >&2
fi
```

삭제 결과를 관찰한다.

```bash
oc get service customer-rule-mock -n "$SANDBOX_NS" --ignore-not-found -o name
```

clipboard를 비운다.

```bash
printf '' | pbcopy
```

Canvas에 연결한 GitHub PAT는 GitHub의 **Settings → Developer settings**에서
폐기하고 Canvas의 GitHub/OpenShift account 연결도 제거한다.

### 17.5 제품 UI와 sandbox Route를 정확한 이름으로 제거

Canvas, Extended Services, CORS Proxy, Management Console이 시연 후 계속
인터넷에 공개되지 않도록 manifest에 고정한 Route 네 개만 제거한다. Maven
Repository와 MCP Server는 처음부터 외부 Route가 없어야 한다. Project 전체 Route
삭제나 `--all`은 사용하지 않는다.

Dev Project ownership을 확인한다.

```bash
oc get namespace "$DEV_NS" \
  -o custom-columns='NAME:.metadata.name,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

ownership을 변경 없이 Gate로 검증한다.

```bash
if [ "$(
  oc get namespace "$DEV_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)" = 'bamoe-poc-guide' ]; then
  printf 'DEV_NAMESPACE_OWNERSHIP_GATE=PASS\n'
else
  printf 'DEV_NAMESPACE_OWNERSHIP_GATE=FAIL\n' >&2
fi
```

실패하면 Dev Route 삭제를 중단한다.

삭제할 Dev Route 세 개의 Service와 host를 조회한다.

```bash
oc get route \
  bamoe-canvas \
  bamoe-cors-proxy \
  bamoe-extended-services \
  -n "$DEV_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,SERVICE:.spec.to.name,HOST:.spec.host'
```

각 행의 이름과 Service가 같은지 확인한다. 아래 한 블록은 namespace ownership과
Route→Service 계약을 **삭제와 같은 조건문 안에서 다시 검사**한다. Route가 이미
없으면 `ALREADY_ABSENT`, 다른 Service를 가리키면 `REFUSE`를 출력하고 보존한다.

```bash
if [ "$(
  oc get namespace "$DEV_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)" = 'bamoe-poc-guide' ]; then
  for route_name in \
    bamoe-canvas \
    bamoe-cors-proxy \
    bamoe-extended-services
  do
    route_service="$(
      oc get route "$route_name" \
        -n "$DEV_NS" \
        --ignore-not-found \
        -o jsonpath='{.spec.to.name}'
    )"

    if [ -z "$route_service" ]; then
      printf 'ALREADY_ABSENT: route/%s\n' "$route_name"
    elif [ "$route_service" = "$route_name" ]; then
      oc delete route "$route_name" -n "$DEV_NS"
    else
      printf 'REFUSE: route/%s targets unexpected service %s\n' \
        "$route_name" \
        "$route_service" \
        >&2
    fi
  done
else
  printf 'REFUSE: Dev namespace ownership mismatch\n' >&2
fi
```

세 Route가 모두 사라졌는지 확인한다.

```bash
oc get route \
  bamoe-canvas \
  bamoe-cors-proxy \
  bamoe-extended-services \
  -n "$DEV_NS" \
  --ignore-not-found \
  -o name
```

정상 관찰값은 빈 출력이다.

Maven Repository Route가 생성된 적 없는지도 확인한다.

```bash
oc get route bamoe-maven-repository \
  -n "$DEV_NS" \
  --ignore-not-found \
  -o name
```

정상 관찰값은 빈 출력이다.

Runtime Project ownership을 확인한다.

```bash
oc get namespace "$RUNTIME_NS" \
  -o custom-columns='NAME:.metadata.name,OWNER:.metadata.labels.app\.kubernetes\.io/managed-by'
```

ownership Gate를 검증한다.

```bash
if [ "$(
  oc get namespace "$RUNTIME_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)" = 'bamoe-poc-guide' ]; then
  printf 'RUNTIME_NAMESPACE_OWNERSHIP_GATE=PASS\n'
else
  printf 'RUNTIME_NAMESPACE_OWNERSHIP_GATE=FAIL\n' >&2
fi
```

실패하면 Runtime Route 삭제를 중단한다.

Management Console Route의 Service와 host를 조회한다.

```bash
oc get route bamoe-management-console \
  -n "$RUNTIME_NS" \
  --ignore-not-found \
  -o custom-columns='NAME:.metadata.name,SERVICE:.spec.to.name,HOST:.spec.host'
```

`SERVICE=bamoe-management-console`일 때만 정확한 Route 하나를 삭제한다. 조회와
삭제를 분리하지 않고 ownership과 target Service를 같은 조건문에서 다시 검증한다.

```bash
runtime_route_service="$(
  oc get route bamoe-management-console \
    -n "$RUNTIME_NS" \
    --ignore-not-found \
    -o jsonpath='{.spec.to.name}'
)"

if [ "$(
  oc get namespace "$RUNTIME_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)" != 'bamoe-poc-guide' ]; then
  printf 'REFUSE: Runtime namespace ownership mismatch\n' >&2
elif [ -z "$runtime_route_service" ]; then
  printf 'ALREADY_ABSENT: route/bamoe-management-console\n'
elif [ "$runtime_route_service" = 'bamoe-management-console' ]; then
  oc delete route bamoe-management-console -n "$RUNTIME_NS"
else
  printf 'REFUSE: Management Console Route targets unexpected service %s\n' \
    "$runtime_route_service" \
    >&2
fi
```

삭제 결과를 확인한다.

```bash
oc get route bamoe-management-console \
  -n "$RUNTIME_NS" \
  --ignore-not-found \
  -o name
```

정상 관찰값은 빈 출력이다.

MCP Route도 생성된 적 없는지 확인한다.

```bash
oc get route bamoe-mcp-server \
  -n "$RUNTIME_NS" \
  --ignore-not-found \
  -o name
```

정상 관찰값은 빈 출력이다.

마지막으로 sandbox ownership을 확인한다.

```bash
test "$(
  oc get namespace "$SANDBOX_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}'
)" = 'bamoe-poc-guide'
```

남은 sandbox Route와 Canvas metadata를 조회한다.

```bash
oc get route \
  -n "$SANDBOX_NS" \
  -o json \
  | jq -r '
      .items[]
      | [
          .metadata.name,
          .spec.to.name,
          .spec.host,
          .metadata.labels["tools.kie.org/created-by"],
          .metadata.annotations["tools.kie.org/workspace-id"],
          .metadata.annotations["tools.kie.org/workspace-name"]
        ]
      | @tsv
    '
```

§13.6에서 기록한 이번 PoC workspace Route가 남아 있으면 임의로 Route만
삭제하지 않는다. 연결된 Deployment/Service까지 한 묶음으로 관리하는 Canvas UI로
돌아가 정확한 Dev Deployment 하나를 삭제한다. 다른 workspace 또는 소유자를
확정할 수 없는 Route는 보존한다.

§17.3과 §17.5에서는 본선·제품의 고정 Route만 삭제했으므로 제품 Pod와 내부
Service는 남는다. Dev 또는 Runtime Kustomize 묶음을 다시 적용하면 선언에 포함된
Route가 복원된다. 다시 외부 UI가 필요하면 인증과 접근제어를 검토한 뒤 §5 또는
§11의 dry-run부터 수행한다.

### 17.6 정리 Gate와 보존 범위

GitHub 자동 배포 flag를 조회한다.

```bash
gh variable get OCP_AUTO_DEPLOY --repo "${GITHUB_OWNER}/${GITHUB_REPO}"
```

GitHub OpenShift Secret 이름을 조회한다.

```bash
gh secret list --repo "${GITHUB_OWNER}/${GITHUB_REPO}" --env ocp-poc
```

본선 외부 Route를 조회한다.

```bash
oc get route -n "$APP_NS"
```

제품 UI Route를 조회한다.

```bash
oc get route -n "$DEV_NS"
```

```bash
oc get route -n "$RUNTIME_NS"
```

```bash
oc get route -n "$SANDBOX_NS"
```

보존된 내부 앱 상태를 확인한다.

```bash
oc get deployment,service -n "$APP_NS"
```

**Gate**

- `OCP_AUTO_DEPLOY=false`다.
- GitHub의 `OPENSHIFT_TOKEN`과 `OPENSHIFT_CA_DATA`가 없다.
- Actions/Canvas ServiceAccount와 RoleBinding이 없다.
- 이번 PoC의 외부 앱 Route와 제품 UI Route가 없다.
- 다른 Canvas workspace의 sandbox Route가 있었다면 삭제하지 않고 소유권을
  기록했다.
- 앱/Mock Deployment와 내부 Service는 보존됐다.
- 고객 실데이터와 token은 어디에도 공유되지 않았다.

Project, 제품 Deployment/Service, `ghcr-pull` Secret 전체 삭제는 많은 자원과
복구 가능성을 제거한다. PoC가 완전히 끝나고 보존할 자산이 없다는 별도 승인을
받은 뒤 새 정리 계획으로 진행한다. 이 가이드에서는 자동 삭제하지 않는다. 내부
앱을 보존하므로 GHCR pull에 필요한 `ghcr-pull` Secret과 그 read-only PAT도
보존한다.
전체 폐기 시에는 Pod/Deployment 삭제 순서를 먼저 정한 뒤 PAT를 GitHub에서
폐기하고 `ghcr-pull` Secret을 마지막에 삭제한다.

## 18. 최종 완료 체크리스트

### 18.1 고객 시연 준비 완료

아래 항목은 제품 UI와 Business Service Route가 열려 있는 **시연 준비 상태**를
확인한다. §17의 종료 정리를 마친 뒤에는 Route 항목이 더 이상 참이 아닌 것이
정상이다.

- [ ] §1: 실제 API server, Route domain, OCP version, worker architecture 확인
- [ ] §1: local `oc`가 cluster minor version과 일치
- [ ] §1: 현재 cluster의 API TLS가 `-k` 없이 검증됨
- [ ] §2: 네 Project ownership label과 namespace 권한 확인
- [ ] §3: worker의 Quay와 Red Hat UBI image pull 성공
- [ ] §4: 직접 배포 YAML, 여섯 제품 image와 Canvas JDK 21 지원 image 계약 검증
- [ ] §5: Dev 제품 4개 Ready, 외부 Route 3개와 Canvas backend 연결 정상
- [ ] §6: sibling private repository 생성, 상위 Git local exclude 적용, 고객 PDF와 Case 05 초안 제외
- [ ] §7: 첫 Actions build와 private GHCR pull 성공
- [ ] §8: 앱과 Mock의 commit SHA bootstrap 성공
- [ ] §9: health, OpenAPI Case 01~04, Case 04 exact journal 성공
- [ ] §10: 외부 Business Service Route가 `-k` 없이 성공
- [ ] §11.2~§11.3: Runtime 제품 2개 Ready와 Management Console Route 확인
- [ ] §11.4·§11.6: Management Console 사전 등록과 앱 CORS origin 확인
- [ ] §11.5: MCP Tech Preview의 내부 OpenAPI fetch/parse 확인
- [ ] §11.5: 인증 없는 MCP 외부 Route가 생성되지 않았음을 확인
- [ ] §12.2: GitHub Actions 최소 권한과 negative 권한 경계 확인
- [ ] §12.3·§12.7: cluster minor 변수를 저장하고 실제 workflow에서 호환 `oc` 설치를 확인
- [ ] §12.4: GitHub-hosted runner Route TLS preflight 성공
- [ ] §12.3~§12.6: GitHub Environment variable/Secret scope 확인
- [ ] §12.7: 같은 commit의 digest image 자동 배포 성공
- [ ] §13: Canvas sandbox 권한 경계와 사용자 정의 Spring Boot Deploy 시연 성공
- [ ] §14: 일상 변경에서 diff, Maven, run SHA, OCP image를 차례로 검증
- [ ] 전체: 합성 데이터만 사용하고 token/Secret을 출력·공유하지 않음
- [ ] §0.3: OCP 4.19 정식 지원 여부는 운영 전 별도 확인 대상으로 기록

### 18.2 선택: 시연 종료 정리 완료

이 목록은 PoC 시연을 끝낼 때만 사용한다. 시연 준비 상태와 동시에 만족시킬
필요는 없다.

- [ ] §13·§17: Canvas Dev Deployment와 임시 token 정리
- [ ] §17.1: 자동 배포 중지와 GitHub OpenShift Secret 제거
- [ ] §17.2·§17.4: Actions/Canvas ServiceAccount와 RoleBinding 제거
- [ ] §17.3·§17.5: Business Service와 제품 UI 외부 Route 제거
- [ ] §17.6: 앱/Mock Deployment와 내부 Service 보존 확인
- [ ] 전체: Project나 제품 Deployment/Service를 광역 삭제하지 않음
