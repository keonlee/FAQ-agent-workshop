# 아키텍처

## 전체 구성

```
┌──────────────────────────────────────────────────────────┐
│                  Microsoft 365 Copilot UI                │
│           (사용자가 "FAQ Agent"를 선택하여 채팅)          │
└──────────────────────────┬───────────────────────────────┘
                           │ activity
                           ▼
            ┌──────────────────────────────┐
            │      Azure Bot Service       │
            │  (Teams 채널 + msaAppId)     │
            └──────────────┬───────────────┘
                           │ POST /api/messages
                           ▼
   ┌────────────────────────────────────────────────────┐
   │             Azure Container Apps                   │
   │  ┌──────────────────────────────────────────────┐  │
   │  │  Microsoft 365 Agents SDK (aiohttp host)     │  │
   │  │  - AgentApplication                          │  │
   │  │  - @AGENT_APP.activity("message")            │  │
   │  └──────────────┬───────────────────────────────┘  │
   │                 │ TurnContext                       │
   │                 ▼                                   │
   │  ┌──────────────────────────────────────────────┐  │
   │  │  GitHub Copilot SDK (CopilotClient)          │  │
   │  │  - session.register_tool(search_faq)         │  │
   │  │  - BYOM: Azure OpenAI (DefaultAzureCredential│  │
   │  │    토큰 기반 / Managed Identity)              │  │
   │  └──────────────┬───────────────────────────────┘  │
   │                 │ 도구 호출                         │
   │                 ▼                                   │
   │  ┌──────────────────────────────────────────────┐  │
   │  │  faq_tool.search_faq(query)                  │  │
   │  │  └─ faq.json (사내 FAQ KB)                    │  │
   │  └──────────────────────────────────────────────┘  │
   └────────────────────────────────────────────────────┘
                  │
                  ▼ (감사/관찰)
        Log Analytics  +  (선택) Application Insights
```

## 컴포넌트 책임 분리

| 계층 | 컴포넌트 | 책임 |
|---|---|---|
| **사용자 채널** | Microsoft 365 Copilot | 사용자 입력 수신 / 답변 표시 |
| **봇 게이트웨이** | Azure Bot Service | 채널 ↔ 메시징 엔드포인트 변환, 인증, 채널 관리 |
| **채널 어댑터** | Microsoft 365 Agents SDK | `/api/messages` HTTP 처리, TurnContext 변환, 활동 라우팅 |
| **추론 엔진** | GitHub Copilot SDK | LLM 호출, 도구 실행 루프, 권한 처리 |
| **모델** | Azure OpenAI (BYOM) | 자연어 이해/생성. Managed Identity 토큰 인증 |
| **지식 도구** | `faq_tool.search_faq` | 사내 FAQ 검색 (입문 단계: 키워드 매칭) |
| **저장소** | `faq.json` | 사내 FAQ 데이터. 운영은 외부 저장소로 교체 |

## 핵심 설계 결정

### 1) 왜 두 SDK를 함께 쓰나요?

**M365 Copilot에 노출하려면** Azure Bot Service를 거쳐야 합니다. Microsoft 365 Agents SDK가 Bot Service와의 채널 통합을 가장 적은 코드로 제공합니다.

**Agent의 두뇌**는 GitHub Copilot SDK가 도구 호출 루프를 제공하므로 그대로 사용합니다.

**즉, 두 SDK는 자연스러운 단일 스택이 아니라 Wrapper / Proxy 패턴입니다.**
- Agents SDK = 채널 어댑터 (입력/출력 변환)
- Copilot SDK = 내부 두뇌 (도구 호출 + 모델 추론)

이를 명확히 분리해서 구현하지 않으면 비동기·인증·세션 수명주기 문제가 발생합니다.

### 2) 왜 Custom Engine Agent인가요?

| 옵션 | 특징 |
|---|---|
| Declarative Agent | Microsoft가 오케스트레이션과 모델을 제공 (입문 쉬움). 단, **자체 추론/도구가 제한적** |
| **Custom Engine Agent** | 오케스트레이션·모델·도구를 100% 직접 제어 (이 워크숍 선택) |
| Copilot Connector | 데이터 수집/검색만, 대화 인터페이스는 별도 |

본 워크숍은 GitHub Copilot SDK로 직접 추론을 구성하므로 **Custom Engine Agent**가 정답입니다.

### 3) 왜 Azure Container Apps인가요?

- 컨테이너 기반: GitHub Copilot SDK의 런타임 의존성을 **Dockerfile에 명시**할 수 있어 환경 차이 최소화
- 서버리스 스케일: minReplicas=1 부터 시작
- Managed Identity 기본 지원: AOAI에 키 없이 토큰 기반 접근

> **상태 관리 주의:** ACA는 다중 replica로 스케일아웃됩니다. 입문 워크숍에서는 **min/max=1** 로 고정하여 인메모리 상태 일관성을 유지합니다. 운영 시 Cosmos DB / Redis 등으로 외부화 필요.

### 4) 왜 매니페스트 v1.21+ / `personal` 스코프인가요?

- `copilotAgents.customEngineAgents` 매니페스트 영역은 **manifestVersion ≥ 1.21**에서 지원
- Custom Engine Agent로 노출할 봇은 매니페스트 `bots[]`에 **`personal` 스코프 필수**
- `bots[].botId`와 `copilotAgents.customEngineAgents[].id`는 같은 **Entra App Client ID**여야 함

## 데이터 흐름 (turn 단위)

1. 사용자가 M365 Copilot에서 "연차는 며칠?" 입력
2. Copilot UI → Azure Bot Service → ACA `/api/messages`
3. Agents SDK가 Activity를 TurnContext로 변환 → `on_message` 핸들러 호출
4. 핸들러가 `copilot_brain.handle(turn_context.activity.text)` await
5. Copilot SDK가 새 session 생성 → AOAI에 프롬프트 + 도구 스키마 전달
6. 모델이 `search_faq` 도구 호출 결정 → SDK가 `search_faq("연차")` 실행
7. `faq.json`에서 매칭된 항목을 모델에 반환
8. 모델이 근거 기반 답변 생성
9. 핸들러가 `turn_context.send_activity(answer)`로 응답 전송
10. Bot Service → M365 Copilot UI 표시

## 관찰성

- **Log Analytics Workspace**: ACA 콘솔/시스템 로그 수집
- **(선택) Application Insights**: 분산 추적, 의존성 호출, custom event
- **Bot Framework 활동 로깅**: 미들웨어로 turn 단위 입출력 추적

## 보안 고려사항

| 영역 | 입문 단계 | 운영 권장 |
|---|---|---|
| AOAI 인증 | DefaultAzureCredential (개발자 로그인 + ACA Managed Identity) | Managed Identity + 최소 권한 RBAC |
| Bot 시크릿 | azd env --secret로 환경 변수 주입 | Key Vault 참조 또는 Federated Identity |
| 도구 권한 | `PermissionHandler.approve_all` (학습용) | 도구별 화이트리스트 / 파라미터 검증 |
| 네트워크 | ACA 외부 ingress | Private endpoint + AFD/APIM 게이트웨이 |
| 비밀 정보 노출 | `.env`는 `.gitignore` 처리 | git secret scanning + push protection |

## 트레이드오프 / 한계

- **GitHub Copilot SDK의 컨테이너 인증**: SDK 버전에 따라 Copilot CLI/토큰 의존성이 달라질 수 있음 → Phase 1.7에서 검증
- **인메모리 상태**: 멀티턴 대화는 한 replica 안에서만 일관성 보장
- **단순 키워드 매칭**: 동의어/의미 검색은 한계가 있음 → Azure AI Search RAG로 확장 (별도 학습)
- **API 키 BYOM**: 시크릿 관리가 필요 → Managed Identity로 대체 가능

자세한 폴백 전략은 [04-operations-cleanup.md](./04-operations-cleanup.md#track-a-폴백)를 참고하세요.
