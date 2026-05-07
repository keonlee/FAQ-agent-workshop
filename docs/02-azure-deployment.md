# Phase 2 — Azure 배포 (Bicep + azd)

> 이 단계에서는 Entra 앱을 사전 생성하고, Bicep으로 Azure 리소스를 정의한 뒤 `azd up` 한 번으로 배포합니다.

## 2.1 왜 Entra 앱을 먼저 만드나요?

Bicep 배포 스크립트로 Entra 앱을 만드는 것도 가능하지만 입문자에게는 복잡합니다 (Graph 권한, 비동기 idempotency, 시크릿 관리). 따라서 **Entra 앱을 먼저 수동 생성**하고, 그 ID/시크릿을 `azd` 환경 변수로 전달하는 방식이 가장 간단합니다.

## 2.2 Entra 앱 등록

`scripts/create-bot-app.ps1` 스크립트가 포함되어 있습니다:

```powershell
.\scripts\create-bot-app.ps1 -DisplayName "faq-agent-bot"
```

또는 수동:
```powershell
$appId = az ad app create --display-name "faq-agent-bot" --sign-in-audience AzureADMyOrg --query appId -o tsv
$secret = az ad app credential reset --id $appId --years 1 --query password -o tsv
$tenantId = az account show --query tenantId -o tsv

Write-Host "BOT_CLIENT_ID:     $appId"
Write-Host "BOT_CLIENT_SECRET: $secret"
Write-Host "BOT_TENANT_ID:     $tenantId"
```

> 🔐 시크릿은 1회만 표시되므로 즉시 안전한 곳(Key Vault 등)에 보관하세요.

## 2.3 Bicep 모듈 구성

`infra/` 디렉터리에 모듈이 준비되어 있습니다.

```
infra/
├─ main.bicep                  ← 진입점 (RG 스코프)
├─ main.parameters.json        ← 파라미터 기본값
└─ modules/
   ├─ container-registry.bicep
   ├─ log-analytics.bicep
   ├─ container-apps-env.bicep
   ├─ container-app.bicep      ← Managed Identity, 외부 ingress, 3978 포트
   ├─ bot-service.bicep        ← Microsoft.BotService + Teams 채널
   └─ role-assignment.bicep    ← Container App MI → AOAI 'Cognitive Services OpenAI User'
```

배포되는 리소스:
- **Azure Container Registry** — 컨테이너 이미지 저장
- **Log Analytics Workspace** — 콘솔 로그 수집
- **Container Apps Environment** — ACA 호스팅 환경
- **Container App** — Agent 워크로드 (User-Assigned MI)
- **Azure Bot Service** (kind=`azurebot`) — Bot ID = Entra App ID
- **Bot Teams Channel** — M365 Copilot 노출에 필수
- **Role Assignment** — Container App MI에 AOAI 권한 부여

## 2.4 azd 환경 설정

```powershell
azd auth login
azd env new faq-agent-dev

# 필수 환경 변수
azd env set AZURE_LOCATION "koreacentral"        # 또는 본인 리전
azd env set BOT_CLIENT_ID    "<위에서 받은 appId>"
azd env set BOT_TENANT_ID    "<tenantId>"
azd env set --secret BOT_CLIENT_SECRET "<password>"

# AOAI 정보
azd env set AZURE_OPENAI_ENDPOINT   "https://<your-aoai>.openai.azure.com/"
azd env set AZURE_OPENAI_DEPLOYMENT "gpt-4o"
azd env set AZURE_OPENAI_RESOURCE_ID "/subscriptions/.../Microsoft.CognitiveServices/accounts/<aoai>"

# 환경 확인
azd env get-values
```

## 2.5 배포

```powershell
azd up
```

`azd up`이 수행하는 작업:
1. Docker 이미지 빌드
2. ACR에 푸시
3. Bicep 배포 (모든 리소스 프로비저닝)
4. Container App에 환경 변수 / Managed Identity 설정
5. Bot Service messaging endpoint를 ACA FQDN으로 설정

배포 완료 시 출력 예시:
```
✓ Done: Deploying service api
   - Endpoint: https://faq-agent-xxxxx.koreacentral.azurecontainerapps.io/
```

## 2.6 messaging endpoint 자동/수동 확인

Bicep 모듈이 자동으로 endpoint를 설정하지만, ACA FQDN은 배포 후에 알 수 있으므로 다음 흐름으로 처리됩니다:

1. `azd provision`이 ACA를 먼저 만들고 FQDN 출력
2. `bot-service.bicep`이 그 값을 `endpoint` 속성으로 받아 Bot 리소스에 설정
3. Bot 리소스 콘솔에서 **Configuration → Messaging endpoint**에 `https://<aca-fqdn>/api/messages`가 보이는지 확인

만약 자동 설정이 누락되었다면 수동:
```powershell
$fqdn = az containerapp show -g <rg> -n <containerAppName> --query properties.configuration.ingress.fqdn -o tsv
az bot update -g <rg> -n <botName> --endpoint "https://$fqdn/api/messages"
```

## 2.7 배포 검증

### 2.7.1 ACA 컨테이너 로그
```powershell
az containerapp logs show -g <rg> -n <containerAppName> --follow --tail 50
```
또는 Log Analytics:
```kql
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "<name>"
| order by TimeGenerated desc
| take 100
```
✅ Agents SDK + Copilot SDK 시작 로그가 보여야 합니다.

### 2.7.2 AOAI 인증 확인
Container App이 Managed Identity로 AOAI 토큰을 받는지 로그에서 확인. 401/403이면 role assignment 누락.

수동 부여:
```powershell
$miPrincipalId = az containerapp show -g <rg> -n <containerAppName> --query identity.userAssignedIdentities -o tsv | <첫 번째 값의 principalId>
az role assignment create `
  --assignee $miPrincipalId `
  --role "Cognitive Services OpenAI User" `
  --scope <AZURE_OPENAI_RESOURCE_ID>
```

### 2.7.3 Bot Service "Test in Web Chat"
1. Azure Portal → Bot 리소스
2. **Test in Web Chat**
3. "연차 며칠?" 입력
4. ✅ FAQ 답변 수신 확인

> ⚠️ Web Chat 통과 = Bot 엔드포인트 동작 확인. **M365 Copilot 통합 보장은 아닙니다.** Phase 3에서 매니페스트로 통합 검증을 진행합니다.

## 2.8 트러블슈팅 빠른 참고

| 증상 | 점검 |
|---|---|
| 401 in Web Chat | Bot Service `msaAppId`와 Container App `CLIENTID` 환경 변수가 일치하는지 |
| AOAI 403 | Managed Identity의 RBAC, AOAI 리소스 ID가 정확한지 |
| Container App 시작 실패 | 이미지 태그, 포트(3978), `python src/app.py` 진입점 |
| 응답이 오지 않음 | Bot endpoint가 정확한 FQDN인지, ACA ingress가 외부인지 |
| 컨테이너에서 Copilot SDK 인증 실패 | Phase 1.7 단계에서 미리 검증되었어야 함. Track A 폴백 고려 |

상세 내용은 [troubleshooting.md](./troubleshooting.md) 참고.

## 2.9 Phase 2 완료 기준

- [ ] `azd up` 성공
- [ ] ACA `/api/messages`가 외부에서 접근 가능 (Bot Service가 호출)
- [ ] Bot Service Test in Web Chat에서 FAQ 답변 수신
- [ ] Log Analytics에서 turn 로그 확인
- [ ] Bot Service에 **Microsoft Teams 채널 활성화** 확인 (Bicep으로 자동)

## 다음 단계
👉 [03-m365-integration.md](./03-m365-integration.md)로 이동하여 M365 Copilot에 노출합니다.
