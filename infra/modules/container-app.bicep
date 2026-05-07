@description('Container App 이름')
param name string

@description('지역')
param location string

@description('태그 (azd-service-name 포함)')
param tags object = {}

@description('Container Apps Environment 리소스 ID')
param environmentId string

@description('ACR 이름 (AcrPull 권한 부여 대상)')
param containerRegistryName string

@description('컨테이너 이미지 (registry/repo:tag)')
param containerImage string

@description('컨테이너 포트')
param targetPort int = 3978

@description('Bot Entra App Client ID')
param botClientId string

@description('Bot Entra App Client Secret')
@secure()
param botClientSecret string

@description('Bot Entra App Tenant ID')
param botTenantId string

@description('Azure OpenAI endpoint')
param azureOpenAiEndpoint string

@description('Azure OpenAI deployment name')
param azureOpenAiDeployment string

// 기존 ACR 참조 (AcrPull 권한 부여용)
resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: containerRegistryName
}

// User-Assigned Managed Identity
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${name}-mi'
  location: location
  tags: tags
}

// AcrPull 권한 부여
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d' // built-in
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, uami.id, acrPullRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  dependsOn: [acrPull]
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: uami.id
        }
      ]
      secrets: [
        {
          name: 'bot-client-secret'
          value: botClientSecret
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            { name: 'PORT', value: string(targetPort) }
            { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID', value: botClientId }
            { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__TENANTID', value: botTenantId }
            { name: 'CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET', secretRef: 'bot-client-secret' }
            { name: 'AZURE_OPENAI_ENDPOINT', value: azureOpenAiEndpoint }
            { name: 'AZURE_OPENAI_CHAT_DEPLOYMENT_NAME', value: azureOpenAiDeployment }
            { name: 'AZURE_CLIENT_ID', value: uami.properties.clientId }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output id string = containerApp.id
output name string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output principalId string = uami.properties.principalId
output identityResourceId string = uami.id
