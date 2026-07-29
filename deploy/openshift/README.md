# OpenShift 배포 파일 안내

실행 순서는 다음 두 문서를 따른다.

1. [배포 시작 가이드](../../OPENSHIFT-DEPLOYMENT-GUIDE.md)
2. [명령어 학습형 PAMOE 9.5 전체 PoC 가이드](FULL-POC-GUIDE.md)

이 README는 파일 역할만 요약한다. 명령을 여기에서 골라 실행하지 말고 전체
가이드에서 코드 블록을 하나씩 실행하고 Gate 순서를 따른다.

## 확정 구조

```text
private GitHub repository
  → GitHub Actions test/build
  → private GHCR image
  → bamoe-poc
       ├─ customer-rule-poc        Spring Boot Business Service
       └─ customer-rule-mock       Case 01~04 Mock API

bamoe-devtools
  └─ PAMOE Dev Environment         Canvas/Extended Services/CORS/Maven

bamoe-runtime
  └─ PAMOE Runtime Environment     Management Console/MCP Server

bamoe-sandbox
  └─ Canvas Dev Deployment         시연용 Spring Boot 사용자 정의 배포
```

- Offering은 PAMOE로 확정했다.
- BAMOE component image는 `quay.io/bamoe`에서 pull한다.
- 공개 Quay의 공식 PAMOE 9.5 component image 6개를
  `deploy/openshift/products/`의 Kustomize/YAML로 직접 배포한다.
- Canvas의 사용자 정의 Spring Boot 시연은 별도 지원 image
  `canvas-dev-deployment-base:9.5.0-ibm-0005-jdk21`을 `bamoe-sandbox`에서
  임시로 사용한다.
- 9.4 chart와 9.5 image를 섞지 않으며 제품 배포에 OCP 내부 Registry를 사용하지
  않는다.
- 사용자 앱과 mock image는 GitHub Actions가 GHCR에 만든다.
- 첫 배포 후 `main` push가 두 Deployment image를 digest로 자동 갱신한다.
- Canvas의 **Deploy** 버튼은 본선 Spring Boot 배포가 아닌 sandbox 시연용이다.
- Mock API에는 외부 Route를 만들지 않는다.
- 고객 원문 `BAMOE_POC_CASE.pdf`는 GitHub에 올리지 않는다.

## 파일 역할

| 파일 | 역할 |
|---|---|
| `ocp-env.sh` | API, Route domain, 네 Project, GitHub 이름 |
| `install-cluster-oc.sh` | cluster가 제공하는 동일 minor의 macOS `oc` 설치 |
| `base/application.yaml` | Business Service Deployment/Service/management Service |
| `base/mock.yaml` | Mock Deployment와 8091~8094 Service |
| `base/configmap.yaml` | Spring/OCP/health/CORS bootstrap 설정 |
| `overlays/pamoe/` | PAMOE product annotation과 직접 적용을 막는 image placeholder |
| `overlays/dmoe/` | DMOE 비교용 보존 자산; 이번 PAMOE PoC에서는 적용 금지 |
| `products/dev/` | Canvas, CORS Proxy, Extended Services, Maven Repository 직접 배포 |
| `products/runtime/` | Management Console과 내부 전용 MCP Server 직접 배포 |
| `../../config/settings-bamoe-openshift.xml` | Canvas 임시 Spring Boot build가 내부 Maven Repository를 사용하도록 설정 |
| `route.yaml` | Business Service의 선택적 HTTPS Route |
| `github-actions-rbac.yaml` | Actions가 두 Deployment image만 갱신하는 최소 권한 |
| `canvas-sandbox-rbac.yaml` | Canvas가 sandbox의 Deployment/Service/Route만 관리하는 최소 권한 |
| `canvas-sandbox-mock-alias.yaml` | sandbox에서 앱 Project의 Mock을 찾는 DNS alias |
| `build-internal-registry.yaml` | 내부 Registry용 보존 초안; 현재 본선에서는 사용하지 않음 |

## 배포 경로별 책임

| 변경 | 적용 경로 |
|---|---|
| Java/DMN/BPMN/Mock 코드 | `main` push → Actions 자동 배포 |
| Deployment/Service/ConfigMap/Route/RBAC | review + server dry-run + 수동 적용 |
| 외부 Route 인증서 사전검증 | 수동 `route-tls-preflight.yml` workflow |
| Canvas의 임시 모델 시험 | `bamoe-sandbox`의 Deploy 버튼 |
| 제품 image/config 변경 | manifest review + Kustomize render + server dry-run + 수동 `oc apply` |

GitHub Actions는 애플리케이션 image만 자동 갱신한다. 제품과 애플리케이션
manifest 변경은 자동 적용하지 않고 review와 server dry-run을 거친다. PAMOE
overlay의 `DO_NOT_APPLY_SET_IMMUTABLE_REF`는 안전 placeholder이므로 원본 overlay를
그대로 적용하지 않는다. 전체 가이드의 임시 작업 사본에서 승인된
`tag@sha256:digest` 또는 bootstrap SHA reference를 주입한 뒤에만 적용한다.
`overlays/dmoe/`는 offering별 annotation 비교를 위한 읽기 전용 참고이며 이
가이드의 어떤 적용 명령도 해당 경로를 사용하지 않는다.

## 자주 혼동하는 주소

OCP 앱에서 Mock 호출:

```text
http://customer-rule-mock:8091
http://customer-rule-mock:8092
http://customer-rule-mock:8093
http://customer-rule-mock:8094
```

Canvas sandbox에서는 같은 짧은 이름이
`customer-rule-mock.bamoe-poc.svc.cluster.local`을 가리키도록
`canvas-sandbox-mock-alias.yaml`을 적용한다.

로컬 `/etc/hosts` 설정은 Mac에서의 로컬 실행에만 영향을 주며 OpenShift Pod DNS를
설정하지 않는다.

## 보안 경계

- 앱 Route에는 현재 인증이 없으므로 합성 데이터만 사용한다.
- Mock API는 cluster 내부 Service로만 둔다.
- Management Console 연결 항목은 사전 구성할 수 있지만, 현재 앱에는
  persistence/Data Index/Process Management add-on이 없어 실제 process 관리
  기능은 후속 범위다.
- MCP Server는 Technology Preview다. 보안을 구성하지 않은 현재 PoC에서는 외부
  MCP Route를 만들지 않고 내부 Service만 사용한다.
- Maven Repository도 기본적으로 외부 Route를 만들지 않으며, 필요한 동안만
  `oc port-forward`로 확인한다.
- Canvas와 Management Console Route를 계속 공개하려면 OAuth proxy 또는 ingress
  IP 제한을 별도로 적용한다.
- Canvas에는 `bamoe-sandbox`의 전용 최소권한 Role을 가진 24시간
  ServiceAccount token만 넣는다.
- Actions에는 두 Deployment image patch만 가능한 별도 ServiceAccount를 사용한다.
- GHCR, Canvas GitHub, OpenShift token은 서로 분리한다.
- OCP 4.19와 BAMOE 9.5의 정식 운영 지원 여부는 SPCR에서 별도 확인한다.
