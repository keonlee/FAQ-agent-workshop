@description('Container Apps Environment 이름')
param name string

@description('지역')
param location string

@description('태그')
param tags object = {}

@description('Log Analytics workspace 리소스 ID')
param logAnalyticsWorkspaceId string

@description('Log Analytics customerId (workspaceId)')
param logAnalyticsCustomerId string

@description('Log Analytics primary shared key')
@secure()
param logAnalyticsPrimarySharedKey string

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsPrimarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output id string = environment.id
output defaultDomain string = environment.properties.defaultDomain
