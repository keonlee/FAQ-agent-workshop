<#
.SYNOPSIS
    Bot에 사용할 Entra 앱 등록 + 시크릿 생성. 결과를 azd env로 저장.

.EXAMPLE
    .\scripts\create-bot-app.ps1 -DisplayName "faq-agent-bot"
#>
param(
    [string]$DisplayName = "faq-agent-bot",
    [int]$SecretYears = 1
)

$ErrorActionPreference = "Stop"

Write-Host "▶ Entra 앱 생성: $DisplayName" -ForegroundColor Cyan
$appId = az ad app create `
    --display-name $DisplayName `
    --sign-in-audience AzureADMyOrg `
    --query appId -o tsv

if (-not $appId) { throw "앱 생성 실패" }
Write-Host "  appId = $appId" -ForegroundColor Green

Write-Host "▶ 클라이언트 시크릿 발급 ($SecretYears 년)" -ForegroundColor Cyan
$secret = az ad app credential reset `
    --id $appId `
    --years $SecretYears `
    --query password -o tsv

if (-not $secret) { throw "시크릿 발급 실패" }
Write-Host "  secret = (재표시되지 않으니 안전하게 보관하세요)" -ForegroundColor Yellow

$tenantId = az account show --query tenantId -o tsv

# 서비스 주체(Service Principal) 생성 — Bot Service에서 토큰 발급에 필요할 수 있음
az ad sp create --id $appId --output none 2>$null

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host " 결과:" -ForegroundColor Cyan
Write-Host "  BOT_CLIENT_ID:     $appId"
Write-Host "  BOT_CLIENT_SECRET: $secret"
Write-Host "  BOT_TENANT_ID:     $tenantId"
Write-Host "===========================================" -ForegroundColor Cyan

# azd env가 초기화되어 있다면 자동 저장
$azdEnv = (azd env list --output json 2>$null | ConvertFrom-Json) | Where-Object { $_.IsDefault }
if ($azdEnv) {
    Write-Host ""
    Write-Host "▶ azd env에 값 저장 ($($azdEnv.Name))" -ForegroundColor Cyan
    azd env set BOT_CLIENT_ID $appId
    azd env set BOT_TENANT_ID $tenantId
    azd env set --secret BOT_CLIENT_SECRET $secret
    Write-Host "  완료" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "ℹ azd env가 초기화되지 않아 자동 저장을 건너뜁니다." -ForegroundColor Yellow
    Write-Host "  azd env new <name> 후 다음 명령을 실행하세요:" -ForegroundColor Yellow
    Write-Host "    azd env set BOT_CLIENT_ID $appId"
    Write-Host "    azd env set BOT_TENANT_ID $tenantId"
    Write-Host "    azd env set --secret BOT_CLIENT_SECRET <secret>"
}
