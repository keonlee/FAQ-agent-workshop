// =====================================================
// FAQ Agent Workshop — main.bicep
// Resource group scope deployment via `azd up`.
// =====================================================
targetScope = 'resourceGroup'

@description('Environment name (azd env)')
param environmentName string

@description('Azure region')
param location string = resourceGroup().location

@description('Resource name token (used to suffix names for uniqueness)')
param resourceToken string = uniqueString(subscription().id, resourceGroup().id, environmentName)

@description('Bot Entra App Client ID (Phase 2.2에서 생성)')
param botClientId string

@description('Bot Entra App Client Secret')
@secure()
param botClientSecret string

@description('Bot Entra App Tenant ID')
param botTenantId string

@description('Azure OpenAI endpoint (예: https://xxx.openai.azure.com/)')
param azureOpenAiEndpoint string

@description('Azure OpenAI deployment name (예: gpt-4o)')
param azureOpenAiDeployment string = 'gpt-4o'

@description('Azure OpenAI resource ID (RBAC 부여 대상)')
param azureOpenAiResourceId string

@description('컨테이너 이미지 (azd가 빌드/태그 후 주입)')
param containerImage string = ''

var tags = {
  'azd-env-name': environmentName
  workshop: 'faq-agent'
}

// --- Log Analytics ---
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    name: 'log-${resourceToken}'
    location: location
    tags: tags
  }
}

// --- Container Registry ---
module containerRegistry 'modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    name: 'cr${resourceToken}'
    location: location
    tags: tags
  }
}

// --- Container Apps Environment ---
module containerAppsEnv 'modules/container-apps-env.bicep' = {
  name: 'container-apps-env'
  params: {
    name: 'cae-${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsPrimarySharedKey: logAnalytics.outputs.primarySharedKey
  }
}

// --- Container App ---
module containerApp 'modules/container-app.bicep' = {
  name: 'container-app'
  params: {
    name: 'ca-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    environmentId: containerAppsEnv.outputs.id
    containerRegistryName: containerRegistry.outputs.name
    containerImage: !empty(containerImage) ? containerImage : '${containerRegistry.outputs.loginServer}/faq-agent:latest'
    targetPort: 3978
    botClientId: botClientId
    botClientSecret: botClientSecret
    botTenantId: botTenantId
    azureOpenAiEndpoint: azureOpenAiEndpoint
    azureOpenAiDeployment: azureOpenAiDeployment
  }
}

// --- AOAI Role Assignment (Container App MI → Cognitive Services OpenAI User) ---
module roleAssignment 'modules/role-assignment.bicep' = {
  name: 'role-assignment-aoai'
  params: {
    azureOpenAiResourceId: azureOpenAiResourceId
    principalId: containerApp.outputs.principalId
  }
}

// --- Bot Service + Teams Channel ---
module botService 'modules/bot-service.bicep' = {
  name: 'bot-service'
  params: {
    name: 'bot-${resourceToken}'
    location: 'global'
    tags: tags
    msaAppId: botClientId
    msaAppTenantId: botTenantId
    endpoint: 'https://${containerApp.outputs.fqdn}/api/messages'
  }
}

// --- Outputs ---
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name
output AZURE_CONTAINER_APP_FQDN string = containerApp.outputs.fqdn
output AZURE_CONTAINER_APP_NAME string = containerApp.outputs.name
output BOT_SERVICE_NAME string = botService.outputs.name
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
