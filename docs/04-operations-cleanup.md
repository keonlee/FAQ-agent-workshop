# Phase 4 — 운영 팁 & 정리

## 4.1 관찰성

### Log Analytics KQL
```kql
// ACA 콘솔 로그
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "<name>"
| order by TimeGenerated desc
| take 100

// 시스템 로그 (스케일/재시작 이벤트)
ContainerAppSystemLogs_CL
| where ContainerAppName_s == "<name>"
| order by TimeGenerated desc
```

### Application Insights (선택, 권장)
1. AI 리소스를 추가로 프로비저닝
2. `APPLICATIONINSIGHTS_CONNECTION_STRING` 환경 변수 주입
3. `opencensus-ext-azure` 또는 OpenTelemetry로 trace 전송
4. Bot Service의 `developmentAppInsightKey` 속성에도 연결하면 turn 단위 추적

### Bot Framework 활동 로깅
간단한 미들웨어로 turn 입출력을 로그에 남길 수 있습니다.

## 4.2 운영 시 보강 항목

| 영역 | 입문 (현재) | 운영 권장 |
|---|---|---|
| 상태 저장 | 인메모리 + replicas=1 | Cosmos DB / Redis / Azure Table |
| 시크릿 | env var (`azd env --secret`) | Key Vault 참조 또는 Federated Identity |
| 도구 권한 | `approve_all` | 도구별 화이트리스트, 입력 검증 |
| 네트워크 | ACA 외부 ingress | Private endpoint + AFD/APIM |
| 스케일 | min=max=1 | min=1, max=N + 외부 상태 |
| 로깅 | print/logging | OpenTelemetry + AI 분산 추적 |
| KB | `faq.json` (정적) | Azure AI Search (RAG) + 인덱싱 파이프라인 |
| 모델 인증 | DefaultAzureCredential | UAMI + role 최소화 |

## 4.3 Track A 폴백

GitHub Copilot SDK가 컨테이너에서 동작하지 않거나 입문자에게 너무 복잡할 때 **GitHub Copilot SDK를 제거하고 Azure OpenAI를 직접 호출**하는 단순화된 경로입니다.

### 무엇을 바꾸나요?
- `src/copilot_brain.py`만 교체
- 다른 코드는 그대로 (Agents SDK, faq_tool, 매니페스트, Bicep 모두 동일)

### Track A 의사코드
```python
# src/copilot_brain.py (Track A)
from openai import AsyncAzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from src.faq_tool import search_faq

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(),
    "https://cognitiveservices.azure.com/.default"
)
client = AsyncAzureOpenAI(
    azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
    azure_ad_token_provider=token_provider,
    api_version="2024-10-21",
)

async def handle(user_text: str) -> str:
    # 1) 단순 RAG: 먼저 FAQ 검색
    hits = search_faq(user_text, top_n=3)
    context = "\n\n".join(f"[{h['id']}] Q: {h['q']}\nA: {h['a']}" for h in hits)

    # 2) 모델 호출
    completion = await client.chat.completions.create(
        model=os.environ["AZURE_OPENAI_CHAT_DEPLOYMENT_NAME"],
        messages=[
            {"role": "system", "content":
                "다음 FAQ를 근거로만 답변하세요. 근거 없으면 '찾을 수 없습니다'라고 답하세요.\n\n" + context},
            {"role": "user", "content": user_text},
        ],
        timeout=30,
    )
    return completion.choices[0].message.content
```

### Track A 결정 기준
- 컨테이너에서 GitHub Copilot SDK 인증 실패 (Phase 1.7)
- 응답 latency > 30초가 일관되게 발생
- 비동기 디버깅에서 입문자가 막힘

## 4.4 정리 (리소스 삭제)

### Azure 리소스
```powershell
azd down --purge
```
- `--purge`는 Soft-deleted 키볼트 등도 즉시 영구 삭제

### Entra 앱
```powershell
$appId = azd env get-value BOT_CLIENT_ID
az ad app delete --id $appId
```

### 사이드로드된 M365 앱
- Teams: Apps → Manage your apps → 우클릭 → Remove
- 또는 M365 관리 센터 → Integrated apps → 앱 선택 → Remove

### `.env` / 로컬 캐시
```powershell
Remove-Item .env
Remove-Item -Recurse -Force .azure  # azd 환경
```

## 4.5 다음 학습 (확장 아이디어)

- **Azure AI Search RAG**: `faq.json` 대신 인덱스 기반 의미 검색
- **다중 도구**: HR API, ITSM API 호출 도구 추가
- **Streaming 응답**: M365 Copilot에서 점진적 토큰 표시
- **Adaptive Cards**: 텍스트 대신 카드형 답변
- **상태 외부화**: Cosmos DB로 ConversationState/UserState 저장
- **CI/CD**: GitHub Actions + `azd pipeline config`

## 워크숍 종료
🎉 축하합니다! GitHub Copilot SDK로 Agent를 만들고 Azure에 배포한 뒤 Microsoft 365 Copilot에서 호출하는 전체 파이프라인을 완성했습니다.

피드백/이슈는 [GitHub Issues](https://github.com/keonlee/FAQ-agent-workshop/issues)로 부탁드립니다.
