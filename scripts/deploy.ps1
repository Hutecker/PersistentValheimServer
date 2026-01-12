# Deployment Script for Valheim Server on Azure
# This script automates the deployment of all infrastructure components

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$true)]
    [string]$DiscordBotToken,
    
    [Parameter(Mandatory=$true)]
    [string]$ServerPassword,
    
    [Parameter(Mandatory=$false)]
    [string]$ServerName = "Valheim Server",
    
    [Parameter(Mandatory=$false)]
    [int]$AutoShutdownMinutes = 120,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = ""
)

Write-Host "Valheim Server Azure Deployment" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

# Check Azure CLI
try {
    $azVersion = az version --output json | ConvertFrom-Json
    Write-Host "Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green
} catch {
    Write-Host "Error: Azure CLI not found. Please install from https://aka.ms/installazurecliwindows" -ForegroundColor Red
    exit 1
}

# Check if logged in
try {
    $account = az account show --output json | ConvertFrom-Json
    if ($SubscriptionId -and $account.id -ne $SubscriptionId) {
        Write-Host "Switching to subscription: $SubscriptionId" -ForegroundColor Yellow
        az account set --subscription $SubscriptionId
    }
    Write-Host "Using subscription: $($account.name) ($($account.id))" -ForegroundColor Green
} catch {
    Write-Host "Error: Not logged in to Azure. Run 'az login'" -ForegroundColor Red
    exit 1
}

# Set subscription ID if not provided
if (-not $SubscriptionId) {
    $account = az account show --output json | ConvertFrom-Json
    $SubscriptionId = $account.id
}

# Deploy infrastructure
Write-Host "`nDeploying infrastructure..." -ForegroundColor Yellow
$deploymentName = "valheim-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

try {
    az deployment sub create `
        --location $Location `
        --name $deploymentName `
        --template-file "infrastructure/main.bicep" `
        --parameters resourceGroupName=$ResourceGroupName `
                     location=$Location `
                     discordBotToken=$DiscordBotToken `
                     serverPassword=$ServerPassword `
                     serverName=$ServerName `
                     autoShutdownMinutes=$AutoShutdownMinutes `
        --output json | Out-Null
    
    Write-Host "Infrastructure deployed successfully" -ForegroundColor Green
} catch {
    Write-Host "Error deploying infrastructure: $_" -ForegroundColor Red
    exit 1
}

# Get deployment outputs
Write-Host "`nRetrieving deployment outputs..." -ForegroundColor Yellow
$outputs = az deployment sub show `
    --name $deploymentName `
    --query "properties.outputs" `
    --output json | ConvertFrom-Json

$functionAppName = $outputs.functionAppName.value
$functionAppUrl = $outputs.functionAppUrl.value
$storageAccountName = $outputs.storageAccountName.value

Write-Host "Deployment outputs:" -ForegroundColor Green
Write-Host "  Function App: $functionAppName"
Write-Host "  Function App URL: $functionAppUrl"
Write-Host "  Storage Account: $storageAccountName"

# Deploy Function App code
Write-Host "`nDeploying Function App code..." -ForegroundColor Yellow
Push-Location functions

try {
    # Check for .NET SDK
    $dotnetVersion = dotnet --version
    if (-not $dotnetVersion) {
        throw ".NET SDK not found. Please install from https://dotnet.microsoft.com/download"
    }
    Write-Host ".NET SDK version: $dotnetVersion" -ForegroundColor Green
    
    # Restore and build
    Write-Host "Restoring NuGet packages..." -ForegroundColor Yellow
    dotnet restore
    
    Write-Host "Building project..." -ForegroundColor Yellow
    dotnet build --configuration Release
    
    # Deploy to Azure
    Write-Host "Publishing Function App..." -ForegroundColor Yellow
    func azure functionapp publish $functionAppName --dotnet-isolated
    
    Write-Host "Function App deployed successfully" -ForegroundColor Green
} catch {
    Write-Host "Error deploying Function App: $_" -ForegroundColor Red
    Pop-Location
    exit 1
} finally {
    Pop-Location
}

# Set Function App environment variables
Write-Host "`nConfiguring Function App settings..." -ForegroundColor Yellow
az functionapp config appsettings set `
    --resource-group $ResourceGroupName `
    --name $functionAppName `
    --settings "SUBSCRIPTION_ID=$SubscriptionId" `
    --output none

# Register Discord commands
Write-Host "`nDiscord Bot Setup:" -ForegroundColor Cyan
Write-Host "1. Go to https://discord.com/developers/applications"
Write-Host "2. Select your application"
Write-Host "3. Go to 'General Information' and copy your Application ID"
Write-Host "4. Register slash commands using:"
Write-Host "   POST https://discord.com/api/v10/applications/{APPLICATION_ID}/commands"
Write-Host ""
Write-Host "Command JSON:"
$commandsJson = @'
[
  {
    "name": "valheim",
    "description": "Control the Valheim server",
    "options": [
      {
        "name": "start",
        "description": "Start the Valheim server",
        "type": 1
      },
      {
        "name": "stop",
        "description": "Stop the Valheim server",
        "type": 1
      },
      {
        "name": "status",
        "description": "Check server status",
        "type": 1
      }
    ]
  }
]
'@
Write-Host $commandsJson -ForegroundColor Yellow
Write-Host ""
Write-Host "5. Set the interaction endpoint URL to: $functionAppUrl/api/DiscordBot" -ForegroundColor Yellow

Write-Host "`nDeployment completed!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Complete Discord bot setup (see above)"
Write-Host "2. Test the server: /valheim start"
Write-Host "3. Monitor costs in Azure Portal"
