@description('Bot Service 리소스 이름 (전역 고유)')
param name string

@description('지역 (Bot Service는 보통 global)')
param location string = 'global'

@description('태그')
param tags object = {}

@description('Microsoft App ID (Entra App Client ID)')
param msaAppId string

@description('Tenant ID (SingleTenant 봇)')
param msaAppTenantId string

@description('Messaging endpoint (https://<aca-fqdn>/api/messages)')
param endpoint string

resource bot 'Microsoft.BotService/botServices@2023-09-15-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'azurebot'
  sku: {
    name: 'F0'
  }
  properties: {
    displayName: name
    msaAppId: msaAppId
    msaAppType: 'SingleTenant'
    msaAppTenantId: msaAppTenantId
    endpoint: endpoint
    publicNetworkAccess: 'Enabled'
  }
}

// Microsoft Teams 채널 활성화 (M365 Copilot 노출 전제)
resource teamsChannel 'Microsoft.BotService/botServices/channels@2023-09-15-preview' = {
  parent: bot
  name: 'MsTeamsChannel'
  location: location
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      isEnabled: true
    }
  }
}

output id string = bot.id
output name string = bot.name
