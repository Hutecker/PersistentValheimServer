@description('The name of the resource group to create')
param resourceGroupName string = 'valheim-server-rg'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Discord bot token for server control')
@secure()
param discordBotToken string

@description('Valheim server password')
@secure()
param serverPassword string

@description('Valheim server name')
param serverName string = 'Valheim Server'

@description('Auto-shutdown timeout in minutes')
param autoShutdownMinutes int = 120

@description('Container CPU cores')
param containerCpu float = 2

@description('Container memory in GB')
param containerMemory float = 4

var storageAccountName = 'valheim${uniqueString(resourceGroup().id)}'
var fileShareName = 'valheim-worlds'
var functionAppName = 'valheim-func-${uniqueString(resourceGroup().id)}'
var keyVaultName = 'valheim-kv-${uniqueString(resourceGroup().id)}'
var containerGroupName = 'valheim-server'
var appInsightsName = 'valheim-insights-${uniqueString(resourceGroup().id)}'

// Storage Account for world saves
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS' // Lowest cost for persistent storage
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    // Note: Azure Files identity-based authentication is configured but not yet used
    // Container Instances don't support managed identity for Azure Files mounts
    // This is prepared for future when ACI adds support
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'None' // Will be enabled when ACI supports it
    }
  }
}

// File Share for world persistence
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: storageAccount::storageAccount.properties.primaryEndpoints.file
  name: fileShareName
  properties: {
    shareQuota: 100 // 100 GB should be plenty for world saves
  }
}

// Key Vault for secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-10-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true // Use RBAC instead of access policies
    accessPolicies: []
  }
}

// Store secrets in Key Vault
resource discordTokenSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DiscordBotToken'
  properties: {
    value: discordBotToken
  }
}

resource serverPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ServerPassword'
  properties: {
    value: serverPassword
  }
}

// Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

// Storage Account for Function App
resource functionStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'valheimfunc${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// App Service Plan (Consumption - pay per execution)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'valheim-func-plan'
  location: location
  kind: 'functionapp'
  properties: {
    reserved: true
  }
  sku: {
    name: 'Y1' // Consumption plan - cost-effective
    tier: 'Dynamic'
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: functionStorageAccount.name
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING__accountName'
          value: functionStorageAccount.name
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'KEY_VAULT_NAME'
          value: keyVaultName
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccountName
        }
        {
          name: 'FILE_SHARE_NAME'
          value: fileShareName
        }
        {
          name: 'CONTAINER_GROUP_NAME'
          value: containerGroupName
        }
        {
          name: 'RESOURCE_GROUP_NAME'
          value: resourceGroupName
        }
        {
          name: 'AUTO_SHUTDOWN_MINUTES'
          value: string(autoShutdownMinutes)
        }
        {
          name: 'SERVER_NAME'
          value: serverName
        }
        {
          name: 'LOCATION'
          value: location
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Grant Function App access to Key Vault using RBAC
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.identity.principalId, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to manage Container Instances
resource functionAppRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'ContainerInstanceContributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '83a5a552-3eb7-4b5f-b13c-2afcc11d3ff8') // Container Instance Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to function storage account
resource functionStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'StorageBlobDataContributor')
  scope: functionStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Storage Account
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'StorageAccountContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Azure Files using identity-based authentication
// Note: This is for future use if we migrate to identity-based file access
// Currently, container instances still require storage keys for Azure Files mounts
resource fileShareRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'StorageFileDataSMBShareElevatedContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a7264617-510f-478b-bc68-6b8df7c8c4e0') // Storage File Data SMB Share Elevated Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output storageAccountName string = storageAccount.name
output keyVaultName string = keyVaultName
output containerGroupName string = containerGroupName
output appInsightsConnectionString string = appInsights.properties.ConnectionString
