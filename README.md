# BAMOE Customer Rule PoC

[jihunkeom/bamoe-customer-rule-poc](https://github.com/jihunkeom/bamoe-customer-rule-poc)는
IBM BAMOE 9.5로 고객 Rule Case01~04를 구현한 PoC입니다.

## 구현 방식

이번 구현은 모든 Fact가 호출 전에 완성되어 있다고 가정하는 DMN-only 방식이
아닙니다. 고객이 전달한 슈도 코드에는 조건에 따른 API·DB 조회와 후속 호출이
포함되어 있으므로 BPMN과 DMN을 함께 사용했습니다.

- BPMN: 외부 API·DB 호출 순서, 조건 분기, 후속 처리 제어
- DMN: BPMN이 수집한 Fact를 이용한 업무 정책 판단과 다음 Action 결정
- Mock API: 고객 연동 계약이 확정되기 전 API·DB 응답 대체

```text
요청
  → BPMN이 필요한 Fact 조회
  → DMN이 현재 Fact로 정책 평가
  → DMN의 nextAction에 따라 BPMN이 후속 API 호출 또는 종료
  → 최종 정책 결과 반환
```

`mockScenario`는 PoC에서 외부 시스템의 응답을 선택하기 위한 테스트 전용
필드입니다. 실제 연동 시에는 Mock API를 고객 API·DB 연동으로 교체합니다.

Case05~06은 현재 저장소와 배포 범위에 포함되지 않습니다.

## 구현 범위

| Case | 설명 | Process endpoint | 대표 결과 |
|---|---|---|---|
| 01 | 서비스 상태 변경 | `POST /Case01ServiceStatusChangeProcess` | `ALLOW / STATUS_CHANGE_ALLOWED` |
| 02 | 유선 서비스 명의변경 | `POST /Case02WirelineNameChangeProcess` | `ALLOW / NAME_CHANGE_ALLOWED` |
| 03 | MMS 발신 권한과 대체 처리 | `POST /Case03MmsSendProcess` | `ALLOW / ALTERNATIVE_PROCESSING_REQUIRED` |
| 04 | 1차 거절 시 대체 권한 확인 | `POST /Case04FallbackProcess` | `ALLOW / FALLBACK_AUTH_GRANTED` |

주요 디렉터리:

```text
src/main/resources/bpmn/   BPMN Process
src/main/resources/dmn/    DMN Decision
src/test/resources/scesim/ DMN Scenario Test
mock-server/                외부 연동 Mock API
deploy/openshift/           OpenShift 배포 manifest
```

## OpenShift 구성

| OCP Project | 역할 |
|---|---|
| `bamoe-devtools` | Canvas, Extended Services, CORS Proxy, Maven Repository |
| `bamoe-runtime` | Case01~04 Business Service, Management Console, MCP Server, Mock DNS alias |
| `mock-api` | Case01~04 Mock REST API |

접근 주소:

- Canvas: `https://bamoe-canvas.apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com`
- Business Service: `https://customer-rule-poc.apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com`
- Management Console: `https://bamoe-management-console.apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com`
- MCP Server: OCP 내부 `http://bamoe-mcp-server.bamoe-runtime.svc.cluster.local:8080/mcp`
- Mock API: OCP 내부 `customer-rule-mock.mock-api.svc.cluster.local:8091~8094`

Business Service는 `bamoe-runtime`의 `customer-rule-mock` DNS alias를 통해
`mock-api` Project의 Mock Service를 호출합니다. MCP와 Mock API에는 외부 Route를
만들지 않았습니다.

## 배포 이미지

현재 OCP에 배포된 PoC 애플리케이션:

```text
ghcr.io/jihunkeom/customer-rule-poc:sha-a20f8c9573a1f65ec7f19f8655ae9fa2b33e7016@sha256:3935984eb78508c2a454bee379c32b115a052b26a372c856e5fea7c9ff11ff19
```

현재 OCP에 배포된 Mock API:

```text
ghcr.io/jihunkeom/customer-rule-mock:sha-a20f8c9573a1f65ec7f19f8655ae9fa2b33e7016@sha256:710b706cfff255feca98b5847e89cff6448e27a713099398c5205b3282496014
```

BAMOE 제품 이미지:

| 구성요소 | 이미지 |
|---|---|
| Canvas | `quay.io/bamoe/canvas:9.5.0-ibm-0005` |
| Extended Services | `quay.io/bamoe/extended-services:9.5.0-ibm-0005` |
| CORS Proxy | `quay.io/bamoe/cors-proxy:9.5.0-ibm-0005` |
| Maven Repository | `quay.io/bamoe/maven-repository:9.5.0-ibm-0005` |
| Management Console | `quay.io/bamoe/management-console:9.5.0-ibm-0005` |
| MCP Server | `quay.io/bamoe/mcp-server:9.5.0-ibm-0005` |

## Case01~04 호출 예시

공통 Business Service URL을 설정합니다.

```bash
export APP_BASE_URL='https://customer-rule-poc.apps.itz-ygi22x.infra01-lb.wdc07.techzone.ibm.com'
```

### Case01 — 서비스 상태 변경

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

기대 결과: `COMPLETED`, 평가 3회,
`ALLOW / STATUS_CHANGE_ALLOWED / CONTINUE`.

### Case02 — 유선 서비스 명의변경

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

기대 결과: `COMPLETED`, 평가 2회,
`ALLOW / NAME_CHANGE_ALLOWED / CONTINUE`.

### Case03 — MMS 발신 권한과 대체 처리

권한이 거절되고 발신번호가 대상이면 DMN이 대체 처리를 지시하고 BPMN이 후속
API를 호출합니다.

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

기대 결과: `COMPLETED`, `ALLOW / ALTERNATIVE_PROCESSING_REQUIRED`,
`alternativeExecuted=true`.

### Case04 — 1차 거절 시 대체 권한 확인

CSMAUX004가 거절된 경우에만 DMN 지시에 따라 CSMAUX005를 호출합니다.

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

기대 결과: `COMPLETED`, 평가 2회,
`ALLOW / FALLBACK_AUTH_GRANTED / CONTINUE`.

## 주요 Mock Scenario

| Case | `mockScenario` | 의미 |
|---|---|---|
| 01 | `happy`, `not-target`, `auth-denied`, `auth-body-error`, `promo-active` | 정상, 비대상, 권한 거절·오류, 프로모션 차단 |
| 02 | `target-granted`, `not-target`, `auth-denied`, `auth-body-error` | 대상 승인, 비대상, 권한 거절·오류 |
| 03 | `GRANTED`, `DENIED_NORMAL`, `DENIED_ALT_SUCCESS`, `AUTH_BODY_ERROR` | 권한 승인, 일반 처리, 대체 처리, 업무 오류 |
| 04 | `PRIMARY_GRANTED`, `PRIMARY_BODY_ERROR`, `FALLBACK_GRANTED`, `FALLBACK_DENIED`, `FALLBACK_BODY_ERROR` | 1차 종료 또는 2차 권한 분기 |

외부 연동의 기술 실패를 확인하는 `*-http-500` 또는 `*_HTTP_500` Scenario도
포함되어 있습니다. 기술 실패는 정상 `policyResult`가 아닌 Process 오류 경로를
검증합니다.

> 현재 외부 Route에는 별도 사용자 인증이 없습니다. 실제 고객정보 대신 합성
> 테스트 데이터만 사용해야 합니다.
