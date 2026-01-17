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

@description('Monthly budget limit in USD (100% threshold)')
param monthlyBudgetLimit int = 30

@description('Email address for budget alerts')
param budgetAlertEmail string = ''

@description('Budget start date (first day of month in YYYY-MM-DD format). Must be first of current month for monthly budgets.')
param budgetStartDate string = '${utcNow('yyyy-MM')}-01'

var storageAccountName = 'valheimsa'
var fileShareName = 'valheim-worlds'
var keyVaultName = 'valheim-kv'
var containerGroupName = 'valheim-server'
var functionStorageAccountName = 'valheimfuncsa'
var functionAppName = 'valheim-func'
var appInsightsName = 'valheim-func-insights'
// ACR name must be globally unique - using uniqueString based on resource group for consistency
var acrNameSuffix = toLower(substring(uniqueString(resourceGroup().id), 0, 8))
var acrName = 'valheimacr${acrNameSuffix}'
var valheimImageName = 'valheim-server'
var valheimImageTag = 'latest'

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

// Azure Container Registry (Basic tier ~$5/month)
// Avoids Docker Hub rate limiting issues when pulling images
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic' // Basic tier: ~$5/month, 10GB storage, sufficient for single image
  }
  properties: {
    adminUserEnabled: true // Required for ACI to pull images (ACI doesn't support managed identity for ACR yet)
    publicNetworkAccess: 'Enabled'
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

// ACR admin password stored in Key Vault
resource acrPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AcrPassword'
  properties: {
    value: acr.listCredentials().passwords[0].value
  }
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${appInsightsName}-ws'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights for monitoring (using explicit Log Analytics workspace)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
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
        version: '10.0'
      }
    }
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          // AzureWebJobsStorage is required for Flex Consumption (host state, triggers, logs, function indexing)
          // Note: listKeys() is required here as storage connection strings aren't available as resource properties
          // @suppress use-resource-symbol-reference Storage account keys must be retrieved via listKeys() - no resource symbol available
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(functionStorageAccount.id, '2023-01-01').keys[0].value}'
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
        {
          name: 'ACR_LOGIN_SERVER'
          value: acr.properties.loginServer
        }
        {
          name: 'ACR_USERNAME'
          value: acr.listCredentials().username
        }
        {
          name: 'ACR_PASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/AcrPassword/)'
        }
        {
          name: 'CONTAINER_IMAGE'
          value: '${acr.properties.loginServer}/${valheimImageName}:${valheimImageTag}'
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

// Role definition IDs (Azure built-in roles)
var keyVaultRoleDefId = '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
var containerInstanceRoleDefId = '5d977122-f97e-4b4d-a52f-6b43003ddb4d' // Azure Container Instances Contributor Role
var storageAccountRoleDefId = '17d1049b-9a84-46fb-8f53-869881c3d3ab' // Storage Account Contributor
var storageFileRoleDefId = 'a7264617-510b-434b-a828-9731dc254ea7' // Storage File Data SMB Share Elevated Contributor
var storageBlobRoleDefId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Owner

// Role assignments for Function App managed identity
// Using fully-qualified guid() names prevents ARM update conflicts
// Bicep automatically infers dependencies from functionApp.identity.principalId

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, resourceGroup().id, keyVault.id, functionAppName, keyVaultRoleDefId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerInstanceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, resourceGroup().id, functionAppName, containerInstanceRoleDefId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', containerInstanceRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageAccountRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, resourceGroup().id, storageAccount.id, functionAppName, storageAccountRoleDefId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageAccountRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageFileRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, resourceGroup().id, storageAccount.id, functionAppName, storageFileRoleDefId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageFileRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, resourceGroup().id, functionStorageAccount.id, functionAppName, storageBlobRoleDefId)
  scope: functionStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobRoleDefId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

var actionGroupName = 'valheim-budget'

resource budgetActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (!empty(budgetAlertEmail)) {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: 'valheim-bgt'
    enabled: true
    emailReceivers: [
      {
        name: 'budget-alert-email'
        emailAddress: budgetAlertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Budget scoped to resource group
// Note: Budgets automatically reset monthly
var budgetEndDate = '2099-12-31T23:59:59Z'

resource budget 'Microsoft.Consumption/budgets@2023-05-01' = if (!empty(budgetAlertEmail)) {
  name: 'valheim-monthly-budget'
  scope: resourceGroup()
  properties: {
    timePeriod: {
      startDate: '${budgetStartDate}T00:00:00Z'
      endDate: budgetEndDate
    }
    timeGrain: 'Monthly'
    amount: monthlyBudgetLimit
    category: 'Cost'
    notifications: {
      actualGreaterThan50: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 50
        contactEmails: [budgetAlertEmail]
        contactGroups: []
        contactRoles: []
        thresholdType: 'Actual'
      }
      actualGreaterThan75: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 75
        contactEmails: [budgetAlertEmail]
        contactGroups: []
        contactRoles: []
        thresholdType: 'Actual'
      }
      actualGreaterThan90: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        contactEmails: [budgetAlertEmail]
        contactGroups: []
        contactRoles: []
        thresholdType: 'Actual'
      }
      actualGreaterThan100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: [budgetAlertEmail]
        contactGroups: []
        contactRoles: []
        thresholdType: 'Actual'
      }
      forecastedGreaterThan80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: [budgetAlertEmail]
        contactGroups: []
        contactRoles: []
        thresholdType: 'Forecasted'
      }
    }
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
output budgetConfigured bool = !empty(budgetAlertEmail)
output budgetLimit string = '$${monthlyBudgetLimit}/month'
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output containerImage string = '${acr.properties.loginServer}/${valheimImageName}:${valheimImageTag}'