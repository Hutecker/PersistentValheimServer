@description('The name of the resource group to create')
param resourceGroupName string = 'valheim-server-rg'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Discord bot token for server control')
@secure()
param discordBotToken string

@description('Discord public key for signature verification (required for interactions endpoint)')
@secure()
param discordPublicKey string

@description('Valheim server password')
@secure()
param serverPassword string

@description('Valheim server name')
param serverName string = 'Valheim Server'

@description('Auto-shutdown timeout in minutes')
param autoShutdownMinutes int = 120

@description('Container CPU cores')
param containerCpu int = 2

@description('Container memory in GB')
param containerMemory int = 4

var storageAccountName = 'valheimsa'
var fileShareName = 'valheim-worlds'
var keyVaultName = 'valheim-kv'
var containerGroupName = 'valheim-server'
var functionStorageAccountName = 'valheimfuncsa'
var functionAppName = 'valheim-func'
var appInsightsName = 'valheim-func-insights'

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
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    shareQuota: 100 // 100 GB should be plenty for world saves
  }
}

// Key Vault for secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
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

// Discord Public Key for signature verification
// This is required for Discord interactions endpoint verification
resource discordPublicKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DiscordPublicKey'
  properties: {
    value: discordPublicKey
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
  name: functionStorageAccountName
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

// Blob container for Function App deployment (required for Flex Consumption)
var deploymentContainerName = 'app-package-${toLower(take(functionAppName, 32))}'

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: functionStorageAccount
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource functionAppHostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppHostingPlan.id
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${functionStorageAccount.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '8.0'
      }
    }
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'RESOURCE_GROUP_NAME'
          value: resourceGroup().name
        }
        {
          name: 'SERVER_NAME'
          value: serverName
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'FILE_SHARE_NAME'
          value: fileShareName
        }
        {
          name: 'LOCATION'
          value: location
        }
        {
          name: 'AUTO_SHUTDOWN_MINUTES'
          value: string(autoShutdownMinutes)
        }
        {
          name: 'CONTAINER_GROUP_NAME'
          value: containerGroupName
        }
        {
          name: 'DISCORD_PUBLIC_KEY'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/DiscordPublicKey/)'
        }
        {
          name: 'SERVER_PASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/ServerPassword/)'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ]
      use32BitWorkerProcess: false
      http20Enabled: true
      minTlsVersion: '1.2'
    }
    httpsOnly: true
    reserved: true
  }
  dependsOn: [
    deploymentContainer
  ]
}

var keyVaultRoleDefId = '4633458b-17de-408a-b874-0445c86b69e6'
var containerInstanceRoleDefId = '5d977122-f97e-4b4d-a52f-6b43003ddb4d'
var storageAccountRoleDefId = '17d1049b-9a84-46fb-8f53-869881c3d3ab'
var storageFileRoleDefId = 'a7264617-510b-434b-a828-9731dc254ea7'
var storageBlobRoleDefId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, keyVaultRoleDefId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerInstanceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, containerInstanceRoleDefId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', containerInstanceRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageAccountRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageAccountRoleDefId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageAccountRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageFileRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageFileRoleDefId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageFileRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionStorageAccount.id, functionApp.id, storageBlobRoleDefId)
  scope: functionStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output storageAccountName string = storageAccount.name
output functionStorageAccountName string = functionStorageAccount.name
output keyVaultName string = keyVaultName
output containerGroupName string = containerGroupName
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString