# Phase 1 — 로컬 Agent 개발

> 이 단계에서는 GitHub Copilot SDK로 추론 엔진을 만들고, Microsoft 365 Agents SDK로 Bot 채널 어댑터를 씌워 로컬에서 동작 검증합니다.

## 1.1 프로젝트 의존성 설치

```powershell
# 워크숍 리포 루트에서
python -m venv .venv
.\.venv\Scripts\Activate.ps1

pip install --upgrade pip
pip install -r requirements.txt
```

`requirements.txt`에 포함된 핵심 패키지:
- `github-copilot-sdk` — 추론 엔진 (도구 호출 루프)
- `microsoft-agents-hosting-aiohttp` — `/api/messages` aiohttp 호스트
- `microsoft-agents-authentication-msal` — Bot Service JWT 검증
- `azure-identity` — DefaultAzureCredential 토큰 획득
- `python-dotenv` — `.env` 로드

## 1.2 환경 변수 (`.env`) 구성

`.env.sample`을 `.env`로 복사 후 값을 채웁니다.

```powershell
Copy-Item .env.sample .env
```

`.env` 핵심 항목:
```env
# 로컬 개발에서는 ANONYMOUS_ALLOWED=True로 시작 (Bot 인증 우회)
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__ANONYMOUS_ALLOWED=True

# Azure 배포 시 (Phase 2)에는 채워집니다 — 로컬은 비워둬도 됩니다
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID=
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET=
CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID=

# Azure OpenAI BYOM (Phase 0에서 배포한 값)
AZURE_OPENAI_ENDPOINT=https://<your-aoai>.openai.azure.com/
AZURE_OPENAI_CHAT_DEPLOYMENT_NAME=gpt-4o

PORT=3978
```

> ⚠️ `.env`는 절대 커밋하지 마세요. `.gitignore`에 포함되어 있습니다.

## 1.3 사내 FAQ 지식 베이스 (`src/faq.json`)

스타터 코드에 5개의 샘플 항목이 포함되어 있습니다. 본인 시나리오에 맞게 수정/확장하세요.

```json
[
  {
    "id": "vacation",
    "q": "연차 휴가 정책",
    "a": "연 15일 부여, 입사 1년 미만은 월 1일씩 가산. 연차는 분기별 사전 승인 필요.",
    "tags": ["휴가", "HR", "연차"]
  }
]
```

## 1.4 검색 도구 구현 (`src/faq_tool.py`)

스타터 코드에 키워드 매칭 기반 `search_faq(query, top_n=3)`이 구현되어 있습니다.

핵심 동작:
1. `faq.json` 로드
2. 질의어 토큰화
3. 각 FAQ 항목의 `q + a + tags`와 매칭 점수 계산
4. 상위 N개 dict 리스트 반환 (id/q/a/score)

**단위 테스트:**
```powershell
python -m src.faq_tool "연차 며칠"
# 출력: 매칭된 FAQ 항목 리스트
```

## 1.5 GitHub Copilot SDK 두뇌 (`src/copilot_brain.py`)

스타터 코드 핵심 규칙:
- **CopilotClient는 앱 시작 시 1회만 생성** (`get_brain()`이 싱글톤 반환)
- **세션은 매 요청마다 새로 생성**
- `session.register_tool(search_faq)` 등록
- BYOM = Azure OpenAI + DefaultAzureCredential 토큰
- **응답 타임아웃 30초**
- 핸들러 안에서 `asyncio.run()` 절대 금지

```python
# 사용 예 (다른 모듈에서)
from src.copilot_brain import handle
answer = await handle("연차 며칠?")
```

## 1.6 Microsoft 365 Agents SDK 호스팅 (`src/app.py`)

스타터 코드 구성:
- `AgentApplication` 데코레이터 패턴
- `@AGENT_APP.activity("message")` → `copilot_brain.handle(text)` 위임
- aiohttp `Application` + `/api/messages` 라우트
- `load_configuration_from_env()`로 `.env` 자동 로드

**로컬 실행:**
```powershell
python src/app.py
# Listening on http://localhost:3978
```

## 1.7 로컬 테스트 (권장 순서)

### Step 1 — 단위 테스트
```powershell
# search_faq() 단독 동작
python -m src.faq_tool "경비 정산"
```
✅ 매칭된 FAQ 항목 출력 확인.

### Step 2 — Copilot 두뇌 단독 호출
```powershell
python -c "import asyncio; from src.copilot_brain import handle; print(asyncio.run(handle('연차 며칠?')))"
```
✅ AOAI 호출 + 도구 호출 + 답변 텍스트 반환 확인.

> AOAI 인증 실패 시: `az login`으로 사용자 토큰 확보. ACA 배포 시에는 Managed Identity가 사용됩니다.

### Step 3 — `/api/messages` 검증 (Microsoft 365 Agents Playground)

```powershell
# 별도 터미널에서 앱 실행
python src/app.py

# Playground 설치/실행 (Node 환경)
npm install -g teamsapptester  # 또는 Microsoft 365 Agents Playground 사용
```

Playground에서:
1. Bot URL: `http://localhost:3978/api/messages`
2. 메시지 입력: "연차 며칠 받을 수 있어요?"
3. ✅ FAQ 근거 답변 수신 확인

### Step 4 (선택) — Bot Framework Emulator
- Open Bot → URL: `http://localhost:3978/api/messages`
- App ID/Secret 비워두기 (`ANONYMOUS_ALLOWED=True` 일 때)

### Step 5 (선택) — devtunnel + Azure Bot
M365 Copilot에서 로컬 디버깅하려면:
```powershell
devtunnel host -p 3978 --allow-anonymous
```
출력된 URL을 Phase 2에서 만든 Azure Bot의 messaging endpoint로 임시 설정 가능.

## 1.8 컨테이너 시작 검증 (중요)

> **검토 결과 반영:** GitHub Copilot SDK는 컨테이너 환경에서 인증/런타임 의존성이 다를 수 있습니다. **Phase 2에서 ACA 배포 전에 반드시 로컬에서 컨테이너 빌드 후 시작 검증**을 합니다.

```powershell
docker build -t faq-agent:dev .
docker run --rm -p 3978:3978 --env-file .env faq-agent:dev
```

별도 터미널에서:
```powershell
curl -X POST http://localhost:3978/api/messages -H "Content-Type: application/json" -d '{"type":"message","text":"연차 며칠?"}'
```

✅ 컨테이너 로그에 SDK 시작 + AOAI 호출 + 답변 생성이 보이면 통과.

❌ 실패 시:
- GitHub Copilot SDK가 컨테이너에서 토큰을 얻지 못하는지 확인
- BYOM-only 흐름인데 SDK가 Copilot CLI를 요구하면 → Track A 폴백 검토
- Track A: `copilot_brain.py`를 Azure OpenAI Python SDK 직접 호출로 교체 (`docs/04-operations-cleanup.md#track-a-폴백` 참고)

## 1.9 Phase 1 완료 기준

- [ ] `search_faq` 단위 테스트 통과
- [ ] `copilot_brain.handle` 단독 호출에서 AOAI 호출 + 도구 호출 동작
- [ ] Agents Playground에서 멀티턴 5회 무오류
- [ ] **Docker 빌드 + `docker run`으로 컨테이너 안에서 동작 확인**
- [ ] FAQ에 없는 질문은 "찾을 수 없음" 류 안전 응답

## 다음 단계
👉 [02-azure-deployment.md](./02-azure-deployment.md)로 이동하여 Azure에 배포합니다.
