# 트러블슈팅

## 로컬 개발

### `pip install github-copilot-sdk` 실패
- Python 3.11+ 사용 중인지 확인 (`python --version`)
- 가상환경 활성화 후 재시도
- 패키지명/버전을 PyPI에서 확인. 일부 사전 릴리스의 경우 `--pre` 옵션 필요

### `import microsoft_agents.hosting.aiohttp` 실패
- 패키지 import는 underscore: `microsoft_agents` (점 아님)
- 마이그레이션 가이드: https://learn.microsoft.com/microsoft-365/agents-sdk/bf-migration-python

### 로컬에서 401 (Bot Framework Emulator)
- `.env`에 `CONNECTIONS__SERVICE_CONNECTION__SETTINGS__ANONYMOUS_ALLOWED=True` 설정
- Emulator 인증 필드는 비워두기

### `DefaultAzureCredential` 실패 (로컬)
```powershell
az login
az account set --subscription "<sub>"
```
VS Code Azure 확장으로 로그인하거나 환경 변수 `AZURE_CLIENT_ID`/`AZURE_TENANT_ID` 등 설정.

### `asyncio` 관련 에러
- aiohttp 핸들러 안에서 `asyncio.run()` 호출 금지
- `await` 누락 확인
- CopilotClient는 시작 시 1회만 생성

---

## 컨테이너 빌드/시작

### `docker build` 실패
- `.dockerignore`로 `.venv`, `.env`, `node_modules` 제외했는지 확인
- 멀티스테이지 빌드 시 `pip install` 단계가 캐시되도록 `requirements.txt`를 먼저 복사

### 컨테이너에서 GitHub Copilot SDK 인증 실패
원인 후보:
1. Copilot CLI/토큰 의존성 — SDK 버전 문서 확인
2. 외부 endpoint 접근 차단
3. BYOM 토큰 흐름이 컨테이너 환경에 맞지 않음

해결:
- BYOM-only로 사용한다면 SDK 옵션에서 GitHub-hosted 모델 의존을 제거
- ACA에 outbound 네트워크 필요 endpoint 허용
- **결정적 회피:** Track A 폴백 ([04-operations-cleanup.md](./04-operations-cleanup.md#track-a-폴백))

### 포트 3978 응답 없음
- Dockerfile `EXPOSE 3978` + `azure.yaml` ingress targetPort=3978 일치
- aiohttp가 `0.0.0.0` 에 바인딩됐는지 (`localhost` 만이면 외부 노출 안 됨)

---

## Azure 배포

### `azd up` 중 `BotService` 생성 실패
- `Microsoft.BotService` 공급자 등록 (`az provider register --namespace Microsoft.BotService`)
- `msaAppId`가 유효한 Entra App ID인지 (`az ad app show --id <id>`)
- Bot 이름 중복 (전역 고유) — 다른 이름 시도

### Container App "Image pull failed"
- ACR에 이미지가 푸시되었는지: `az acr repository list -n <acr>`
- Container App에 `AcrPull` 권한이 있는지 (Managed Identity)
- ACR 관리자 자격 증명을 비활성화하고 MI로 통일했다면 Bicep 모듈에서 `acrPull` role assignment 확인

### AOAI 호출이 401/403
- Container App User-Assigned MI의 principalId 확인
- AOAI 리소스에 `Cognitive Services OpenAI User` 역할 부여 확인:
  ```powershell
  az role assignment list --scope <aoai-resource-id> --query "[].{p:principalId,r:roleDefinitionName}" -o table
  ```
- 토큰 audience가 `https://cognitiveservices.azure.com/.default` 인지

### Web Chat에서 응답 없음
- Bot messaging endpoint URL이 정확한지 (`https://<fqdn>/api/messages`)
- ACA ingress가 `external=true` 인지
- Container App 로그에 incoming 요청이 보이는지

### `azd up`이 매번 새 RG 생성
- `azd env new` 중 `AZURE_LOCATION`만 다르거나 environment 이름 변경 여부 확인
- 기존 환경 사용: `azd env list` → `azd env select <name>`

---

## Microsoft 365 통합

### Agent가 Copilot UI에서 안 보임
1. **사용자에게 M365 Copilot 라이선스 부여** (가장 흔한 원인)
2. 매니페스트 `manifestVersion >= 1.21`
3. `copilotAgents.customEngineAgents` 블록 존재
4. `bots[].botId == customEngineAgents[].id`
5. `bots[].scopes`에 `personal` 포함
6. 사이드로드 후 5~10분 캐시 갱신 대기

### 사이드로드 시 "App is not approved by your administrator"
- Teams 관리 센터 → Teams 앱 → **Setup policies** → Upload custom apps = On
- 사용자에게 정책 적용 확인

### 사이드로드는 됐지만 채팅이 동작 안 함
- Bot Service에 **Microsoft Teams 채널** 활성화 확인
- Container App의 환경 변수 `CLIENTID/CLIENTSECRET/TENANTID`가 매니페스트의 `botId` (= Entra App)와 일치하는지

### Activity Log에 채널이 `webchat`만 보이고 `msteams`는 없음
- 사이드로드된 앱에서 실제 채팅을 보내야 `msteams` 채널이 보입니다
- M365 Copilot에서 시도한 후 다시 확인

### 멀티턴 대화에서 컨텍스트가 유실됨
- ACA replicas가 2 이상으로 스케일됐을 가능성 — 인메모리 상태 손실
- min/maxReplicas = 1 확인:
  ```powershell
  az containerapp show -g <rg> -n <name> --query properties.template.scale
  ```
- 운영 시 외부 상태 저장소 사용

---

## 매니페스트

### Teams Toolkit 검증 오류
- `id`(앱 GUID)가 유효한 GUID 인지
- `bots[].botId`가 등록된 Bot 리소스의 `msaAppId`인지
- 아이콘 파일 크기/포맷 (color 192x192, outline 32x32, PNG)

### 매니페스트 패키지에서 파일 누락
- `Compress-Archive` 시 매니페스트는 zip **루트**에 위치해야 함 (하위 폴더 X)

---

## 자주 묻는 질문

**Q. GitHub Copilot SDK 대신 다른 LLM을 쓸 수 있나요?**
A. 네. `copilot_brain.py`를 OpenAI/Anthropic SDK 직접 호출 또는 Semantic Kernel/LangChain으로 교체할 수 있습니다. Track A가 그 예시입니다.

**Q. 매니페스트의 `id`와 `botId`는 같은 값인가요?**
A. 다릅니다. `id`는 앱 자체의 새 GUID, `botId`는 Bot 리소스의 Entra App ID입니다.

**Q. Web Chat에서는 잘 되는데 M365 Copilot에서만 안 됩니다.**
A. 매니페스트 검증부터 시작하세요 (1.21+ / personal scope / botId 일치). 그리고 사용자가 Copilot 라이선스를 가지고 있는지 확인하세요.

**Q. 비용이 얼마나 들까요?**
A. Container Apps Consumption + Log Analytics + Bot Service Free + AOAI 사용량 기준입니다. 학습 후 `azd down --purge`로 즉시 정리하세요.
