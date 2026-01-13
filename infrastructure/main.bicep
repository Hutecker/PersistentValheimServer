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

// Standardized naming: use short hash of resource group for consistency
// This ensures deterministic naming while keeping names short
var resourceSuffix = substring(uniqueString(resourceGroup().id), 0, 8)
var storageAccountName = 'valheim${resourceSuffix}'
var fileShareName = 'valheim-worlds'
// Function App is created via CLI with standardized name 'valheim-func-flex' (not in Bicep)
// Application Insights is automatically created with the Function App (not in Bicep)
var keyVaultName = 'valheim-kv-${resourceSuffix}'
var containerGroupName = 'valheim-server'
var functionStorageAccountName = 'valheimfunc${resourceSuffix}'

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

// Application Insights is automatically created when the Function App is created via CLI
// No need to create it separately in Bicep - the Function App will have its own Application Insights
// This prevents duplicate Application Insights resources

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

// Flex Consumption Function App is created via Azure CLI in deploy.ps1
// Bicep doesn't fully support Flex Consumption functionAppConfig yet
// The Function App name is standardized to 'valheim-func-flex'

// Role assignments are created via Azure CLI in deploy.ps1 after the Function App is created
// This is because:
// 1. The Function App is created via CLI (Flex Consumption not fully supported in Bicep)
// 2. Role assignments require the Function App's managed identity principal ID
// 3. Azure doesn't allow updating existing role assignments, so they must be created after Function App creation

// Outputs
// Function App is created via CLI with standardized name 'valheim-func-flex'
output functionAppName string = 'valheim-func-flex'
output functionAppUrl string = 'https://valheim-func-flex.azurewebsites.net'
output storageAccountName string = storageAccount.name
output functionStorageAccountName string = functionStorageAccount.name
output keyVaultName string = keyVaultName
output containerGroupName string = containerGroupName
// Application Insights is automatically created with the Function App
