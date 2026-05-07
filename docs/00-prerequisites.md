# Phase 0 — 사전 준비

> **소요 시간 가이드:** 처음 환경 구성 시 도구 설치/계정 준비에 가장 많은 시간이 소요됩니다. 모든 체크박스가 ✅ 가 된 후 Phase 1로 이동하세요.

## 0.1 계정 / 라이선스 / 권한

| 항목 | 요구 사항 | 확인 방법 |
|---|---|---|
| Azure 구독 | Owner 또는 Contributor 권한 | `az account show` 후 IAM 확인 |
| Microsoft 365 테넌트 | 개발자 테넌트 또는 사이드로드 허용 테넌트 | M365 Developer Program: https://developer.microsoft.com/microsoft-365/dev-program |
| **Microsoft 365 Copilot 라이선스** | 테스트 사용자에게 라이선스 부여 | M365 관리 센터 → 사용자 → 라이선스 |
| Teams 사이드로드 정책 | 사용자 정의 앱 업로드 허용 | Teams 관리 센터 → Teams 앱 → 설치 정책 |
| Entra 앱 등록 권한 | Application Developer 이상 | Entra 관리 센터 → 역할 |
| GitHub Copilot 구독 | 사용자 계정에 활성 (선택, GitHub-hosted 모델 사용 시) | https://github.com/settings/copilot |
| Azure OpenAI 액세스 | 구독에 모델 배포 가능 | Azure Portal → Azure OpenAI 서비스 |

> ⚠️ **M365 Copilot 라이선스가 없으면 Copilot UI에서 만들어둔 Agent를 볼 수 없습니다.** 워크숍 진행 전 반드시 확인하세요.

## 0.2 로컬 도구 설치

### 필수
- **Python 3.11+** (3.12 권장) — https://www.python.org/downloads/
- **Docker Desktop** (실행 중이어야 함) — https://www.docker.com/products/docker-desktop/
- **Azure Developer CLI (`azd`)** — https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd
- **Azure CLI (`az`)** — https://learn.microsoft.com/cli/azure/install-azure-cli
- **Node.js LTS** — https://nodejs.org/ (Agents Toolkit CLI 및 매니페스트 패키징)
- **Git**
- **VS Code** + 확장
  - Microsoft 365 Agents Toolkit (구 Teams Toolkit)
  - Python
  - Azure Bicep
  - Docker
  - Azure Tools

### 권장
- **Microsoft 365 Agents Playground** (또는 `teamsapptester` npm 패키지) — 1차 로컬 테스트
- **devtunnel CLI** — M365 Copilot에서 로컬 개발 시 외부 노출

### 선택
- **Bot Framework Emulator** — 보조 디버깅 (Bot Service의 활동 검사)

### 버전 확인
```powershell
python --version              # 3.11.x 이상
docker --version
docker info                   # 데몬 실행 중 확인
azd version
az --version
node --version
git --version
```

## 0.3 Azure 리소스 공급자 등록 (구독당 1회)

```powershell
az login
az account set --subscription "<구독 이름 또는 ID>"

az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.BotService
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.CognitiveServices

# 등록 상태 확인 (모두 "Registered" 가 되어야 함)
az provider list --query "[?namespace=='Microsoft.App' || namespace=='Microsoft.BotService' || namespace=='Microsoft.ContainerRegistry' || namespace=='Microsoft.OperationalInsights' || namespace=='Microsoft.CognitiveServices'].[namespace, registrationState]" -o table
```

## 0.4 Azure OpenAI 모델 배포

1. Azure Portal에서 **Azure OpenAI** 리소스 생성 (지역: East US, Sweden Central 등 모델 가용 지역)
2. **Model deployments** → **Manage deployments** → **Create new deployment**
3. 모델: `gpt-4o` (또는 `gpt-4.1`, `gpt-4o-mini`)
4. 배포 이름 기록 (예: `gpt-4o`)
5. 엔드포인트 기록: `https://<your-resource>.openai.azure.com/`

> 💡 모델 배포 이름은 모델 이름과 다를 수 있습니다. **배포 이름**을 환경 변수에 사용합니다.

## 0.5 Microsoft 365 Developer 테넌트 (선택)

회사 테넌트에서 사이드로드가 막혀 있으면 개인 개발자 테넌트를 만드세요.

1. https://developer.microsoft.com/microsoft-365/dev-program 가입
2. **Instant Sandbox** 또는 **Configurable Sandbox** 선택
3. 관리자 계정 정보 보관
4. M365 Copilot 라이선스가 포함되는지 확인 (트라이얼 단계 또는 별도 활성화 필요)

## 0.6 사이드로드 정책 확인

Teams 관리 센터 (https://admin.teams.microsoft.com):
1. **Teams 앱** → **Setup policies** → 사용자 정책 선택
2. **Upload custom apps** = **On** 인지 확인
3. 정책이 테스트 사용자에게 적용되었는지 확인

## 0.7 사전 체크리스트

Phase 1로 진행하기 전 모두 ✅ 확인하세요.

- [ ] Azure CLI 로그인 완료 (`az account show`)
- [ ] 구독에 Owner/Contributor 권한 보유
- [ ] M365 테넌트에 **Copilot 라이선스 보유 사용자 1명** 확인
- [ ] Teams 관리 센터에서 사용자 정의 앱 업로드 허용
- [ ] Entra 앱 등록 권한 보유 (Application Developer 이상)
- [ ] Azure OpenAI 리소스 + 모델 배포 완료, 배포 이름 기록
- [ ] 로컬 도구 설치 및 버전 확인 완료
- [ ] Azure 리소스 공급자 5개 모두 Registered

## 다음 단계
👉 [01-local-development.md](./01-local-development.md)로 이동하여 Agent를 로컬에서 개발합니다.
