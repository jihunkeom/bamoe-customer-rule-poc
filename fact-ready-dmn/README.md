# Fact-Ready DMN-only 가이드

> **목표**
>
> DB 조회와 권한 API 호출은 기존 Java/Spring 서비스 또는 외부 Adapter가 수행하고,
> 모든 업무 fact가 준비된 뒤 BAMOE DMN Decision Service를 **한 번만** 호출한다.
>
> 이 폴더는 기존 `test/README.md`와 Case 00~06의
> Policy-Driven BPMN+DMN 가이드를 수정하거나 대체하지 않는다.

[두 버전 선택 가이드로 이동](../GUIDE-VERSIONS.md)

현재 `test` 프로젝트에서 이어서 실습한다면 먼저 기존
[Case 00 환경 설정](../case-00-environment-setup.md)을 완료한다. 그 환경은 두
버전이 함께 사용하며, 이 폴더에서는 기존 DMN/BPMN 자산을 건드리지 않고
`FactReady` 이름의 DMN과 SCESIM만 추가한다. BPMN 의존성이 없는 별도 프로젝트를
원하면 이 문서의 9절을 따른다.

## 1. 이 버전의 구조

```mermaid
flowchart LR
    C["기존 코드 / Adapter"] --> A["DB·외부 API 호출"]
    A --> N["응답 검증·fact 정규화"]
    N --> D["BAMOE DMN Decision Service 1회"]
    D --> R["최종 Result"]
    R --> X["기존 코드가 후속 처리"]
```

DMN은 HTTP나 DB를 호출하지 않는다. 다음 항목도 DMN 밖에 있다.

- URL, 인증, timeout, retry
- API 호출 순서와 병렬성
- 상태 변경 side effect
- idempotency와 보상 처리

DMN은 이미 준비된 fact를 받아 다음만 반환한다.

```text
status
reasonCode
reasonMessage
nextAction
사례별 추가 결과
```

이 버전에는 `NEEDS_EVIDENCE`나 `PolicyStep`이 없다. 한 번의 평가가 항상 최종
`Result`를 반환한다.

## 2. `NOT_CHECKED`의 의미

공통 `AuthResult`:

```feel
"GRANTED", "DENIED", "ERROR", "NOT_CHECKED"
```

여기서 `NOT_CHECKED`는 “나중에 BAMOE가 호출해야 한다”는 뜻이 아니다.

| 상태 | Fact-Ready DMN의 해석 |
|---|---|
| 규칙상 호출 대상이 아님 + `NOT_CHECKED` | 정상적인 최종 fact |
| 규칙상 호출 대상임 + `NOT_CHECKED` | 외부 fact 조립 실패이므로 `INVALID_INPUT` |
| HTTP 200 body의 legacy `ERROR` | DMN이 판정할 정규화된 업무/provider 결과 |
| HTTP 4xx·5xx, timeout, malformed JSON | DMN을 호출하지 않고 외부 코드의 기술 오류로 처리 |

`ERROR` 문자열로 transport 장애를 위조하지 않는다. 그래야 재시도 가능한 장애와
정상 평가된 업무 결과를 구분할 수 있다.

## 3. 기존 버전과 공존하는 자산 이름

기존 모델을 덮어쓰지 않도록 별도 이름과 namespace를 사용한다.

| Case | DMN 파일 | Model | Decision Service |
|---:|---|---|---|
| 01 | `Case01ServiceStatusChangeFactReady.dmn` | `Case01ServiceStatusChangeFactReady` | `Case01FactReadyService` |
| 02 | `Case02WirelineNameChangeFactReady.dmn` | `Case02WirelineNameChangeFactReady` | `Case02FactReadyService` |
| 03 | `Case03MmsSendAuthorityFactReady.dmn` | `Case03MmsSendAuthorityFactReady` | `Case03FactReadyService` |
| 04 | `Case04FallbackAuthorityFactReady.dmn` | `Case04FallbackAuthorityFactReady` | `Case04FactReadyService` |
| 05 | `Case05CompositeAuthorityFactReady.dmn` | `Case05CompositeAuthorityFactReady` | `Case05FactReadyService` |
| 06 | `Case06WirelineSuspensionFactReady.dmn` | `Case06WirelineSuspensionFactReady` | `Case06FactReadyService` |

DMN 위치:

```text
src/main/resources/dmn/
```

SCESIM 위치:

```text
src/test/resources/scesim/
```

기존 자산과 같은 폴더를 사용하되 모든 Fact-Ready 파일에 `FactReady`를 붙여
이름을 구분한다. 별도 하위 폴더를 만들지 않으므로 각 Case 문서의 UI 경로와
Maven classpath가 동일하다.

Namespace 규칙:

```text
https://example.com/bamoe/poc/fact-ready/case01/v1
...
https://example.com/bamoe/poc/fact-ready/case06/v1
```

같은 Spring Boot Business Service에 두 버전의 모델을 함께 두어 endpoint와 결과를
비교할 수 있다. Fact-Ready 모델 자체는 BPMN 자산이나 Workflow runtime에 의존하지
않는다.

## 4. 사례별 외부 fact 계약

| Case | 외부 코드가 DMN 전에 준비할 fact |
|---:|---|
| 01 | 서비스 상세 분류, 상태 변경 코드, ORDAUX227 결과 또는 비대상 표시, 필요한 경우 프로모션 건수 |
| 02 | 서비스 코드·유형 코드, ORDAU1520 결과 또는 비대상 표시 |
| 03 | CSMAUX004 결과, MMS 발신번호 |
| 04 | CSMAUX004 결과, fallback이 필요한 경우 CSMAUX005 결과 |
| 05 | CSMAUX006과 CSMAUX007 결과 모두 |
| 06 | ONLINE 입력, dummy 여부, 적용되는 102·164·103 최종 결과 |

Case 01·02·04·06의 외부 코드는 어떤 API가 적용 대상인지 판단하거나 필요한 fact를
안전한 방법으로 모두 수집해야 한다. 이 조건이 기존 코드에 이미 구현돼 있다면
Fact-Ready 방식이 자연스럽다. 새로 조건부 호출까지 BAMOE가 결정해야 한다면 기존
Policy-Driven BPMN+DMN 버전을 사용한다.

## 5. 공통 DMN UI 원칙

각 Case에서 다음 순서를 사용한다.

1. `src/main/resources/dmn`에 Case별 `FactReady.dmn` 파일을 만든다.
2. `Modern BAMOE DMN Editor`로 연다.
3. Model name과 namespace를 Case 문서대로 지정한다.
4. `Data Types`에서 enum과 구조체를 만든다.
5. `Request` Input Data와 helper Decision을 만든다.
6. 모든 Decision의 `Decision Output data type`을 명시한다.
7. 최종 `Result`는 구조화된 타입을 사용한다.
8. 사례별 Decision Service 하나에 `Result`만 Output Decision으로 넣는다.
9. HTTP 호출이나 Java 함수를 DMN Expression에 넣지 않는다.

“Decision의 output type”은 DRD의 Decision node에 지정한다. 출력이 하나뿐인
Decision Table은 Decision node와 표 내부 단일 Output column에 같은 type을
지정한다. 현재 실습에서 검증한 BAMOE `9.5.0-ibm-0005` 저장 형식과 맞추기 위한
기준이다. 일반 validator warning만 보고 한쪽 type을 지우지 말고 BAMOE build와
SCESIM 결과를 함께 확인한다. 여러 output column으로 구조화된 `Result`를 만드는
표는 각 열의 field type을 지정한다.

Decision Service 자체에 별도 output type을 지정하지 않는다. 유일한 Output
Decision인 `Result`의 타입으로 service 응답 타입이 정해진다.

## 6. 공통 최종 결과

`DecisionStatus`:

```feel
"ALLOW", "DENY", "SYSTEM_ERROR", "INVALID_INPUT"
```

최소 `Result` field:

| Field | Type | 의미 |
|---|---|---|
| `status` | `DecisionStatus` | 최종 업무 판정 |
| `reasonCode` | `string` | 테스트와 연계에서 사용하는 안정적인 코드 |
| `reasonMessage` | `string` | 사람이 읽는 설명 |
| `nextAction` | `string` 또는 사례별 `NextAction` | 외부 코드가 수행할 최종 업무 행동 |

`nextAction`은 이 버전에서 추가 fact를 요청하지 않는다.

```text
CONTINUE
STOP
RETURN_ERROR
FIX_INPUT
ALTERNATIVE_PROCESSING
EXECUTE_SUSPENSION
```

## 7. SCESIM

SCESIM은 외부 API를 호출하지 않고 완성된 fact 조합과 최종 판정을 검증한다.

- GIVEN: `Request`의 모든 조립 fact
- EXPECT: helper Decision과 최종 `Result`
- 문자열: `"GRANTED"`처럼 큰따옴표를 포함한 FEEL literal
- null: 빈칸이 아니라 `null`
- 공용 activator: 기존
  `src/test/java/testscenario/TestScenarioJunitActivatorTest.java` 하나

중점 시나리오:

1. 정상 허용
2. 정상 거절
3. HTTP 200 body `ERROR`
4. 필요한 fact가 `NOT_CHECKED` 또는 null
5. 비대상 API 결과가 잘못 주입된 모순 상태
6. 경계값과 원문 목록 회귀

SCESIM은 외부 API가 실제로 호출됐는지 검증하지 않는다. 외부 Adapter에는 별도의
JUnit/통합 테스트가 필요하다.

## 8. Build와 endpoint

현재 프로젝트에서 UI 자산을 모두 저장한 뒤:

```bash
cd "/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test"

mvn -s config/settings-bamoe-container.xml clean verify
mvn -s config/settings-bamoe-container.xml spring-boot:run
```

`clean verify`는 DMN compilation과 SCESIM을 검증하지만 Spring REST endpoint를
시작하거나 아래 HTTP 요청을 실행하지 않는다. `BUILD SUCCESS`는 필수 Gate이지
Decision Service E2E 완료 증거는 아니다. 서버를 시작한 뒤 OpenAPI와 Case별
Decision Service curl을 별도로 통과시킨다.

Case별 curl Terminal에서는 `set -o pipefail`을 먼저 적용한다. OpenAPI Gate는
해당 model의 endpoint가 정확히 네 개인지 검사하고, Decision Service 예제는
`status/reasonCode/reasonMessage/nextAction`과 사례별 추가 field를 exact
비교한다. `/dmnresult` 예제도 빈 최상위 `messages`, 하나 이상의 Decision 결과,
모든 `evaluationStatus = SUCCEEDED`와 최종 `Result`를 함께 검사한다. 따라서
HTTP 4xx·5xx뿐 아니라 잘못된 2xx 정책 결과나 DMN 평가 실패도 성공처럼 보이지
않는다.

다른 Terminal:

```bash
APP_READY=0
APP_READY_ATTEMPT=1

while [ "$APP_READY_ATTEMPT" -le 30 ]
do
  if curl -fsS \
      'http://127.0.0.1:8080/actuator/health' \
      2>/dev/null \
    | jq -e '.status == "UP"' >/dev/null
  then
    APP_READY=1
    break
  fi
  sleep 1
  APP_READY_ATTEMPT=$((APP_READY_ATTEMPT + 1))
done

if [ "$APP_READY" -eq 1 ]; then
  printf 'APP_READINESS_GATE=PASS\n'
else
  printf 'APP_READINESS_GATE=FAIL: BAMOE Terminal 로그를 확인하세요.\n' >&2
  false
fi
```

`PASS`일 때만 OpenAPI를 조회한다.

```bash
curl --fail-with-body -sS \
  'http://127.0.0.1:8080/v3/api-docs' \
  | jq -r '.paths | keys[] | select(contains("FactReady"))'
```

Case마다 OpenAPI에서 다음 네 종류를 확인한다.

| endpoint | 반환 목적 |
|---|---|
| `/{model}` | 전체 model context |
| `/{model}/dmnresult` | 전체 model 평가 상태와 message |
| `/{model}/{decisionService}` | 좁은 최종 `Result` |
| `/{model}/{decisionService}/dmnresult` | facade 범위 상세 진단 |

BAMOE 9.5 Business Rule Task 제약은 이 버전에 영향을 주지 않는다. BPMN에서
embedded 평가하지 않고 외부 코드가 Decision Service REST endpoint를 직접
호출하기 때문이다.

> 같은 Maven 프로젝트의 `clean verify`는 Fact-Ready 파일만이 아니라 체크인된
> 모든 DMN, BPMN, SCESIM을 함께 검증한다. 다른 Case 때문에 실패할 수 있으므로
> 먼저 [현재 체크인 자산 상태](../README.md#현재-체크인-자산-상태)를 확인하고,
> report의 model/scenario 이름으로 실패 자산을 구분한다.

## 9. 순수 DMN-only 프로젝트로 분리하는 선택

두 버전을 같은 프로젝트에서 비교할 필요가 없다면 Fact-Ready 모델만 별도 Spring
Boot Business Service에 둘 수 있다.

- `Decisions (Spring Boot + Maven)` Accelerator 사용
- `drools-decisions-spring-boot-starter` 유지
- 사용하지 않는 `drools-decisiontables` 제거
- BPMN과 `kogito-rest-workitem` 불필요
- 이 폴더의 DMN·SCESIM만 생성

운영에서 Decision Service를 독립 배포·버전 관리하려는 경우에는 이 구성이 더
단순하다. 반대로 두 접근을 한 화면에서 비교하는 PoC라면 현재 프로젝트에 별도
model name으로 공존시키는 편이 편하다.

## 10. 학습 순서

| 순서 | 문서 |
|---:|---|
| 1 | [Case 01 - 서비스 상태 변경](case-01-service-status-change-dmn-only.md) |
| 2 | [Case 02 - 별정서비스 명의변경](case-02-service-name-change-dmn-only.md) |
| 3 | [Case 03 - MMS 발신번호](case-03-mms-origin-number-dmn-only.md) |
| 4 | [Case 04 - fallback 권한](case-04-fallback-authority-dmn-only.md) |
| 5 | [Case 05 - 복합 AND 권한](case-05-composite-authority-dmn-only.md) |
| 6 | [Case 06 - ONLINE 유선 일시정지](case-06-wireline-suspension-dmn-only.md) |

## 11. 이 버전의 완료 기준

- [ ] 기존 orchestration DMN/BPMN 파일을 덮어쓰지 않았다.
- [ ] Fact-Ready 모델 6개가 별도 namespace로 존재한다.
- [ ] 각 모델은 `Result` Decision과 Decision Service facade 하나를 가진다.
- [ ] `NEEDS_EVIDENCE`나 evidence 요청용 `nextAction`이 없다.
- [ ] 적용 대상인데 `NOT_CHECKED`인 fact는 `INVALID_INPUT`이다.
- [ ] HTTP 기술 실패를 업무 `ERROR` fact로 변환하지 않는다.
- [ ] SCESIM이 최종 조합과 모순 상태를 검증한다.
- [ ] Decision Service endpoint를 외부 코드가 한 번 호출한다.
- [ ] 실제 side effect는 BAMOE DMN 밖에서 실행한다.
