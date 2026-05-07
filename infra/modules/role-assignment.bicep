@description('Azure OpenAI 리소스 ID')
param azureOpenAiResourceId string

@description('역할을 부여받을 Principal (Container App UAMI)')
param principalId string

// "Cognitive Services OpenAI User" built-in role
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource aoai 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' existing = {
  name: last(split(azureOpenAiResourceId, '/'))
  scope: resourceGroup(split(azureOpenAiResourceId, '/')[2], split(azureOpenAiResourceId, '/')[4])
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aoai
  name: guid(aoai.id, principalId, openAiUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id
