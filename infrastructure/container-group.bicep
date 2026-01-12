@description('Storage account name for file share')
param storageAccountName string

@description('File share name')
param fileShareName string

@description('Server name')
param serverName string

@description('Server password')
@secure()
param serverPassword string

@description('Container CPU cores')
param containerCpu float = 2

@description('Container memory in GB')
param containerMemory float = 4

@description('Resource group name')
param resourceGroupName string

var containerGroupName = 'valheim-server'
var containerImage = 'lloesche/valheim-server:latest'

// Get storage account key
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

var storageAccountKey = storageAccount.listKeys().keys[0].value

// Container Group for Valheim Server
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: resourceGroup().location
  properties: {
    containers: [
      {
        name: 'valheim-server'
        properties: {
          image: containerImage
          resources: {
            requests: {
              cpu: containerCpu
              memoryInGB: containerMemory
            }
          }
          environmentVariables: [
            {
              name: 'SERVER_NAME'
              value: serverName
            }
            {
              name: 'WORLD_NAME'
              value: 'Dedicated'
            }
            {
              name: 'SERVER_PASS'
              value: serverPassword
            }
            {
              name: 'SERVER_PUBLIC'
              value: '1'
            }
            {
              name: 'BACKUPS'
              value: '1'
            }
            {
              name: 'BACKUPS_RETENTION_DAYS'
              value: '7'
            }
            {
              name: 'UPDATE_CRON'
              value: '0 4 * * *' // Daily at 4 AM
            }
          ]
          volumeMounts: [
            {
              name: 'world-data'
              mountPath: '/config'
            }
          ]
          ports: [
            {
              port: 2456
              protocol: 'UDP'
            }
            {
              port: 2457
              protocol: 'UDP'
            }
            {
              port: 2458
              protocol: 'UDP'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    ipAddress: {
      type: 'Public'
      ports: [
        {
          protocol: 'UDP'
          port: 2456
        }
        {
          protocol: 'UDP'
          port: 2457
        }
        {
          protocol: 'UDP'
          port: 2458
        }
      ]
      dnsNameLabel: 'valheim-${uniqueString(resourceGroup().id)}'
    }
    volumes: [
      {
        name: 'world-data'
        azureFile: {
          shareName: fileShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccountKey
        }
      }
    ]
    restartPolicy: 'Never' // Don't auto-restart, we control via Discord
  }
}

output containerGroupName string = containerGroup.name
output publicIPAddress string = containerGroup.properties.ipAddress.ip
output fqdn string = containerGroup.properties.ipAddress.fqdn
