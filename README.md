# FAQ Agent Workshop

> **GitHub Copilot SDK** 기반의 사내 FAQ 질의응답 Agent를 만들어 **Azure Container Apps**에 배포하고, **Microsoft 365 Copilot**에서 **Custom Engine Agent**로 호출하는 입문자 워크숍입니다.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
![Python](https://img.shields.io/badge/python-3.12-blue)
![Azure](https://img.shields.io/badge/Azure-Container%20Apps-0078D4)
![M365](https://img.shields.io/badge/M365-Copilot%20Custom%20Engine%20Agent-7B83EB)

---

## 🎯 무엇을 만드나요?

사내 FAQ(`faq.json`)를 근거로 답변하는 Agent를 만들고, 다음과 같이 전체 흐름을 완성합니다.

```
[M365 Copilot UI]
      │
      ▼
[Azure Bot Service] ── Teams 채널 + Entra App ID
      │  /api/messages
      ▼
[Azure Container Apps]
      ├─ Microsoft 365 Agents SDK   ← 채널 어댑터 (aiohttp)
      └─ GitHub Copilot SDK          ← 추론 엔진 + search_faq 도구
            └─ BYOM: Azure OpenAI (Managed Identity 토큰)
```

자세한 설계는 [docs/architecture.md](./docs/architecture.md)를 참고하세요.

---

## 📚 학습 목표

이 워크숍을 마치면 다음을 할 수 있게 됩니다.

- GitHub Copilot SDK(Python)로 도구를 가진 Agent 작성
- Microsoft 365 Agents SDK로 Agent를 Bot 채널에 노출
- `azd` + Bicep으로 Azure Container Apps에 배포
- Microsoft 365 Agents Toolkit으로 매니페스트 패키징
- Microsoft 365 Copilot에서 Custom Engine Agent로 호출/검증

---

## 🗺️ 워크숍 구성

| 단계 | 문서 | 핵심 활동 |
|---|---|---|
| 0 | [Prerequisites](./docs/00-prerequisites.md) | 계정·라이선스·도구·정책 점검 |
| 1 | [Local Development](./docs/01-local-development.md) | FAQ 도구 + Copilot 두뇌 + Agents SDK 호스팅 + 로컬 테스트 |
| 2 | [Azure Deployment](./docs/02-azure-deployment.md) | Entra 앱·Bicep·`azd up`·Bot 구성 |
| 3 | [M365 Copilot Integration](./docs/03-m365-integration.md) | 매니페스트·Teams 채널·사이드로드·E2E 검증 |
| 4 | [Operations & Cleanup](./docs/04-operations-cleanup.md) | 관찰성·운영 팁·Track A 폴백·정리 |
| ⚙️ | [Architecture](./docs/architecture.md) | 아키텍처 결정 배경과 Wrapper 패턴 |
| 🛠️ | [Troubleshooting](./docs/troubleshooting.md) | 자주 발생하는 문제와 해결 |

---

## 🚀 빠른 시작

### 1) 사전 점검 (필수)
- Azure 구독 (Owner/Contributor)
- Microsoft 365 테넌트 + **M365 Copilot 라이선스가 부여된 테스트 사용자 1명**
- Teams 사용자 정의 앱 업로드 허용 정책
- Entra 앱 등록 권한
- Azure OpenAI 모델 배포 (예: `gpt-4o`)
- 로컬 도구: Python 3.11+, Docker Desktop, `azd`, `az`, Node.js, VS Code (+ Microsoft 365 Agents Toolkit, Python, Bicep, Docker 확장)

자세한 체크리스트는 [docs/00-prerequisites.md](./docs/00-prerequisites.md).

### 2) 클론 & 환경 준비
```powershell
git clone https://github.com/keonlee/FAQ-agent-workshop.git
cd FAQ-agent-workshop

python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

Copy-Item .env.sample .env  # 값 채우기
```

### 3) 로컬 테스트 → Azure 배포 → M365 통합
[docs/01-local-development.md](./docs/01-local-development.md)부터 순서대로 따라가세요.

---

## 📦 리포지토리 구조

```
FAQ-agent-workshop/
├─ README.md                      ← 이 파일
├─ docs/                          ← 단계별 가이드
│  ├─ 00-prerequisites.md
│  ├─ 01-local-development.md
│  ├─ 02-azure-deployment.md
│  ├─ 03-m365-integration.md
│  ├─ 04-operations-cleanup.md
│  ├─ architecture.md
│  └─ troubleshooting.md
├─ src/                           ← Python 스타터 코드
│  ├─ app.py                      ← aiohttp + M365 Agents SDK 진입점
│  ├─ copilot_brain.py            ← GitHub Copilot SDK 래퍼
│  ├─ faq_tool.py                 ← search_faq() 구현
│  └─ faq.json                    ← 샘플 FAQ KB
├─ infra/                         ← Bicep IaC
│  ├─ main.bicep
│  ├─ main.parameters.json
│  └─ modules/
│     ├─ container-registry.bicep
│     ├─ log-analytics.bicep
│     ├─ container-apps-env.bicep
│     ├─ container-app.bicep
│     ├─ bot-service.bicep
│     └─ role-assignment.bicep
├─ appPackage/                    ← M365 앱 매니페스트
│  ├─ manifest.template.json
│  └─ icons/README.md
├─ scripts/
│  └─ create-bot-app.ps1          ← Entra 앱 사전 생성 스크립트
├─ Dockerfile
├─ azure.yaml                     ← azd 설정
├─ requirements.txt
├─ .env.sample
├─ .dockerignore
└─ .gitignore
```

---

## ⚠️ 중요 주의사항

이 워크숍은 입문자 학습을 위한 단순화된 구성입니다. 다음을 기억하세요.

- **상태 관리:** 인메모리 상태 + `replicas=1`로 시작합니다. 운영 시 외부 저장소(Cosmos DB 등) 필요
- **시크릿:** 데모는 평문 환경 변수, 운영은 Key Vault 또는 Managed Identity로 대체
- **GitHub Copilot SDK는 컨테이너에서 인증 검증이 필요합니다** — Phase 1.7 단계에서 반드시 컨테이너 시작 검증 수행. 실패 시 Track A(Azure OpenAI 직접 호출)로 폴백 고려 ([docs/04-operations-cleanup.md](./docs/04-operations-cleanup.md#track-a-폴백) 참조)

---

## 📄 라이선스

[MIT](./LICENSE)

---

## 🙋 기여

이슈/PR 환영합니다. 워크숍 진행 중 막힌 부분, 오류, 개선 제안을 [Issues](https://github.com/keonlee/FAQ-agent-workshop/issues)에 남겨주세요.
