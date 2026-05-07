# Phase 3 — Microsoft 365 Copilot 통합 (Custom Engine Agent)

> 이 단계에서는 매니페스트를 만들고 사이드로드하여 M365 Copilot에서 Agent를 호출합니다.

## 3.1 매니페스트 작성

`appPackage/manifest.template.json` 템플릿이 포함되어 있습니다.

핵심 필드 (검토 결과 반영):

```jsonc
{
  "$schema": "https://developer.microsoft.com/json-schemas/teams/v1.21/MicrosoftTeams.schema.json",
  "manifestVersion": "1.21",                    // ⚠️ 1.21 이상 필수
  "version": "1.0.0",
  "id": "<NEW_APP_GUID>",                        // 새 GUID (Bot ID와 별개)
  "developer": {
    "name": "Workshop",
    "websiteUrl": "https://github.com/keonlee/FAQ-agent-workshop",
    "privacyUrl": "https://github.com/keonlee/FAQ-agent-workshop/blob/main/README.md",
    "termsOfUseUrl": "https://github.com/keonlee/FAQ-agent-workshop/blob/main/LICENSE"
  },
  "name": { "short": "FAQ Agent", "full": "Internal FAQ Agent" },
  "description": {
    "short": "사내 FAQ 응답 에이전트",
    "full": "사내 FAQ 데이터를 근거로 답변하는 Custom Engine Agent입니다."
  },
  "icons": { "color": "color.png", "outline": "outline.png" },
  "accentColor": "#0078D4",
  "bots": [
    {
      "botId": "<BOT_CLIENT_ID>",                // Phase 2의 Entra App ID
      "scopes": ["personal"],                     // ⚠️ personal 필수
      "supportsCalling": false,
      "supportsVideo": false,
      "isNotificationOnly": false
    }
  ],
  "copilotAgents": {
    "customEngineAgents": [
      {
        "id": "<BOT_CLIENT_ID>",                  // ⚠️ bots[].botId와 동일해야 함
        "type": "bot"
      }
    ]
  },
  "validDomains": []
}
```

### 매니페스트 핵심 제약 (검토 결과)
1. `manifestVersion` ≥ **1.21** — Custom Engine Agent 노출 가능
2. `bots[].botId` == `copilotAgents.customEngineAgents[].id` (= Entra App Client ID)
3. `bots[].scopes`에 **`personal`** 포함 필수
4. `id`는 앱 자체의 GUID (Bot ID와는 다름) — 다음 명령으로 새 GUID 생성:
   ```powershell
   [guid]::NewGuid().ToString()
   ```

## 3.2 매니페스트 채우기 (스크립트 활용)

```powershell
# Phase 2의 Bot ID 가져오기
$botId = azd env get-value BOT_CLIENT_ID
$appGuid = [guid]::NewGuid().ToString()

# 템플릿 → 실제 매니페스트
(Get-Content appPackage/manifest.template.json) `
  -replace "<BOT_CLIENT_ID>", $botId `
  -replace "<NEW_APP_GUID>", $appGuid `
  | Set-Content appPackage/manifest.json
```

## 3.3 아이콘 준비

`appPackage/icons/README.md` 안내에 따라 다음 두 파일을 `appPackage/`에 배치:
- `color.png` — 192x192 컬러 아이콘
- `outline.png` — 32x32 단색 아이콘 (투명 배경)

> 워크숍 학습 목적이라면 임시 PNG로 충분합니다. 운영용은 디자인 가이드라인 준수 필요.

## 3.4 Bot Service Teams 채널 확인

Phase 2에서 Bicep으로 자동 활성화되었어야 합니다. 확인:
```powershell
az bot show -g <rg> -n <botName> --query "properties.configuredChannels" -o tsv
```
✅ `MsTeamsChannel`이 보이면 통과.

수동 활성화 (필요 시):
```powershell
az bot msteams create -g <rg> -n <botName>
```

> 💡 **별도의 "Microsoft 365 Copilot 채널" UI에 의존하지 마세요.** M365 Copilot 노출은 **Teams 채널 + 매니페스트의 `copilotAgents.customEngineAgents`** 조합으로 이루어집니다.

## 3.5 앱 패키징

```powershell
# 패키징 (zip)
$pkg = "appPackage/FAQ-Agent.zip"
if (Test-Path $pkg) { Remove-Item $pkg }
Compress-Archive -Path appPackage/manifest.json, appPackage/color.png, appPackage/outline.png -DestinationPath $pkg
```

또는 VS Code Microsoft 365 Agents Toolkit:
- 명령 팔레트 → **Teams: Zip Teams App Package**

## 3.6 사이드로드

### 옵션 A — 개인 빠른 테스트 (Teams 클라이언트)
1. Teams 데스크톱/웹 → 좌측 **Apps**
2. **Manage your apps** → **Upload an app** → **Upload a custom app**
3. `FAQ-Agent.zip` 선택
4. **Add for me** 또는 본인 사용자에게 추가

### 옵션 B — 테넌트 배포 (M365 관리 센터)
1. https://admin.microsoft.com → **Settings** → **Integrated apps**
2. **Upload custom apps**
3. zip 업로드 후 사용자/그룹 할당

> ⚠️ 옵션 B는 글로벌 관리자 권한 필요. 워크숍에서는 옵션 A를 권장합니다.

## 3.7 M365 Copilot에서 Agent 호출

1. https://m365.cloud.microsoft → **Copilot** 또는 https://copilot.cloud.microsoft 접속
2. 좌측 사이드바 → **Agents** (또는 채팅창에서 `+`)
3. **FAQ Agent** 선택 → 채팅 시작
4. 질문 입력: "연차 며칠 받을 수 있어?"

✅ FAQ KB에 근거한 답변 + 출처 표시(예: 매칭된 FAQ ID) 확인.

## 3.8 E2E 검증 체크리스트

- [ ] M365 Copilot UI에서 Agent가 표시됨
- [ ] FAQ 질문에 근거 기반 답변
- [ ] 멀티턴 5회 (replica 1 가정) 컨텍스트 유지
- [ ] FAQ에 없는 질문 → "찾을 수 없음" 안전 응답
- [ ] ACA 로그에서 turn 단위 입출력 추적 가능
- [ ] Bot Service "활동 로그"에서 채널이 `msteams` 인지 확인

## 3.9 일반적 통합 실패 패턴

| 증상 | 원인 / 해결 |
|---|---|
| Agent가 Copilot UI에 안 보임 | 매니페스트 `manifestVersion < 1.21` 또는 `customEngineAgents` 누락 |
| 사이드로드는 됐는데 채팅이 안 됨 | `bots[].scopes`에 `personal` 빠짐, 또는 botId 불일치 |
| 401/403 응답 | Container App `CLIENTID/SECRET/TENANTID` 환경 변수가 Bot Entra 앱과 일치하는지 |
| 응답이 늦거나 끊김 | ACA 인스턴스 콜드 스타트 + Copilot SDK 토큰 갱신 — 응답 타임아웃 30초로 설정 |
| 첫 응답만 되고 멀티턴 실패 | replica 2 이상으로 스케일된 경우 인메모리 상태 손실. min/max=1 확인 |

상세는 [troubleshooting.md](./troubleshooting.md).

## 다음 단계
👉 [04-operations-cleanup.md](./04-operations-cleanup.md)로 이동하여 운영 팁과 정리를 학습합니다.
