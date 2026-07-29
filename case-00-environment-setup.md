# Case 00 - `test` 독립 BAMOE 9.5 환경 준비

> **목표**
> `/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test` 자체를 환경 root이자 BAMOE Workflow + Decisions Spring Boot Maven Business Service root로 만든다.
>
> **독립 환경 원칙**
> 기존 `basic_handson`의 Compose, Maven settings, Maven cache, Colima profile을 사용하지 않는다. 필요한 환경 파일과 cache를 모두 `test/` 기준으로 새로 만든다.
>
> **성공하면**
> `test/`에서 DMN과 BPMN을 함께 실행할 수 있는 최초 Maven build가 성공하고 Swagger 화면을 열 수 있다. 같은 폴더의 가이드를 보면서 [Case 01](case-01-process-service-status-change.md)을 바로 시작한다.

[전체 실습 목차로 돌아가기](README.md)

## 1. 최종 경로와 구성

이번 실습의 기준 경로는 하나다.

```text
/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

핵심 실습 자산과 Accelerator가 생성하는 실행 파일은 다음 구조로 둔다.

```text
test/
├── README.md
├── case-00-environment-setup.md
├── case-01-process-service-status-change.md
├── case-02-service-name-change-authority.md
├── case-03-mms-origin-number-authority.md
├── case-04-csmaux004-005-fallback.md
├── case-05-csmaux006-007-composite.md
├── case-06-wireline-suspension.md
├── mock-server/
├── .bamoe/
├── .gitignore
├── .kie-sandbox/
├── .m2/
│   └── repository/
├── .vscode/
│   └── settings.json
├── config/
│   └── settings-bamoe-container.xml
├── compose.bamoe-dev.yaml
├── pom.xml
└── src/
    ├── main/
    │   ├── java/org/acme/
    │   │   ├── BamoeSpringBootApplication.java
    │   │   └── BamoeCorsConfig.java
    │   └── resources/
    │       ├── application.properties
    │       ├── dmn/
    │       └── bpmn/
    └── test/
        ├── java/
        └── resources/
            └── scesim/
```

경로별 역할:

| 구분 | 절대 경로 |
|---|---|
| 환경 및 Maven 프로젝트 root | `/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test` |
| Maven settings | `/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/config/settings-bamoe-container.xml` |
| Docker Compose | `/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/compose.bamoe-dev.yaml` |
| 전용 Maven cache | `/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/.m2/repository` |
| DMN | `/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/src/main/resources/dmn` |
| BPMN | `/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/src/main/resources/bpmn` |
| Case별 Mock | `/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/mock-server` |
| SCESIM | `/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/src/test/resources/scesim` |

§8의 일회성 Accelerator staging 작업을 제외하면, 모든 `mvn`, `docker compose`, `code .` 명령은 `test/`에서 실행한다. `basic_handson/`으로 이동하지 않는다.

이 문서는 macOS 기준이다. Windows나 Linux에서는 설치와 container runtime 명령이 다르므로 그대로 실행하지 않는다.

## 2. 최초 상태 확인

일반 Terminal에서 다음 명령을 실행한다. 이 단계는 설치 여부와 version만 확인하며 파일을 변경하지 않는다.

```bash
uname -m
sw_vers
java -version
javac -version
mvn -version
command -v brew colima docker code jq git rg
docker compose version
code --list-extensions --show-versions | rg -i 'ibm\.bamoe-developer-tools|redhat\.java|vscode-java-debug'
```

확인 기준:

| 항목 | 기준 |
|---|---|
| `java -version` | Java 21 |
| `javac -version` | Java 21 |
| `mvn -version` | Maven 3.9.11 이상, 실행 Java 21 |
| VS Code | `code` 명령 사용 가능 |
| BAMOE 확장 | `IBM.bamoe-developer-tools@9.5.0` |
| Java 확장 | `redhat.java`, `vscjava.vscode-java-debug` |
| Container 도구 | `colima`, `docker`, `docker compose` 사용 가능 |
| 기타 | `jq`, `git`, `rg` 사용 가능 |

이미 기준을 만족하는 도구는 다시 설치하지 않는다. 빠진 항목만 §3에서 준비한다.

## 3. 누락된 Mac 도구 최초 1회 설치

### 3.1 Homebrew

```bash
brew --version
```

Homebrew가 없다면 다음 명령으로 Xcode Command Line Tools 상태를 확인한다.

```bash
xcode-select -p
```

실패하면 Apple 설치 화면을 연다.

```bash
xcode-select --install
```

설치 완료 후 [Homebrew 공식 설치 안내](https://docs.brew.sh/Installation)를 따라 Homebrew를 설치하고 새 Terminal에서 `brew --version`을 다시 확인한다.

### 3.2 Java, Maven, VS Code, Colima와 Docker CLI

§2에서 누락되었거나 기준에 맞지 않는 도구만 설치한다.

```bash
brew install --cask temurin@21 visual-studio-code
brew install maven colima docker docker-compose docker-buildx jq git ripgrep
```

VS Code를 한 번 연 다음 다음 UI 명령을 실행한다.

1. `Cmd+Shift+P`
2. `Shell Command: Install 'code' command in PATH`
3. VS Code와 기존 Terminal을 닫는다.
4. 새 Terminal을 연다.
5. `code --version`을 확인한다.

설치 후 다음 명령을 확인한다.

```bash
docker compose version
```

정상적으로 version이 출력되면 다음 절로 이동한다.

```bash
docker buildx version
```

`docker: 'compose' is not a docker command` 또는
`docker: unknown command: docker buildx`와 같이 둘 중 하나라도 실패하면
Homebrew의 CLI plugin 경로를 Docker CLI에 등록한다.

1. Mac architecture에 맞는 경로를 고른다.

   | Mac | plugin 경로 |
   |---|---|
   | Apple Silicon (`uname -m` → `arm64`) | `/opt/homebrew/lib/docker/cli-plugins` |
   | Intel (`uname -m` → `x86_64`) | `/usr/local/lib/docker/cli-plugins` |

2. Docker 설정 폴더를 만들고 VS Code로 설정 파일을 연다.

   ```bash
   mkdir -p ~/.docker
   code ~/.docker/config.json
   ```

3. 파일이 비어 있거나 새 파일이면 Apple Silicon 기준으로 다음 전체를 저장한다. Intel Mac은 위 표의 Intel 경로로 바꾼다.

   ```json
   {
     "cliPluginsExtraDirs": [
       "/opt/homebrew/lib/docker/cli-plugins"
     ]
   }
   ```

4. 파일에 기존 property가 있으면 지우지 않는다. 최상위 JSON object에 `cliPluginsExtraDirs`를 추가하고, 같은 key가 이미 있으면 배열에 위 경로만 추가한다. JSON property 사이의 쉼표를 확인한다.
5. 저장한 파일과 Compose를 검증한다.

   ```bash
   jq empty ~/.docker/config.json
   docker compose version
   ```

`jq` 오류가 없고 Compose version이 출력되어야 한다. 계속 실패하면 모든 Terminal을 닫고 새 Terminal에서 다시 확인한다.

### 3.3 Git 사용자 정보

BAMOE Accelerator는 staging Git repository를 만들고 자동 commit을 수행하므로 Git 사용자 이름과 이메일이 필요하다. 먼저 현재 값을 확인한다.

```bash
git config --global --get user.name
git config --global --get user.email
```

두 값이 모두 출력되면 다음 절로 이동한다. 하나라도 비어 있으면 조직의 Git 정책에 맞는 **본인 이름과 이메일**을 정한 뒤 다음 형식으로 등록한다. 아래 `<본인 이름>`과 `<본인 이메일>`을 문자 그대로 입력하지 않는다.

```bash
git config --global user.name "<본인 이름>"
git config --global user.email "<본인 이메일>"
git config --global --get user.name
git config --global --get user.email
```

`--global` 설정은 이 Mac에서 새로 만드는 다른 Git repository에도 사용된다. 회사에서 정한 이름이나 이메일 형식이 있으면 그 값을 우선한다.

### 3.4 BAMOE 9.5와 Java 확장

VS Code에서 `Cmd+Shift+X`를 눌러 Extensions 화면을 열고 다음을 설치한다.

- IBM BAMOE Developer Tools
- Language Support for Java by Red Hat
- Debugger for Java

PoC 기준 version을 정확히 설치하려면 Terminal에서 다음을 실행한다.

```bash
code --install-extension IBM.bamoe-developer-tools@9.5.0
code --install-extension redhat.java
code --install-extension vscjava.vscode-java-debug
code --list-extensions --show-versions | rg -i 'ibm\.bamoe-developer-tools|redhat\.java|vscode-java-debug'
```

Extensions 화면에서 IBM BAMOE Developer Tools의 gear menu를 열고 이번 PoC 동안 자동 업데이트를 끈다.

### 3.5 Java 21을 login shell 기본값으로 설정

`java`, `javac`, Maven 실행 Java가 모두 21이면 이 절을 건너뛴다.

다르면 다음 파일을 연다.

```bash
code ~/.zprofile
```

기존 내용을 지우지 말고 다음 두 줄이 없을 때만 한 번 추가한다.

```zsh
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
export PATH="$JAVA_HOME/bin:$PATH"
```

저장 후 모든 Terminal을 닫고 새 Terminal에서 확인한다.

```bash
java -version
javac -version
mvn -version
```

세 출력이 모두 Java 21을 사용해야 한다.

## 4. `test/`를 VS Code 프로젝트 root로 열기

다음 명령으로 정확한 위치를 확인한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
pwd

for file in \
  README.md \
  case-00-environment-setup.md \
  case-01-process-service-status-change.md
do
  if test -f "$file"; then
    echo "[OK] $file"
  else
    echo "[MISSING] $file"
  fi
done
```

`pwd` 결과가 다음과 정확히 같아야 한다.

```text
/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

새 VS Code window로 이 폴더를 연다.

```bash
code -n /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
```

Explorer 최상단 폴더가 `test`인지 확인한다. 이후 UI에서 만드는 모든 파일은 이 Explorer 아래에 있어야 한다.

## 5. 독립 환경 파일을 UI로 새로 만들기

### 5.1 `.gitignore`

VS Code Explorer에서 root를 우클릭하고 `New File`로 `.gitignore`를 만든다. 다음을 저장한다.

```gitignore
.DS_Store
.m2/
target/
.vscode/settings.json
config/settings-bamoe-container.xml
*.swidtag
```

`.m2`에는 이 프로젝트가 새로 받는 Maven artifact가 쌓인다. 개인 절대 경로가 들어가는 Maven settings와 VS Code settings도 공유 Git에서는 제외한다.

### 5.2 전용 Maven settings

Explorer root를 우클릭하여 `config` 폴더를 만들고, 그 안에 `settings-bamoe-container.xml`을 만든다.

다음 전체를 저장한다.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0 https://maven.apache.org/xsd/settings-1.2.0.xsd">
  <localRepository>/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/.m2/repository</localRepository>

  <profiles>
    <profile>
      <id>ibm-bamoe-enterprise-maven-repository</id>
      <repositories>
        <repository>
          <id>ibm-bamoe-enterprise-maven-repository</id>
          <url>http://127.0.0.1:10099/</url>
          <releases>
            <enabled>true</enabled>
          </releases>
          <snapshots>
            <enabled>false</enabled>
          </snapshots>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>ibm-bamoe-enterprise-maven-repository</id>
          <url>http://127.0.0.1:10099/</url>
          <releases>
            <enabled>true</enabled>
          </releases>
          <snapshots>
            <enabled>false</enabled>
          </snapshots>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>

  <activeProfiles>
    <activeProfile>ibm-bamoe-enterprise-maven-repository</activeProfile>
  </activeProfiles>
</settings>
```

이 설정은 다음 두 가지를 기존 환경과 분리한다.

- BAMOE repository URL: `http://127.0.0.1:10099/`
- Maven local cache: `test/.m2/repository`

### 5.3 독립 Docker Compose

Explorer root에 `compose.bamoe-dev.yaml`을 만들고 다음 전체를 저장한다.

```yaml
name: bamoe-customer-rule-poc

services:
  maven-repository:
    image: quay.io/bamoe/maven-repository:9.5.0-ibm-0005
    platform: linux/amd64
    ports:
      - "127.0.0.1:10099:8080"
```

환경 준비 단계에서는 Maven Repository만 container로 실행한다. Canvas, PostgreSQL, Kafka는 만들지 않는다. Case별 Mock API는 각 실습에서 Python 표준 라이브러리로 만들며 Docker Compose service가 아니다.

### 5.4 정적 검증

VS Code Terminal이 `test/`에 있는지 확인하고 실행한다.

```bash
pwd

READY=true
for file in \
  config/settings-bamoe-container.xml \
  compose.bamoe-dev.yaml
do
  if test -f "$file"; then
    echo "[OK] $file"
  else
    echo "[MISSING] $file"
    READY=false
  fi
done

if test "$READY" = true; then
  xmllint --noout config/settings-bamoe-container.xml
  docker compose -f compose.bamoe-dev.yaml config --quiet
  rg -n \
    'localRepository|127\.0\.0\.1:10099|ibm-bamoe-enterprise-maven-repository' \
    config/settings-bamoe-container.xml
else
  echo "STOP: 환경 파일을 만든 뒤 정적 검증을 다시 실행하세요."
fi
```

`pwd`는 `.../prelim/test`여야 한다. `xmllint`와 Compose validation은 아무 오류 없이 끝나야 한다.

### 5.5 로컬과 OCP에서 공통으로 쓸 Mock hostname

BPMN의 REST Service Task에는 Case별로 다른 `127.0.0.1` 주소를 넣지 않고
`customer-rule-mock`이라는 공통 hostname을 사용한다.

- 로컬 Mac: `/etc/hosts`가 `customer-rule-mock`을 `127.0.0.1`로 해석한다.
- OCP: 같은 이름의 Kubernetes Service가 Mock Pod로 연결한다.
- Mac terminal에서 Mock을 직접 확인하는 `curl`은 계속 `127.0.0.1:<port>`를 쓴다.

먼저 기존 설정을 조회한다.

```bash
rg -n \
  '^[[:space:]]*127\.0\.0\.1[[:space:]]+.*customer-rule-mock([[:space:]]|$)' \
  /etc/hosts
```

정상이라면 다음과 같은 줄 하나가 보인다.

```text
127.0.0.1 customer-rule-mock
```

아무것도 출력되지 않을 때만 `/etc/hosts`를 연다.

```bash
sudo nano /etc/hosts
```

파일 끝에 다음 한 줄을 추가하고 저장한다. 이미 같은 hostname이 있으면 중복으로
추가하지 않는다.

```text
127.0.0.1 customer-rule-mock
```

변경한 경우에만 macOS DNS cache를 갱신한다.

```bash
sudo dscacheutil -flushcache
```

```bash
sudo killall -HUP mDNSResponder
```

마지막으로 실제 이름 해석을 검증한다.

```bash
python3 -c \
  'import socket; print(socket.gethostbyname("customer-rule-mock"))'
```

기대 출력:

```text
127.0.0.1
```

이 Gate를 통과하지 않으면 Case 01 이후 BPMN의 REST Task는 로컬 Mock에 연결되지
않는다. 반대로 BPMN URL을 `127.0.0.1`로 바꾸면 로컬에서는 우연히 동작해도 OCP
Pod 안에서는 실패하므로 URL을 바꾸는 방식으로 우회하지 않는다.

## 6. 독립 Colima profile 최초 생성

이번 프로젝트는 기존 `bamoe` profile 대신 `bamoe-rules` profile을 사용한다.

```bash
colima list
```

상태에 따라 다음처럼 처리한다.

| `bamoe-rules` 상태 | 조치 |
|---|---|
| 행이 없음 | 아래 생성 명령 실행 |
| `Running` | 생성하지 않고 §7로 이동 |
| `Stopped` | 생성하지 않고 §7에서 다시 시작 |
| `Broken` | 아래 복구 절차로 profile을 초기화한 뒤 생성 |

`Broken`이면 해당 profile의 VM과 container data를 더 이상 보존할 필요가 없는지 먼저 확인한다. 이 실습 전용 profile을 처음부터 다시 만드는 경우에만 다음을 실행하고 확인 prompt에 답한다.

```bash
colima delete bamoe-rules
colima list
```

이 명령은 `bamoe-rules` profile의 VM과 container 환경을 삭제한다. `default`, `bamoe`, `telco` 등 다른 profile에는 실행하지 않는다. 삭제 후 `bamoe-rules` 행이 없어야 한다.

Apple Silicon Mac에서 `bamoe-rules` 행이 없을 때 다음을 한 번 실행한다.

```bash
colima start bamoe-rules \
  --vm-type vz \
  --vz-rosetta \
  --mount-type virtiofs \
  --cpus 4 \
  --memory 8 \
  --disk 100
```

Intel Mac에서는 Rosetta option 없이 만든다.

```bash
colima start bamoe-rules \
  --cpus 4 \
  --memory 8 \
  --disk 100
```

이 profile의 Docker context 이름은 `colima-bamoe-rules`다.

## 7. 독립 Maven Repository 시작

### 7.1 Colima와 Docker context

```bash
colima start bamoe-rules
docker context use colima-bamoe-rules
docker context show
colima -p bamoe-rules status
docker info --format 'arch={{.Architecture}} cpus={{.NCPU}} memoryBytes={{.MemTotal}} os={{.OperatingSystem}}'
```

정상 기준:

- Docker context: `colima-bamoe-rules`
- Colima profile `bamoe-rules`: Running
- `docker info`: server 정보 출력

`colima status`만 실행하면 `default` profile을 확인한다. 항상 `colima -p bamoe-rules status`를 사용한다.

### 7.2 Repository container

프로젝트 root에서 실행한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test

docker compose -f compose.bamoe-dev.yaml up -d maven-repository
docker compose -f compose.bamoe-dev.yaml ps maven-repository

repository_ready=false

for attempt in {1..30}; do
  if curl -fs -o /dev/null http://127.0.0.1:10099/; then
    repository_ready=true
    break
  fi

  echo "WAIT: Maven Repository 시작 대기 ${attempt}/30"
  sleep 2
done

if test "$repository_ready" = true; then
  echo "Maven Repository HTTP 200"
else
  echo "STOP: 60초 안에 Maven Repository가 준비되지 않았습니다."
fi
```

Compose service가 `running`이고 마지막 출력이 다음과 같아야 한다.

```text
Maven Repository HTTP 200
```

이 container는 DMN 실행 서버가 아니라 Maven이 BAMOE JAR, POM, plugin을 받는 저장소다.

### 7.3 Maven settings 적용 확인

```bash
mvn \
  -s config/settings-bamoe-container.xml \
  help:effective-settings \
  | rg -n 'localRepository|ibm-bamoe-enterprise-maven-repository|127\.0\.0\.1:10099'
```

출력에 다음 값이 보여야 한다.

```text
/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/.m2/repository
ibm-bamoe-enterprise-maven-repository
http://127.0.0.1:10099/
```

## 8. 빈 staging 폴더에서 Decisions Accelerator 생성 후 lean Workflow 전환

`test/`에는 이미 Case 00~06, `README.md`, Compose와 Maven settings가 있다. IBM BAMOE Developer Tools의 Accelerator는 기존의 “other files”를 `src/main/resources/others` 등으로 이동할 수 있으므로 **현재 `test/`에 직접 적용하지 않는다.**

대신 빈 형제 폴더에서 Maven skeleton을 생성하고, 필요한 네 항목만 `test/`로 한 번 복사한다.

```text
prelim/
├── test/                         ← 최종 프로젝트 root
└── test-accelerator-staging/     ← 일회성 생성 공간
```

staging은 프로젝트 root나 공통 환경이 아니다. `basic_handson`의 파일도 사용하지 않는다.

### 8.1 최종 프로젝트의 중복 상태 확인

`test/` Terminal에서 다음을 실행한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test

for project_item in pom.xml .bamoe .kie-sandbox src; do
  if test -e "$project_item"; then
    echo "EXISTS: $project_item"
  else
    echo "EMPTY:  $project_item"
  fi
done
```

판정:

| 출력 | 조치 |
|---|---|
| 네 항목이 모두 `EMPTY` | §8.2부터 최초 생성 |
| 네 항목이 모두 `EXISTS`이고 Decisions Accelerator가 확인됨 | 다시 적용하거나 복사하지 않고 §8.5로 이동 |
| 일부만 `EXISTS` | 덮어쓰지 말고 중단하여 해당 파일의 출처를 먼저 확인 |

### 8.2 빈 staging 폴더 만들기

일반 Terminal에서 다음을 실행한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim

if test -e test-accelerator-staging; then
  echo "STOP: test-accelerator-staging이 이미 있습니다."
else
  mkdir test-accelerator-staging
  echo "READY: 빈 staging 폴더를 만들었습니다."
fi
```

`STOP`이 나오면 기존 폴더에 중요한 파일이 없는지 Finder나 VS Code에서 확인한다. 그대로 재사용하거나 자동으로 지우지 않는다. 폴더가 비어 있음을 확인한 경우에만 별도 VS Code window로 연다.

```bash
code -n /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test-accelerator-staging
```

이 window의 Explorer 최상단은 반드시 `test-accelerator-staging`이어야 한다.

### 8.3 VS Code UI로 Accelerator 적용

staging window에서 다음을 수행한다.

1. `Cmd+Shift+P`
2. `BAMOE Developer Tools: Apply Accelerator`
3. `Decisions (Spring Boot + Maven)` 선택
4. 대상 workspace가 `test-accelerator-staging`인지 확인
5. Git 초기화 prompt가 나오면 기본 선택으로 진행
6. 적용 완료 notification까지 기다림

Terminal에서 생성 결과를 확인한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test-accelerator-staging

for project_item in pom.xml .bamoe .kie-sandbox/accelerator.yaml src; do
  if test -e "$project_item"; then
    echo "OK:      $project_item"
  else
    echo "MISSING: $project_item"
  fi
done

sed -n '1,120p' .kie-sandbox/accelerator.yaml
```

네 항목이 모두 `OK`이고 Accelerator name이 `Decisions (Spring Boot + Maven)`인지 확인한다. `MISSING`이 있거나 다른 Accelerator를 선택했다면 최종 프로젝트에 복사하지 않는다.

이번 PoC는 BPMN을 사용하지만 짧은 동기식 straight-through process만 필요하다. BAMOE 9.5의 기본 Workflows Accelerator는 PostgreSQL/JDBC persistence, Data Index/Audit, Jobs, User Task 저장소, process 관리·보안 등 stateful 예제 구성을 폭넓게 포함한다. 현재 사례에 그 전체 구성을 넣지 않고, 가벼운 Decisions skeleton에 §8.6의 Workflow starter와 REST work item만 추가한다.

이 방식은 임의 버전을 섞는 것이 아니다. `bamoe-spring-boot-bom`이 관리하는 같은 9.5 계열 artifact로 실행 capability만 좁게 구성한다. 조직에서 반복 사용할 때는 검증된 최종 POM을 custom Accelerator로 만들어 수동 전환 단계를 없앤다.

### 8.4 Maven skeleton만 최종 프로젝트로 복사

다음 명령은 최종 `test/`에 네 항목이 하나라도 있으면 복사를 수행하지 않는다. 전체 block을 한 번에 실행한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim

if test -e test/pom.xml ||
   test -e test/.bamoe ||
   test -e test/.kie-sandbox ||
   test -e test/src; then
  echo "STOP: test에 Maven skeleton 항목이 이미 있습니다. 복사하지 않았습니다."
else
  if cp test-accelerator-staging/pom.xml test/ &&
     cp -R test-accelerator-staging/.bamoe test/ &&
     cp -R test-accelerator-staging/.kie-sandbox test/ &&
     cp -R test-accelerator-staging/src test/; then
    echo "DONE: Maven skeleton 네 항목을 test로 복사했습니다."
  else
    echo "STOP: 복사 중 오류가 발생했습니다. 재실행하지 말고 test의 부분 생성 항목을 확인하세요."
  fi
fi
```

`DONE`이 나와야 한다. `STOP`이면 덮어쓰기나 재실행을 하지 않고 메시지에 적힌 기존 또는 부분 생성 항목을 먼저 확인한다.

다음 항목은 staging에서 복사하지 않는다.

- `README.md`: 현재 6개 실습 가이드를 유지
- `.gitignore`: §5.1에서 만든 독립 환경 규칙을 유지
- `.git/`: staging의 Git history를 가져오지 않음

이제 staging VS Code window를 닫고, 원래 `test` window로 돌아간다.

### 8.5 병합 결과 확인

`test/` Terminal에서 실행한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test

pwd

for project_item in pom.xml .bamoe .kie-sandbox/accelerator.yaml src; do
  if test -e "$project_item"; then
    echo "OK:      $project_item"
  else
    echo "MISSING: $project_item"
  fi
done

head -1 README.md
rg -n '^\\.m2/|^target/|^\\.vscode/settings\\.json|^config/settings-bamoe-container\\.xml|^\\*\\.swidtag' .gitignore
sed -n '1,120p' .kie-sandbox/accelerator.yaml
rg -n 'version\.bamoe|version\.org\.springframework\.boot|maven\.compiler\.release' pom.xml
rg -n 'bamoe-spring-boot-bom|drools-decisions-spring-boot-starter|jbpm-with-drools-spring-boot-starter|kogito-rest-workitem|scenario-simulation|kogito-maven-plugin|spring-boot-maven-plugin' pom.xml
find src/test/java -type f -name 'TestScenarioJunitActivatorTest.java' -print

if rg -q '<artifactId>spring-boot-maven-plugin</artifactId>' pom.xml &&
   ! rg -q '<artifactId>quarkus-maven-plugin</artifactId>' pom.xml; then
  echo "FRAMEWORK: Spring Boot"
else
  echo "FRAMEWORK: WRONG OR UNKNOWN - 다음 단계로 이동하지 마세요."
fi
```

Decisions Accelerator 병합 직후 기준:

- README 첫 줄: `# BAMOE 9.5 고객 규칙 6종 UI 실습 가이드`
- `.gitignore`: `.m2/`, `target/`, `.vscode/settings.json`, `config/settings-bamoe-container.xml`, `*.swidtag`
- Accelerator name: `Decisions (Spring Boot + Maven)`
- Accelerator ref: `9.5.0-ibm-0005-decisions-spring-boot-maven`
- BAMOE: `9.5.0-ibm-0005`
- Spring Boot: `4.0.7`
- `bamoe-spring-boot-bom`
- `drools-decisions-spring-boot-starter`
- `kogito-scenario-simulation`
- `kogito-maven-plugin`
- `spring-boot-maven-plugin`
- framework 판별 결과: `FRAMEWORK: Spring Boot`

새 프로젝트라면 위 필수 항목이 모두 보여야 한다. 새로 만든 프로젝트와 이미
Decisions Accelerator에서 Workflow starter로 전환한 프로젝트 모두 파일을 지우거나
Accelerator를 다시 적용하지 않는다.

이 가이드가 기준으로 삼는 정확한
`9.5.0-ibm-0005-decisions-spring-boot-maven` Accelerator에는 일반적으로
`TestScenarioJunitActivatorTest.java`가 함께 생성된다. 다만 기존 프로젝트,
부분 병합 또는 다른 Accelerator 결과에서는 빠질 수 있으므로 이름만 가정하지 않고
반드시 확인한다. `find src/test/java ...`가 경로를 출력하면 기존 공용 activator를
그대로 사용한다. 아무것도 출력하지 않으면 아래 절차를 project당 한 번 수행한다.

1. VS Code Explorer에서 `src/test/java/testscenario` folder를 만든다.
2. 그 안에 `TestScenarioJunitActivatorTest.java`를 만든다.
3. 다음 내용을 붙여 넣고 저장한다.

   ```java
   package testscenario;

   import org.drools.scenariosimulation.backend.runner.TestScenarioActivator;

   @TestScenarioActivator
   public class TestScenarioJunitActivatorTest {
   }
   ```

4. 다음 Gate로 확인한다.

   ```bash
   ACTIVATOR_FILE="src/test/java/testscenario/TestScenarioJunitActivatorTest.java"

   if test -f "$ACTIVATOR_FILE" &&
      rg -q '@TestScenarioActivator' "$ACTIVATOR_FILE"; then
     echo "[OK] shared SCESIM activator"
   else
     echo "[MISSING/INVALID] shared SCESIM activator"
   fi
   ```

이 Java class는 Case마다 하나씩 만드는 파일이 아니라 이후 Case 01~06이 함께
사용하는 project 단위 진입점이다. 준비가 끝나면 §8.6으로 이동한다.

Accelerator가 `maven.compiler.release`를 17로 생성하더라도 Maven process는 Java 21로 실행한다. 의미가 다른 값이므로 compiler release를 임의로 바꾸지 않는다.

`Decisions (Quarkus + Maven)`이 보이거나 POM에 `quarkus-maven-plugin`이 있으면 잘못 생성한 것이다. 최종 프로젝트에 복사하기 전이라면 plugin을 수동으로 섞지 말고 §8의 staging부터 Spring Boot Accelerator로 다시 생성한다.

### 8.6 Decisions skeleton을 lean Workflow 기반으로 전환

새로 만든 Decisions 프로젝트와 이미 전환한 기존 프로젝트 모두 먼저 현재 starter를 확인한다. Accelerator를 다시 적용하거나 기존 업무 자산을 삭제하지 않는다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test

rg -n \
  'drools-decisions-spring-boot-starter|jbpm-with-drools-spring-boot-starter|kogito-rest-workitem' \
  pom.xml
```

판정:

| 현재 POM | 조치 |
|---|---|
| `jbpm-with-drools-spring-boot-starter`와 `kogito-rest-workitem`이 각각 한 번 보임 | 이미 전환됨. dependency를 다시 추가하지 않고 아래 Gate 실행 |
| `drools-decisions-spring-boot-starter`만 보임 | 아래 UI 절차로 lean Workflow 기반으로 전환 |
| 양쪽 starter가 모두 보임 | build하지 말고 Decisions starter를 제거하여 하나의 starter만 유지 |
| 아무것도 보이지 않음 | 다른 Accelerator일 수 있으므로 중단하고 POM 확인 |

기존 Decisions starter만 있는 경우 VS Code Explorer에서 `pom.xml`을 열고 다음 dependency를 찾는다.

```xml
<dependency>
  <groupId>org.drools</groupId>
  <artifactId>drools-decisions-spring-boot-starter</artifactId>
</dependency>
```

이를 다음 두 dependency로 교체한다.

```xml
<dependency>
  <groupId>org.jbpm</groupId>
  <artifactId>jbpm-with-drools-spring-boot-starter</artifactId>
</dependency>
<dependency>
  <groupId>org.kie.kogito</groupId>
  <artifactId>kogito-rest-workitem</artifactId>
</dependency>
```

개별 version은 추가하지 않는다. `bamoe-spring-boot-bom`이 호환 version을 관리한다.

Decisions Accelerator가 다음 dependency를 만들었다면 제거한다.

```xml
<dependency>
  <groupId>org.drools</groupId>
  <artifactId>drools-decisiontables</artifactId>
</dependency>
```

`drools-decisiontables`는 XLS/XLSX Drools decision table용이다. 이 실습의 DMN Decision Table에는 필요하지 않다. `kogito-scenario-simulation`, Maven plugin과 Spring Boot plugin은 유지한다.

저장 후 다음 Gate를 실행한다.

```bash
rg -n \
  'jbpm-with-drools-spring-boot-starter|kogito-rest-workitem' \
  pom.xml

READY=true

if rg -q 'drools-decisions-spring-boot-starter' pom.xml; then
  echo "STOP: 기존 Decisions starter가 남아 있습니다."
  READY=false
else
  echo "OK: Decisions-only starter 없음"
fi

if test "$(rg -c '<artifactId>jbpm-with-drools-spring-boot-starter</artifactId>' pom.xml)" -eq 1; then
  echo "OK: jbpm-with-drools-spring-boot-starter exactly once"
else
  echo "STOP: Workflow starter 누락 또는 중복"
  READY=false
fi

if test "$(rg -c '<artifactId>kogito-rest-workitem</artifactId>' pom.xml)" -eq 1; then
  echo "OK: kogito-rest-workitem exactly once"
else
  echo "STOP: kogito-rest-workitem 누락 또는 중복"
  READY=false
fi

EMPTY_MODELS="$(find src/main/resources src/test/resources \
  -type f \
  \( -name '*.dmn' -o -name '*.bpmn' -o -name '*.bpmn2' -o -name '*.scesim' \) \
  -size 0 \
  -print 2>/dev/null)"

if test -n "$EMPTY_MODELS"; then
  echo "STOP: 저장되지 않은 0 byte 모델이 있습니다."
  printf '%s\n' "$EMPTY_MODELS"
  READY=false
else
  echo "OK: 0 byte DMN/BPMN/SCESIM 없음"
fi

if test "$READY" = true; then
  mvn -s config/settings-bamoe-container.xml -U clean verify
else
  echo "STOP: POM과 모델 자산을 수정한 뒤 Gate를 다시 실행하세요."
fi
```

`STOP`이 출력되면 Maven을 실행하지 않는다. 0 byte 파일은 모델이 저장된 것이
아니므로 VS Code Explorer에서 해당 빈 placeholder만 제거하고, 올바른 전용
DMN/BPMN/Test Scenario Editor로 같은 이름의 자산을 다시 만든다. 이름이 비슷한
다른 파일을 자동 rename하거나 내용이 있는 모델을 삭제하지 않는다.

마지막이 `BUILD SUCCESS`여야 한다. 기존 DMN과 SCESIM은 `jbpm-with-drools-spring-boot-starter`에서도 계속 실행된다.

`.kie-sandbox/accelerator.yaml`에는 최초 생성에 사용한 Decisions Accelerator 정보가 남는 것이 정상이다. 이 파일을 Workflows로 가장하여 수정하지 않는다. 실제 실행 capability는 POM과 build 결과로 확인한다.

Workflow artifact를 10099 repository에서 받을 권한이 없으면 dependency 이름을 다른 artifact로 추측하지 않는다. BAMOE Workflow entitlement와 repository 제공 범위를 먼저 확인한다.

### 8.7 Maven project 이름

`pom.xml`에서 임시 좌표가 남아 있으면 다음처럼 변경한다.

```xml
<groupId>com.example.bamoe.poc</groupId>
<artifactId>customer-rule-poc</artifactId>
<version>1.0.0-SNAPSHOT</version>
```

그 밖의 BOM, dependency와 plugin version은 개별적으로 변경하지 않는다.

## 9. VS Code Maven settings 연결

Terminal Maven과 VS Code Java Language Server는 별도 process다. 현재 프로젝트의 Workspace Settings에 새 settings 파일을 연결한다.

1. `Cmd+Shift+P`
2. `Preferences: Open Workspace Settings (JSON)`
3. 기존 property를 지우지 않고 다음 key를 병합

```json
{
  "java.configuration.maven.userSettings": "/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test/config/settings-bamoe-container.xml"
}
```

4. 저장
5. `Cmd+Shift+P` → `Java: Reload Projects`
6. Java status가 Ready가 될 때까지 기다림

오류가 계속될 때만 `Java: Clean Java Language Server Workspace`를 실행한다.

## 10. 최초 build와 실행 Gate

### 10.1 자산 무결성과 독립 Maven cache 확인

첫 build 전에는 `test/.m2/repository`가 없거나 비어 있어도 정상이다. 다음 build가 이 위치에 artifact를 새로 받는다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test

EMPTY_MODELS="$(find src/main/resources src/test/resources \
  -type f \
  \( -name '*.dmn' -o -name '*.bpmn' -o -name '*.bpmn2' -o -name '*.scesim' \) \
  -size 0 \
  -print 2>/dev/null)"

if test -n "$EMPTY_MODELS"; then
  echo "STOP: 저장되지 않은 0 byte 모델이 있습니다."
  printf '%s\n' "$EMPTY_MODELS"
else
  echo "OK: 0 byte DMN/BPMN/SCESIM 없음"
  mvn \
    -s config/settings-bamoe-container.xml \
    -U \
    clean verify
fi
```

`STOP`이면 build는 실행되지 않는다. 해당 자산을 전용 UI Editor에서 저장한다.
특히 파일명 오타가 있는 0 byte SCESIM을 내용이 있는 정상 파일로 간주하지 않는다.
모든 모델이 `[OK]` 상태일 때만 같은 block 안에서 Maven이 실행된다.

처음에는 새 cache에 dependency를 받기 때문에 시간이 걸릴 수 있다. 마지막에 `BUILD SUCCESS`가 보여야 한다.

build 후 전용 cache가 생성됐는지 확인한다.

```bash
if test -d .m2/repository; then
  echo "[OK] project-local Maven repository"
else
  echo "[MISSING] .m2/repository"
fi

find .m2/repository/com/ibm/bamoe -maxdepth 2 -type d -print | head
```

### 10.2 Spring Boot와 Swagger

실행 전에 POM이 Spring Boot이고 Quarkus plugin이 없는지 확인한다.

```bash
if rg -q '<artifactId>spring-boot-maven-plugin</artifactId>' pom.xml &&
   ! rg -q '<artifactId>quarkus-maven-plugin</artifactId>' pom.xml; then
  echo "FRAMEWORK: Spring Boot"
else
  echo "FRAMEWORK: WRONG OR UNKNOWN - 실행하지 마세요."
fi
```

`FRAMEWORK: Spring Boot`가 정확히 출력될 때만 같은 project root에서 실행한다.

```bash
mvn \
  -s config/settings-bamoe-container.xml \
  spring-boot:run
```

서버 시작 로그가 나온 뒤 browser에서 다음 주소를 연다.

```text
http://localhost:8080/swagger-ui/index.html
```

OpenAPI 원문은 `http://localhost:8080/v3/api-docs`에서 확인할 수 있다.

Swagger 화면이 열리면 environment와 Maven skeleton이 준비된 것이다. 실행 Terminal에서 `Ctrl+C`로 종료한다.

### 10.3 DMN, BPMN, SCESIM과 Mock 폴더

정확한 `9.5.0-ibm-0005-decisions-spring-boot-maven` Accelerator에는 일반적으로
sample DMN이 없다. 다른 변형 Accelerator에서 sample DMN이 실제로 생성된 경우에도
baseline build 전에는 삭제하지 않는다. Build 성공 후 파일 이름과 내용을 확인하여
고객 Case 자산이 아닌 것이 확실한 sample만 VS Code Explorer에서 정리한다.

```text
src/main/resources/dmn
src/main/resources/bpmn
src/test/resources/scesim
mock-server
```

폴더가 없다면 VS Code Explorer에서 만든다.

1. `src/main/resources` 우클릭 → `New Folder` → `dmn`
2. `src/main/resources` 우클릭 → `New Folder` → `bpmn`
3. `src/test/resources` 우클릭 → `New Folder` → `scesim`
4. project root 우클릭 → `New Folder` → `mock-server`

확인:

```bash
for folder in \
  src/main/resources/dmn \
  src/main/resources/bpmn \
  src/test/resources/scesim \
  mock-server
do
  if test -d "$folder"; then
    echo "[OK] $folder"
  else
    echo "[MISSING] $folder"
  fi
done
```

Case 01부터 이 폴더들에 고객 규칙 DMN, BPMN, SCESIM과 Case별 Mock을 만든다.

### 10.4 staging 폴더 정리

`mvn clean verify`와 Swagger 확인까지 성공한 뒤에는 `test-accelerator-staging`이 더 이상 필요하지 않다. Finder에서 다음 폴더만 선택하여 휴지통으로 이동한다.

```text
/Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test-accelerator-staging
```

최종 프로젝트인 `test/`는 선택하지 않는다. 휴지통을 비우기 전에는 staging 폴더를 복구할 수 있다. 보관하고 싶다면 삭제하지 않아도 되지만, 이후 Accelerator를 다시 적용하거나 Maven project로 사용하지 않는다.

## 11. 매일 다시 시작하는 최소 순서

최초 설정을 마친 뒤에는 설치와 파일 생성을 반복하지 않는다. Mac 재부팅 후 다음만 실행한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test

java -version
javac -version
mvn -version

colima start bamoe-rules
docker context use colima-bamoe-rules
colima -p bamoe-rules status
docker context show

docker compose -f compose.bamoe-dev.yaml up -d maven-repository
docker compose -f compose.bamoe-dev.yaml ps maven-repository

repository_ready=false

for attempt in {1..30}; do
  if curl -fs -o /dev/null http://127.0.0.1:10099/; then
    repository_ready=true
    break
  fi

  echo "WAIT: Maven Repository 시작 대기 ${attempt}/30"
  sleep 2
done

if test "$repository_ready" = true; then
  echo "Maven Repository HTTP 200"
  code .
else
  echo "STOP: 60초 안에 Maven Repository가 준비되지 않았습니다."
fi
```

정상 기준은 Java 21, `colima-bamoe-rules`, Repository HTTP 200이다.

## 12. 하루 실습 종료

Spring Boot runtime이 실행 중이면 해당 Terminal에서 `Ctrl+C`를 누른다. CPU와 memory를 돌려받고 싶을 때만 다음을 실행한다.

```bash
cd /Users/jihunkeom/Desktop/projects/2026/SKT/skt_bamoe_party/prelim/test
docker compose -f compose.bamoe-dev.yaml stop maven-repository
colima -p bamoe-rules stop
```

다음 날에는 §3~§10을 반복하지 않고 [11. 매일 다시 시작하는 최소 순서](#11-매일-다시-시작하는-최소-순서)만 수행한다.

일반 종료나 문제 해결에 다음 명령을 사용하지 않는다.

```text
colima delete
docker image rm
docker compose down -v
```

이 명령은 VM, image 또는 volume을 삭제할 수 있다.

## 13. 자주 발생하는 문제

| 증상 | 우선 확인 |
|---|---|
| `code: command not found` | VS Code에서 `Shell Command: Install 'code' command in PATH`, 새 Terminal |
| `mvn -version`만 Java 21이 아님 | `~/.zprofile`, 중복 Java 설정, 새 login shell |
| Docker daemon 연결 실패 | `colima start bamoe-rules`, `docker context use colima-bamoe-rules` |
| `colima status` 실패 | `colima -p bamoe-rules status`로 named profile 확인 |
| Port 10099 충돌 | 다른 process 또는 Compose가 10099를 사용 중인지 확인 |
| Repository HTTP 200 실패 | `docker compose ... ps`, container log, Docker context |
| `com.ibm.bamoe` artifact를 찾지 못함 | HTTP 200, Maven `-s config/...`, effective settings |
| Artifact가 `~/.m2`에 쌓임 | `settings-bamoe-container.xml`의 `localRepository`, 실제 `-s` option 확인 |
| VS Code Java import 오류 | Workspace Maven settings 저장 후 `Java: Reload Projects` |
| `.dmn`이 XML로 열림 | `Reopen Editor With...` → `Modern BAMOE DMN Editor` |
| Accelerator 명령이 없음 | BAMOE Developer Tools 9.5.0 설치와 활성화 |
| Accelerator 적용 후 rollback | `git config --global --get user.name`, `git config --global --get user.email` |
| `No plugin found for prefix 'spring-boot'` | 잘못 선택한 Quarkus Accelerator인지 `.kie-sandbox/accelerator.yaml`과 `pom.xml`을 확인 |
| BPMN palette에 REST Service Call Task가 없음 | `jbpm-with-drools-spring-boot-starter`, `kogito-rest-workitem`, Maven reload, editor 재열기 확인 |
| Port 8080 충돌 | 기존 Spring Boot runtime을 해당 Terminal에서 `Ctrl+C`로 종료 |

환경 Gate가 통과했는데 `mvn verify`가 DMN Decision Table이나 FEEL 오류를 가리키면 Colima나 Repository 문제가 아니라 모델 문제다. VM, image, `.m2`를 삭제하지 말고 VS Code Problems와 첫 Maven model validation 오류를 확인한다.

관련 로컬 가이드:

- [Mac 최초 도구 설치 참고](../htmls/labs/core/index.html#s00)
- [환경과 Maven Repository 개념](../htmls/labs/core/setup.html#s1)
- [Spring Boot Accelerator UI](../htmls/labs/core/decision-basics.html#s5)
- [BPMN Workflow 모델링](../htmls/labs/core/workflow-modeling.html)

## 14. Case 01 진입 체크리스트

- [ ] 현재 VS Code Explorer root가 `test`다.
- [ ] Java, javac, Maven 실행 Java가 모두 21이다.
- [ ] Maven이 3.9.11 이상이다.
- [ ] BAMOE Developer Tools가 9.5.0이다.
- [ ] Red Hat Java와 Java Debug 확장이 설치되어 있다.
- [ ] Git `user.name`과 `user.email`이 실제 본인 값으로 설정돼 있다.
- [ ] `config/settings-bamoe-container.xml`을 새로 만들었다.
- [ ] `compose.bamoe-dev.yaml`을 새로 만들었다.
- [ ] Maven local repository가 `test/.m2/repository`다.
- [ ] `bamoe-rules` Colima profile이 Running이다.
- [ ] Docker context가 `colima-bamoe-rules`다.
- [ ] 독립 Maven Repository가 `127.0.0.1:10099`에서 HTTP 200이다.
- [ ] **신규 skeleton 경로라면** 빈 `test-accelerator-staging`에 Decisions Spring Boot Accelerator를 한 번 적용했다.
- [ ] **신규 skeleton 경로라면** staging에서 `pom.xml`, `.bamoe`, `.kie-sandbox`, `src`만 `test`로 복사했고 기존 `README.md`, Case 문서와 환경 파일을 보존했다.
- [ ] **기존 lean 프로젝트 경로라면** staging 생성·복사를 생략하고 §8.5의 호환성 Gate로 현재 POM과 Accelerator 출처를 확인했다.
- [ ] 선택한 경로에 맞춰 파일을 삭제하지 않고 §8.6의 lean Workflow Gate를 통과했다.
- [ ] `pom.xml`의 artifactId가 `customer-rule-poc`다.
- [ ] POM runtime 판별 결과가 `FRAMEWORK: Spring Boot`다.
- [ ] POM에 `jbpm-with-drools-spring-boot-starter`와 `kogito-rest-workitem`이 있다.
- [ ] `kogito-rest-workitem`은 POM에 정확히 한 번만 있다.
- [ ] POM에 기존 `drools-decisions-spring-boot-starter`가 중복으로 남아 있지 않다.
- [ ] VS Code Workspace Maven settings가 `test/config` 파일을 가리킨다.
- [ ] `mvn -s config/settings-bamoe-container.xml clean verify`가 `BUILD SUCCESS`다.
- [ ] Swagger 화면을 열었다.
- [ ] Spring Boot runtime을 `Ctrl+C`로 정상 종료했다.
- [ ] `src/main/resources/dmn`, `src/main/resources/bpmn`, `src/test/resources/scesim`, `mock-server`가 준비됐다.

모두 완료했으면 다음 문서로 이동한다.

**다음: [Case 01 - 서비스 상태 변경 권한 판정](case-01-process-service-status-change.md)**

## 15. 공식 참고 자료

- [IBM BAMOE 9.5 Development Environment](https://www.ibm.com/docs/en/ibamoe/9.5.0?topic=installing-dev-environment)
- [IBM BAMOE 9.5 Development environment comparison](https://www.ibm.com/docs/en/ibamoe/9.5.0?topic=80x-dev-environment-comparison)
- [IBM BAMOE 9.5 Known limitations and Accelerator versions](https://www.ibm.com/docs/en/ibamoe/9.5.0?topic=notes-known-limitations)
- [BAMOE 9.5 Decisions Spring Boot Accelerator POM](https://github.com/IBM/bamoe-canvas-quarkus-accelerator/blob/9.5.0-ibm-0005-decisions-spring-boot-maven/pom.xml)
- [BAMOE 9.5 Workflows Spring Boot Accelerator POM](https://github.com/IBM/bamoe-canvas-quarkus-accelerator/blob/9.5.0-ibm-0005-workflows-spring-boot-maven/pom.xml)
- [IBM BAMOE 9.5 Workflow Services with Spring Boot](https://www.ibm.com/docs/en/ibamoe/9.5.0?topic=workflows-workflow-services-spring-boot)
- [IBM BAMOE Developer Tools - VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=IBM.bamoe-developer-tools)
