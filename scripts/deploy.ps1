# Deployment Script for Valheim Server on Azure
# Infrastructure is managed via Bicep (infrastructure/main.bicep)
# This script deploys the Bicep template and then builds/deploys Function App code
#
# If you get an execution policy error, run this first:
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Or run: powershell.exe -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 ...

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$true)]
    [string]$DiscordBotToken,
    
    [Parameter(Mandatory=$true)]
    [string]$DiscordPublicKey,
    
    [Parameter(Mandatory=$true)]
    [string]$ServerPassword,
    
    [Parameter(Mandatory=$false)]
    [string]$ServerName = "Valheim Server",
    
    [Parameter(Mandatory=$false)]
    [int]$AutoShutdownMinutes = 120,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "",
    
    [Parameter(Mandatory=$false)]
    [decimal]$MonthlyBudgetLimit = 30.0,
    
    [Parameter(Mandatory=$false)]
    [string]$BudgetAlertEmail = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Valheim Server Azure Deployment" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

try {
    $azVersion = az version --output json | ConvertFrom-Json
    Write-Host "Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green
} catch {
    Write-Host "Error: Azure CLI not found. Please install from https://aka.ms/installazurecliwindows" -ForegroundColor Red
    exit 1
}

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

if (-not $SubscriptionId) {
    $account = az account show --output json | ConvertFrom-Json
    $SubscriptionId = $account.id
}

Write-Host "`nChecking resource group..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroupName --output tsv
if ($rgExists -eq "false") {
    Write-Host "Creating resource group: $ResourceGroupName" -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location --output none
    Write-Host "Resource group created" -ForegroundColor Green
} else {
    Write-Host "Resource group already exists" -ForegroundColor Green
}

Write-Host "`nDeploying infrastructure..." -ForegroundColor Yellow
$deploymentName = "valheim-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "Using Incremental deployment mode (preserves existing resources not in template)" -ForegroundColor Gray

try {
        $deployParams = @(
            "resourceGroupName=$ResourceGroupName",
            "location=$Location",
            "discordBotToken=$DiscordBotToken",
            "discordPublicKey=$DiscordPublicKey",
            "serverPassword=$ServerPassword",
            "serverName=$ServerName",
            "autoShutdownMinutes=$AutoShutdownMinutes",
            "monthlyBudgetLimit=$MonthlyBudgetLimit"
        )
        
        if (-not [string]::IsNullOrWhiteSpace($BudgetAlertEmail)) {
            $deployParams += "budgetAlertEmail=$BudgetAlertEmail"
        }
        
        $deployOutput = az deployment group create `
            --resource-group $ResourceGroupName `
            --name $deploymentName `
            --template-file "infrastructure/main.bicep" `
            --mode Incremental `
            --parameters $deployParams `
            --output json 2>&1

    $deployOutputString = $deployOutput | Out-String
    if ($deployOutputString -match "RoleAssignmentUpdateNotPermitted") {
        Write-Host "`n⚠️  Role assignment update errors detected" -ForegroundColor Yellow
        Write-Host "This happens when old role assignments exist from previous deployments." -ForegroundColor Gray
        Write-Host "Role assignments are now managed in Bicep, but old ones need to be cleaned up first." -ForegroundColor Gray
        Write-Host ""
        Write-Host "To fix this, delete the conflicting role assignments in the Azure Portal:" -ForegroundColor Yellow
        Write-Host "  1. Go to the resource group: $ResourceGroupName" -ForegroundColor Gray
        Write-Host "  2. Navigate to 'Access control (IAM)'" -ForegroundColor Gray
        Write-Host "  3. Remove any role assignments for the Function App's managed identity" -ForegroundColor Gray
        Write-Host "  4. Retry the deployment" -ForegroundColor Gray
        throw "Deployment failed due to role assignment conflicts. Clean up old role assignments and retry."
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed with exit code $LASTEXITCODE"
    }
    
    Write-Host "Infrastructure deployed successfully" -ForegroundColor Green
} catch {
    Write-Host "Error deploying infrastructure: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nRetrieving deployment outputs..." -ForegroundColor Yellow
$outputs = az deployment group show `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --query "properties.outputs" `
    --output json | ConvertFrom-Json

$functionAppName = $outputs.functionAppName.value
$functionAppUrl = $outputs.functionAppUrl.value

Write-Host "Deployment outputs:" -ForegroundColor Green
Write-Host "  Function App: $functionAppName"
Write-Host "  Function App URL: $functionAppUrl"
Write-Host "  Storage Account: $($outputs.storageAccountName.value)"
Write-Host "  Key Vault: $($outputs.keyVaultName.value)"
if ($outputs.budgetConfigured.value) {
    Write-Host "  Budget: $($outputs.budgetLimit.value) (alerts configured)" -ForegroundColor Green
} elseif (-not [string]::IsNullOrWhiteSpace($BudgetAlertEmail)) {
    Write-Host "  Budget: Not configured (email may be invalid)" -ForegroundColor Yellow
}

Write-Host "`nDeploying Function App code..." -ForegroundColor Yellow
Push-Location functions

try {
    # Check for .NET SDK
    $dotnetVersion = dotnet --version
    if (-not $dotnetVersion) {
        throw ".NET SDK not found. Please install from https://dotnet.microsoft.com/download"
    }
    Write-Host ".NET SDK version: $dotnetVersion" -ForegroundColor Green
    
    Write-Host "Restoring NuGet packages..." -ForegroundColor Yellow
    dotnet restore
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to restore NuGet packages"
    }
    
    Write-Host "Building project..." -ForegroundColor Yellow
    dotnet build --configuration Release
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build project"
    }
    
    if (Test-Path "ValheimServerFunctions.Tests\ValheimServerFunctions.Tests.csproj") {
        Write-Host "`nRunning tests..." -ForegroundColor Yellow
        try {
            $testOutput = dotnet test ValheimServerFunctions.Tests\ValheimServerFunctions.Tests.csproj --configuration Release --verbosity minimal 2>&1
            $testExitCode = $LASTEXITCODE
            
            if ($testExitCode -eq 0) {
                Write-Host "✅ All tests passed!" -ForegroundColor Green
            } else {
                Write-Host "⚠️  Some tests failed. Exit code: $testExitCode" -ForegroundColor Yellow
                Write-Host "   Test output:" -ForegroundColor Gray
                $testOutput | Where-Object { $_ -notmatch "warning NU1603" } | Select-Object -Last 10 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
                Write-Host "   Continuing with deployment. Fix test issues before next deployment." -ForegroundColor Gray
            }
        } catch {
            Write-Host "⚠️  Could not run tests: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "   Continuing with deployment..." -ForegroundColor Gray
        }
    }
    
    # Check for Azure Functions Core Tools (required for Flex Consumption One Deploy)
    Write-Host "Checking for Azure Functions Core Tools..." -ForegroundColor Yellow
    $funcVersion = func --version 2>$null
    if (-not $funcVersion) {
        Write-Host "⚠️  Azure Functions Core Tools not found. Installing via npm..." -ForegroundColor Yellow
        Write-Host "   This is required for Flex Consumption deployment (One Deploy method)" -ForegroundColor Gray
        
        # Check for npm/node
        $nodeVersion = node --version 2>$null
        if (-not $nodeVersion) {
            Write-Host "❌ Node.js not found. Please install Node.js from https://nodejs.org/" -ForegroundColor Red
            Write-Host "   Then run: npm install -g azure-functions-core-tools@4 --unsafe-perm true" -ForegroundColor Yellow
            throw "Azure Functions Core Tools required for deployment"
        }
        
        Write-Host "   Installing Azure Functions Core Tools..." -ForegroundColor Gray
        npm install -g azure-functions-core-tools@4 --unsafe-perm true
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install Azure Functions Core Tools"
        }
        Write-Host "✅ Azure Functions Core Tools installed" -ForegroundColor Green
    } else {
        Write-Host "✅ Azure Functions Core Tools version: $funcVersion" -ForegroundColor Green
    }
    
    Write-Host "`nBuilding and publishing project..." -ForegroundColor Yellow
    dotnet publish --configuration Release --output "bin\Release\net8.0\publish"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to publish project"
    }
    
    Write-Host "Verifying published files..." -ForegroundColor Yellow
    $publishDir = "bin\Release\net8.0\publish"
    $requiredFiles = @("host.json", "ValheimServerFunctions.dll")
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $publishDir $file
        if (-not (Test-Path $filePath)) {
            Write-Host "❌ Required file missing: $file" -ForegroundColor Red
            throw "Required file missing from publish output: $file"
        }
    }
    Write-Host "✅ All required files present" -ForegroundColor Green
    
    Write-Host "`nDeploying Function App using One Deploy (Flex Consumption)..." -ForegroundColor Yellow
    Write-Host "  Function App: $functionAppName" -ForegroundColor Gray
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  This uses 'func azure functionapp publish' which properly handles Flex Consumption" -ForegroundColor Gray
    Write-Host "  The deployment will use the blob container configured in the Function App" -ForegroundColor Gray
    Write-Host ""
    
    # Use func azure functionapp publish for proper One Deploy
    func azure functionapp publish $functionAppName --dotnet-isolated --csharp
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  Deployment may have failed. Checking status..." -ForegroundColor Yellow
        
        # Try alternative: use func with explicit publish directory
        Write-Host "  Trying alternative deployment method..." -ForegroundColor Gray
        Push-Location $publishDir
        func azure functionapp publish $functionAppName --dotnet-isolated --csharp
        $deployExitCode = $LASTEXITCODE
        Pop-Location
        
        if ($deployExitCode -ne 0) {
            Write-Host "❌ Deployment failed. Error code: $deployExitCode" -ForegroundColor Red
            Write-Host "`nTroubleshooting tips:" -ForegroundColor Yellow
            Write-Host "  1. Ensure you're logged in: az login" -ForegroundColor Gray
            Write-Host "  2. Check Function App exists: az functionapp show --name $functionAppName --resource-group $ResourceGroupName" -ForegroundColor Gray
            Write-Host "  3. Verify deployment storage is configured in the Function App" -ForegroundColor Gray
            Write-Host "  4. Check Application Insights logs for errors" -ForegroundColor Gray
            throw "Function App deployment failed"
        }
    }
    
    Write-Host "`n✅ Deployment completed successfully!" -ForegroundColor Green
    Write-Host "`nVerifying functions..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    
    # Wait and retry checking for functions (they may take time to appear)
    $maxRetries = 6
    $retryCount = 0
    $functions = $null
    
    while ($retryCount -lt $maxRetries) {
        $functions = az functionapp function list --name $functionAppName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        
        if ($functions -and $functions.Count -gt 0) {
            Write-Host "✅ Function App deployed successfully! Found $($functions.Count) function(s):" -ForegroundColor Green
            foreach ($func in $functions) {
                Write-Host "  ✅ $($func.name)" -ForegroundColor Green
            }
            break
        }
        
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Host "  Waiting for functions to appear... (attempt $retryCount/$maxRetries)" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    }
    
    if (-not $functions -or $functions.Count -eq 0) {
        Write-Host "⚠️  Functions not yet visible in Azure CLI" -ForegroundColor Yellow
        Write-Host "   This is normal - functions may take 1-2 minutes to appear" -ForegroundColor Gray
        Write-Host "   Check Azure Portal: https://portal.azure.com/#@/resource/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$functionAppName" -ForegroundColor Gray
        Write-Host "   Or run: az functionapp function list --name $functionAppName --resource-group $ResourceGroupName" -ForegroundColor Gray
    }
    
    Pop-Location
} catch {
    Write-Host "Error deploying Function App: $_" -ForegroundColor Red
    Pop-Location
    Write-Host "`nNote: Infrastructure is deployed. You can deploy Function App code manually later." -ForegroundColor Yellow
}

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
