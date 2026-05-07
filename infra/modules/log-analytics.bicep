@description('Log Analytics workspace 이름')
param name string

@description('지역')
param location string

@description('태그')
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output id string = workspace.id
output customerId string = workspace.properties.customerId
output primarySharedKey string = workspace.listKeys().primarySharedKey
