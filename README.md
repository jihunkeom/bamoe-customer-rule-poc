# BAMOE Customer Rule PoC

IBM BAMOE 9.5로 고객 Rule Case01~04를 구현한 PoC입니다.

- BPMN: 외부 API 호출과 실행 순서 제어
- DMN: 수집한 데이터를 이용한 업무 정책 판단
- Mock API: 고객 연동 정보 확정 전 테스트 데이터 제공
- GitHub: BPMN, DMN, 테스트와 배포 파일의 기준 원본

Case05~06은 현재 저장소와 배포 범위에 포함되지 않습니다.

## 구현 범위

| Case | 설명 | Process endpoint | 대표 결과 |
|---|---|---|---|
| 01 | 서비스 상태 변경 | `POST /Case01ServiceStatusChangeProcess` | `ALLOW / STATUS_CHANGE_ALLOWED` |
| 02 | 유선 서비스 명의변경 | `POST /Case02WirelineNameChangeProcess` | `ALLOW / NAME_CHANGE_ALLOWED` |
| 03 | MMS 발신 권한과 대체 처리 | `POST /Case03MmsSendProcess` | `ALLOW / ALTERNATIVE_PROCESSING_REQUIRED` |
| 04 | 1차 거절 시 대체 권한 확인 | `POST /Case04FallbackProcess` | `ALLOW / FALLBACK_AUTH_GRANTED` |

```text
src/main/resources/bpmn/   BPMN Process
src/main/resources/dmn/    DMN Decision
src/test/resources/scesim/ DMN Scenario Test
mock-server/                외부 연동 Mock API
```

## OCP 구성

| OCP project | 배포 대상 |
|---|---|
| `bamoe-devtools` | Canvas, Extended Services, CORS Proxy, Maven Repository |
| `bamoe-runtime` | Case01~04 Business Service, Management Console, MCP Server |
| `mock-api` | Case01~04 Mock REST API |

배포 후 접근 주소:

- Canvas: `https://bamoe-canvas.apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com`
- Business Service: `https://customer-rule-poc.apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com`
- Management Console: `https://bamoe-management-console.apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com`
- MCP Server: OCP 내부 `bamoe-mcp-server.bamoe-runtime.svc.cluster.local:8080`
- Mock API: OCP 내부 `customer-rule-mock.mock-api.svc.cluster.local:8091~8094`

Business Service는 `bamoe-runtime`의 DNS alias를 통해 `mock-api`의 Mock
Service를 호출합니다. MCP와 Mock API에는 외부 Route를 만들지 않습니다.

## 호출 예시

```bash
export APP_BASE_URL='https://customer-rule-poc.apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com'
```

### Case01

서비스 분류, ORDAUX227 권한, 프로모션 가입 건수를 순차적으로 확인합니다.

```bash
curl --fail-with-body -sS \
  -X POST "${APP_BASE_URL}/Case01ServiceStatusChangeProcess" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{
    "requestId": "README-C01-001",
    "serviceManagementNumber": "SVC-1001",
    "serviceStatusChangeCode": "F1",
    "mockScenario": "happy"
  }' \
  | jq '.processResponse'
```

기대: `COMPLETED`, 평가 3회, `ALLOW / STATUS_CHANGE_ALLOWED / CONTINUE`.

### Case02

서비스 유형을 조회하고 대상인 경우에만 ORDAU1520 권한을 확인합니다.

```bash
curl --fail-with-body -sS \
  -X POST "${APP_BASE_URL}/Case02WirelineNameChangeProcess" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{
    "requestId": "README-C02-001",
    "serviceManagementNumber": "SVC-2001",
    "mockScenario": "target-granted"
  }' \
  | jq '.processResponse'
```

기대: `COMPLETED`, 평가 2회, `ALLOW / NAME_CHANGE_ALLOWED / CONTINUE`.

### Case03

권한이 거절되고 발신번호가 대상이면 DMN이 대체 처리 호출을 지시합니다.

```bash
curl --fail-with-body -sS \
  -X POST "${APP_BASE_URL}/Case03MmsSendProcess" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{
    "requestId": "README-C03-001",
    "mmsOriginNumber": "01012345678",
    "mockScenario": "DENIED_ALT_SUCCESS"
  }' \
  | jq '.processResponse'
```

기대: `COMPLETED`, `ALLOW / ALTERNATIVE_PROCESSING_REQUIRED`,
`alternativeExecuted=true`.

### Case04

CSMAUX004가 거절된 경우에만 DMN의 지시에 따라 CSMAUX005를 호출합니다.

```bash
curl --fail-with-body -sS \
  -X POST "${APP_BASE_URL}/Case04FallbackProcess" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{
    "requestId": "README-C04-001",
    "customerId": "C001",
    "mockScenario": "FALLBACK_GRANTED"
  }' \
  | jq '.processResponse'
```

기대: `COMPLETED`, 평가 2회, `ALLOW / FALLBACK_AUTH_GRANTED / CONTINUE`.

## 주요 Mock scenario

| Case | `mockScenario` | 의미 |
|---|---|---|
| 01 | `happy`, `not-target`, `auth-denied`, `auth-body-error`, `promo-active` | 정상, 비대상, 권한 거절·오류, 프로모션 차단 |
| 02 | `target-granted`, `not-target`, `auth-denied`, `auth-body-error` | 대상 승인, 비대상, 권한 거절·오류 |
| 03 | `GRANTED`, `DENIED_NORMAL`, `DENIED_ALT_SUCCESS`, `AUTH_BODY_ERROR` | 권한 승인, 일반 처리, 대체 처리, 업무 오류 |
| 04 | `PRIMARY_GRANTED`, `PRIMARY_BODY_ERROR`, `FALLBACK_GRANTED`, `FALLBACK_DENIED`, `FALLBACK_BODY_ERROR` | 1차 종료 또는 2차 권한 분기 |

외부 연동의 기술 실패를 확인하는 `*-http-500` 또는 `*_HTTP_500` scenario도
포함되어 있습니다. 기술 실패는 정상 `policyResult`가 아닌 Process 오류 경로를
검증합니다.

## 빌드 및 테스트

Java 21과 BAMOE Maven Repository가 준비된 상태에서 실행합니다.

```bash
mvn \
  -s config/settings-bamoe-ci.xml \
  -B -ntp clean verify
```

이 명령은 빌드와 SCESIM 테스트를 함께 실행합니다.

## CI/CD

`main` push 시 GitHub Actions가 다음 작업을 수행합니다.

1. Maven 및 SCESIM 검증
2. Business Service와 Mock 이미지 빌드
3. GHCR에 commit SHA 기반 이미지 게시
4. `OCP_AUTO_DEPLOY=true`이면 기존 OCP Deployment 이미지 갱신
5. Rollout과 Case04 smoke test 검증
6. 실패 시 이전 이미지로 롤백

```text
ghcr.io/jihunkeom/customer-rule-poc
ghcr.io/jihunkeom/customer-rule-mock
```

최초 OCP 리소스 생성과 인프라 매니페스트 변경은 수동으로 적용합니다. GitHub
Actions는 기존 앱과 Mock Deployment의 이미지 변경 권한만 가집니다.

## 협업 원칙

- Git 저장소가 모델과 배포 파일의 기준 원본입니다.
- Canvas에서 수정한 BPMN/DMN도 검토 후 Git에 반영합니다.
- 실행 중인 Runtime에서 모델을 역으로 가져오는 방식은 사용하지 않습니다.
- Mock API는 고객 연동 정보가 확정되면 실제 API로 교체합니다.
- Management Console의 장기 실행 이력 기능은 현재 비영속 PoC 구성에서 제한될 수 있습니다.

## 배포 확인

```bash
oc get deploy,pod,svc,route -n bamoe-devtools
oc get deploy,pod,svc,route -n bamoe-runtime
oc get deploy,pod,svc,route -n mock-api
```

```bash
curl --fail-with-body -sS \
  "${APP_BASE_URL}/v3/api-docs" \
  | jq '.paths | keys'
```
