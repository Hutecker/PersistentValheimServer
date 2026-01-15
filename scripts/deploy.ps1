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
    [int]$MonthlyBudgetLimit = 30,
    
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
    
    # NOTE: We do NOT delete role assignments here!
    # ARM owns role assignments - deleting them outside ARM causes conflicts.
    # The Bicep template now uses:
    # - Explicit dependsOn to wait for Function App identity
    # - Fully-qualified guid() names for deterministic assignment IDs
    # This ensures role assignments are stable across redeployments.
    
    # Delete existing budget if it exists (budget time periods can't be updated)
    Write-Host "Checking for existing budget..." -ForegroundColor Gray
    $existingBudget = az consumption budget show --budget-name "valheim-monthly-budget" --resource-group $ResourceGroupName --output json 2>$null
    if ($existingBudget) {
        Write-Host "Deleting existing budget (time period can't be updated)..." -ForegroundColor Yellow
        az consumption budget delete --budget-name "valheim-monthly-budget" --resource-group $ResourceGroupName --output none 2>$null
        Write-Host "✅ Budget deleted" -ForegroundColor Green
    }
}

Write-Host "`nDeploying infrastructure..." -ForegroundColor Yellow
$deploymentName = "valheim-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "Using Incremental deployment mode (preserves existing resources not in template)" -ForegroundColor Gray

try {
        # Build parameters for Azure CLI - pass each parameter separately
        $azParams = @(
            'deployment', 'group', 'create',
            '--resource-group', $ResourceGroupName,
            '--name', $deploymentName,
            '--template-file', 'infrastructure/main.bicep',
            '--mode', 'Incremental',
            '--parameters', "resourceGroupName=$ResourceGroupName",
            '--parameters', "location=$Location",
            '--parameters', "discordBotToken=$DiscordBotToken",
            '--parameters', "discordPublicKey=$DiscordPublicKey",
            '--parameters', "serverPassword=$ServerPassword",
            '--parameters', "serverName=$ServerName",
            '--parameters', "autoShutdownMinutes=$AutoShutdownMinutes",
            '--parameters', "monthlyBudgetLimit=$MonthlyBudgetLimit"
        )
        
        if (-not [string]::IsNullOrWhiteSpace($BudgetAlertEmail)) {
            $azParams += '--parameters'
            $azParams += "budgetAlertEmail=$BudgetAlertEmail"
            # Budget start date must be first day of current month for monthly time grain
            $currentMonthStart = (Get-Date -Day 1).ToString("yyyy-MM-dd")
            Write-Host "  Budget start date: $currentMonthStart" -ForegroundColor Gray
            $azParams += '--parameters'
            $azParams += "budgetStartDate=$currentMonthStart"
        }
        
        $azParams += '--output'
        $azParams += 'json'
        
        # Execute Azure CLI command
        $deployOutput = & az $azParams 2>&1

        $deployOutputString = $deployOutput | Out-String
        
        # Check for role assignment errors - these should be rare with the fixed Bicep template
        if ($deployOutputString -match "RoleAssignmentUpdateNotPermitted") {
            Write-Host "`n❌ Role assignment update error detected" -ForegroundColor Red
            Write-Host "This is unexpected with the current Bicep template." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "If this is the first deployment after updating the template:" -ForegroundColor Yellow
            Write-Host "  The role assignment GUIDs have changed. You need to manually delete" -ForegroundColor Gray
            Write-Host "  the old role assignments in Azure Portal, then redeploy." -ForegroundColor Gray
            Write-Host ""
            Write-Host "Steps to fix:" -ForegroundColor Yellow
            Write-Host "  1. Go to Azure Portal -> Resource Group -> Access control (IAM)" -ForegroundColor Gray
            Write-Host "  2. Delete role assignments for 'valheim-func' managed identity" -ForegroundColor Gray
            Write-Host "  3. Run this deployment again" -ForegroundColor Gray
            throw "Deployment failed due to role assignment conflicts."
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
    
    # Function to find func command
    function Find-FuncCommand {
        # Try direct command first
        $funcCmd = Get-Command func -ErrorAction SilentlyContinue
        if ($funcCmd) {
            return "func"
        }
        
        # Check common npm global install locations (only if npm is available)
        try {
            $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
            if ($npmCmd) {
                $npmGlobalPath = npm root -g 2>$null
                if ($npmGlobalPath -and (Test-Path $npmGlobalPath)) {
                    $funcPath = Join-Path (Split-Path $npmGlobalPath) "func.cmd"
                    if (Test-Path $funcPath) {
                        return $funcPath
                    }
                }
            }
        } catch {
            # npm not available, continue checking other locations
        }
        
        # Check AppData\npm (Windows default)
        $appDataNpm = Join-Path $env:APPDATA "npm\func.cmd"
        if (Test-Path $appDataNpm) {
            return $appDataNpm
        }
        
        # Check Program Files npm
        $programFilesNpm = "${env:ProgramFiles}\nodejs\func.cmd"
        if (Test-Path $programFilesNpm) {
            return $programFilesNpm
        }
        
        return $null
    }
    
    $funcCmd = Find-FuncCommand
    $useFuncDeploy = $false
    
    if (-not $funcCmd) {
        Write-Host "⚠️  Azure Functions Core Tools not found." -ForegroundColor Yellow
        
        # Check for npm/node before trying to install
        try {
            $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
            $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
            if ($nodeCmd -and $npmCmd) {
                Write-Host "   Attempting to install via npm..." -ForegroundColor Gray
                $installOutput = npm install -g azure-functions-core-tools@4 --unsafe-perm true 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Azure Functions Core Tools installed" -ForegroundColor Green
                    
                    # Refresh PATH and try to find func again
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                    $funcCmd = Find-FuncCommand
                }
            }
        } catch {
            # npm/node not available, skip installation
        }
        
        if (-not $funcCmd) {
            Write-Host "⚠️  Could not install or find Azure Functions Core Tools" -ForegroundColor Yellow
            Write-Host "   Falling back to Azure CLI ZIP deployment method..." -ForegroundColor Gray
            Write-Host "   (For best results with Flex Consumption, install: npm install -g azure-functions-core-tools@4)" -ForegroundColor Gray
            $useFuncDeploy = $false
        } else {
            $useFuncDeploy = $true
        }
    } else {
        $useFuncDeploy = $true
    }
    
    if ($useFuncDeploy) {
        # Verify func works
        try {
            $funcVersion = & $funcCmd --version 2>$null
            if ($funcVersion) {
                Write-Host "✅ Azure Functions Core Tools version: $funcVersion" -ForegroundColor Green
            } else {
                Write-Host "⚠️  Could not verify func version, falling back to ZIP deployment..." -ForegroundColor Yellow
                $useFuncDeploy = $false
            }
        } catch {
            Write-Host "⚠️  Error running func command, falling back to ZIP deployment..." -ForegroundColor Yellow
            $useFuncDeploy = $false
        }
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
    
    if ($useFuncDeploy) {
        Write-Host "`nDeploying Function App using One Deploy (Flex Consumption)..." -ForegroundColor Yellow
        Write-Host "  Function App: $functionAppName" -ForegroundColor Gray
        Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  This uses 'func azure functionapp publish' which properly handles Flex Consumption" -ForegroundColor Gray
        Write-Host "  The deployment will use the blob container configured in the Function App" -ForegroundColor Gray
        Write-Host ""
        
        # Use func azure functionapp publish for proper One Deploy
        & $funcCmd azure functionapp publish $functionAppName --dotnet-isolated --csharp
        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠️  Deployment may have failed. Trying alternative method..." -ForegroundColor Yellow
            
            # Try alternative: use func with explicit publish directory
            Write-Host "  Trying with explicit publish directory..." -ForegroundColor Gray
            Push-Location $publishDir
            & $funcCmd azure functionapp publish $functionAppName --dotnet-isolated --csharp
            $deployExitCode = $LASTEXITCODE
            Pop-Location
            
            if ($deployExitCode -ne 0) {
                Write-Host "⚠️  func deployment failed, falling back to ZIP deployment..." -ForegroundColor Yellow
                $useFuncDeploy = $false
            }
        }
    }
    
    if (-not $useFuncDeploy) {
        Write-Host "`nDeploying Function App using Azure CLI ZIP deployment..." -ForegroundColor Yellow
        Write-Host "  Function App: $functionAppName" -ForegroundColor Gray
        Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
        Write-Host ""
        
        # Get absolute paths
        $publishDirFull = (Resolve-Path $publishDir).Path
        $zipPath = Join-Path $env:TEMP "valheim-func-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
        
        Write-Host "  Creating deployment package..." -ForegroundColor Gray
        Write-Host "    Source: $publishDirFull" -ForegroundColor DarkGray
        Write-Host "    ZIP: $zipPath" -ForegroundColor DarkGray
        
        # Remove existing ZIP if present
        if (Test-Path $zipPath) {
            Remove-Item $zipPath -Force
        }
        
        # Create ZIP using .NET Compression (works on Windows without external tools)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        try {
            [System.IO.Compression.ZipFile]::CreateFromDirectory($publishDirFull, $zipPath)
        } catch {
            Write-Host "❌ Failed to create ZIP: $_" -ForegroundColor Red
            throw "Failed to create deployment ZIP package: $_"
        }
        
        if (-not (Test-Path $zipPath)) {
            throw "Failed to create deployment ZIP package - file not found after creation"
        }
        
        $zipSize = (Get-Item $zipPath).Length / 1MB
        Write-Host "  ✅ ZIP created ($([math]::Round($zipSize, 2)) MB)" -ForegroundColor Green
        
        Write-Host "  Uploading deployment package to blob storage..." -ForegroundColor Gray
        
        # Get the function storage account name from outputs
        $functionStorageAccountName = $outputs.functionStorageAccountName.value
        
        # Calculate deployment container name (matches Bicep logic: first 32 chars of function app name, lowercased)
        $containerNamePrefix = ($functionAppName).ToLower()
        if ($containerNamePrefix.Length -gt 32) {
            $containerNamePrefix = $containerNamePrefix.Substring(0, 32)
        }
        $deploymentContainerName = "app-package-$containerNamePrefix"
        
        Write-Host "    Storage Account: $functionStorageAccountName" -ForegroundColor DarkGray
        Write-Host "    Container: $deploymentContainerName" -ForegroundColor DarkGray
        
        # Get storage account key
        $storageAccountKey = az storage account keys list --account-name $functionStorageAccountName --resource-group $ResourceGroupName --query "[0].value" --output tsv
        if (-not $storageAccountKey) {
            Write-Host "❌ Failed to get storage account key" -ForegroundColor Red
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            throw "Function App deployment failed - could not access storage account"
        }
        
        # Upload to blob container
        Write-Host "  Uploading ZIP to blob container..." -ForegroundColor Gray
        az storage blob upload --account-name $functionStorageAccountName --account-key $storageAccountKey --container-name $deploymentContainerName --name "deploy.zip" --file $zipPath --overwrite --output none
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to upload to blob storage. Error code: $LASTEXITCODE" -ForegroundColor Red
            Write-Host "   Trying to create container if it doesn't exist..." -ForegroundColor Yellow
            az storage container create --account-name $functionStorageAccountName --account-key $storageAccountKey --name $deploymentContainerName --output none 2>$null
            az storage blob upload --account-name $functionStorageAccountName --account-key $storageAccountKey --container-name $deploymentContainerName --name "deploy.zip" --file $zipPath --overwrite --output none
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Failed to upload to blob storage after container creation. Error code: $LASTEXITCODE" -ForegroundColor Red
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                throw "Function App deployment failed - blob upload failed"
            }
        }
        
        # Construct blob URL (Flex Consumption uses this format)
        $blobUrl = "https://${functionStorageAccountName}.blob.core.windows.net/${deploymentContainerName}/deploy.zip"
        
        # Configure Function App to use the deployment package
        Write-Host "  Configuring Function App deployment source..." -ForegroundColor Gray
        az functionapp config appsettings set --name $functionAppName --resource-group $ResourceGroupName --settings "WEBSITE_RUN_FROM_PACKAGE=$blobUrl" --output none
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to configure Function App. Error code: $LASTEXITCODE" -ForegroundColor Red
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            throw "Function App deployment failed - configuration failed"
        }
        
        Write-Host "  ✅ Deployment package uploaded and configured" -ForegroundColor Green
        Write-Host "  Note: Function App may take 1-2 minutes to restart and load the new package" -ForegroundColor Gray
        
        # Clean up ZIP
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Write-Host "  ✅ Deployment package uploaded successfully" -ForegroundColor Green
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
