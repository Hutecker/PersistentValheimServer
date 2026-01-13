# Deployment Script for Valheim Server on Azure
# This script automates the deployment of all infrastructure components
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
    [string]$SubscriptionId = ""
)

# Get script directory for cleanup script reference
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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

# Create resource group if it doesn't exist
Write-Host "`nChecking resource group..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroupName --output tsv
if ($rgExists -eq "false") {
    Write-Host "Creating resource group: $ResourceGroupName" -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location --output none
    Write-Host "Resource group created" -ForegroundColor Green
} else {
    Write-Host "Resource group already exists" -ForegroundColor Green
}

# Deploy infrastructure at resource group scope
Write-Host "`nDeploying infrastructure..." -ForegroundColor Yellow
$deploymentName = "valheim-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# Check for previous failed deployments with role assignment issues
Write-Host "Checking for previous failed deployments..." -ForegroundColor Yellow
$recentFailed = az deployment group list --resource-group $ResourceGroupName --query "[?properties.provisioningState=='Failed' && contains(properties.error.code, 'RoleAssignment')].name" -o tsv 2>$null | Select-Object -First 1
if ($recentFailed) {
    Write-Host "  Found failed deployment with role assignment issues: $recentFailed" -ForegroundColor Yellow
    Write-Host "  This deployment will be skipped - using Incremental mode" -ForegroundColor Gray
}

# Always use Incremental mode to avoid conflicts with existing resources
# This ensures resources not in the template are left alone
Write-Host "Using Incremental deployment mode (preserves existing resources not in template)" -ForegroundColor Gray

try {
    $deployOutput = az deployment group create `
        --resource-group $ResourceGroupName `
        --name $deploymentName `
        --template-file "infrastructure/main.bicep" `
        --mode Incremental `
        --parameters resourceGroupName=$ResourceGroupName `
                     location=$Location `
                     discordBotToken=$DiscordBotToken `
                     discordPublicKey=$DiscordPublicKey `
                     serverPassword=$ServerPassword `
                     serverName=$ServerName `
                     autoShutdownMinutes=$AutoShutdownMinutes `
        --output json 2>&1
    
    # Check for role assignment errors specifically
    $deployOutputString = $deployOutput | Out-String
    if ($deployOutputString -match "RoleAssignmentUpdateNotPermitted") {
        Write-Host "`n⚠️  Role assignment update errors detected" -ForegroundColor Yellow
        Write-Host "This happens when old role assignments exist from previous deployments." -ForegroundColor Gray
        Write-Host "Role assignments are now managed via Azure CLI, not Bicep." -ForegroundColor Gray
        Write-Host ""
        Write-Host "Attempting to clean up old role assignments..." -ForegroundColor Yellow
        
        # Try to clean up old role assignments automatically
        $cleanupScript = Join-Path $scriptDir "cleanup-role-assignments.ps1"
        if (Test-Path $cleanupScript) {
            Write-Host "Running cleanup script..." -ForegroundColor Gray
            & $cleanupScript -ResourceGroupName $ResourceGroupName -Force
        } else {
            Write-Host "Cleanup script not found at: $cleanupScript" -ForegroundColor Yellow
            Write-Host "Please run manually: .\scripts\cleanup-role-assignments.ps1 -ResourceGroupName $ResourceGroupName -Force" -ForegroundColor Yellow
        }
        
        Write-Host "`nRetrying deployment..." -ForegroundColor Yellow
        $deployOutput = az deployment group create `
            --resource-group $ResourceGroupName `
            --name $deploymentName `
            --template-file "infrastructure/main.bicep" `
            --mode Incremental `
            --parameters resourceGroupName=$ResourceGroupName `
                         location=$Location `
                         discordBotToken=$DiscordBotToken `
                         discordPublicKey=$DiscordPublicKey `
                         serverPassword=$ServerPassword `
                         serverName=$ServerName `
                         autoShutdownMinutes=$AutoShutdownMinutes `
            --output json 2>&1
        
        $deployOutputString = $deployOutput | Out-String
        if ($deployOutputString -match "RoleAssignmentUpdateNotPermitted") {
            Write-Host "`n❌ Still getting role assignment errors after cleanup." -ForegroundColor Red
            Write-Host "Please run this manually and then retry deployment:" -ForegroundColor Yellow
            Write-Host "  .\scripts\cleanup-role-assignments.ps1 -ResourceGroupName $ResourceGroupName -Force" -ForegroundColor Gray
            throw "Deployment failed due to role assignment conflicts"
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed with exit code $LASTEXITCODE"
    }
    
    Write-Host "Infrastructure deployed successfully" -ForegroundColor Green
    
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "Error deploying infrastructure: $_" -ForegroundColor Red
    exit 1
}

# Get deployment outputs
Write-Host "`nRetrieving deployment outputs..." -ForegroundColor Yellow
$outputs = az deployment group show `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --query "properties.outputs" `
    --output json | ConvertFrom-Json

# Use standardized Function App name (not from Bicep outputs)
$functionAppName = "valheim-func-flex"
$storageAccountName = $outputs.storageAccountName.value
$functionStorageAccountName = $outputs.functionStorageAccountName.value

Write-Host "Deployment outputs:" -ForegroundColor Green
Write-Host "  Function App Name: $functionAppName (standardized)"
Write-Host "  Storage Account: $storageAccountName"
Write-Host "  Function Storage Account: $functionStorageAccountName"

# Check for existing Flex Consumption Function App
Write-Host "`nChecking for existing Flex Consumption Function App..." -ForegroundColor Yellow
$existingFlexApp = az functionapp show --name $functionAppName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json

if ($existingFlexApp) {
    Write-Host "Found existing Flex Consumption Function App: $functionAppName" -ForegroundColor Green
} else {
    Write-Host "Flex Consumption Function App not found. Creating new one..." -ForegroundColor Yellow
    Write-Host "  Creating: $functionAppName" -ForegroundColor Gray
    
    az functionapp create `
        --name $functionAppName `
        --resource-group $ResourceGroupName `
        --storage-account $functionStorageAccountName `
        --flexconsumption-location $Location `
        --runtime "dotnet-isolated" `
        --runtime-version "8" `
        --functions-version "4" `
        --output none 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Flex Consumption Function App created successfully: $functionAppName" -ForegroundColor Green
    } else {
        throw "Failed to create Flex Consumption Function App. Please check Azure CLI output above."
    }
}

# Enable System-Assigned Managed Identity (if not already enabled)
Write-Host "Enabling managed identity..." -ForegroundColor Yellow
az functionapp identity assign --name $functionAppName --resource-group $ResourceGroupName --output none 2>&1 | Out-Null

# Get managed identity principal ID
$principalId = az functionapp identity show --name $functionAppName --resource-group $ResourceGroupName --query "principalId" -o tsv 2>$null

if ($principalId) {
    $keyVaultName = $outputs.keyVaultName.value
    
    # Check and create missing role assignments
    Write-Host "Verifying role assignments..." -ForegroundColor Yellow
    
    # Key Vault access
    $kvAssignment = az role assignment list --assignee $principalId --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$keyVaultName" --query "[?roleDefinitionId=='/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6']" -o tsv 2>$null
    if (-not $kvAssignment) {
        Write-Host "Granting Key Vault access..." -ForegroundColor Yellow
        az role assignment create `
            --role "Key Vault Secrets User" `
            --assignee-object-id $principalId `
            --assignee-principal-type ServicePrincipal `
            --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$keyVaultName" `
            --output none 2>&1 | Out-Null
    }
    
    # Container Instance access
    $aciAssignment = az role assignment list --assignee $principalId --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" --query "[?roleDefinitionId=='/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/5d977122-f97e-4b4d-a52f-6b43003ddb4d']" -o tsv 2>$null
    if (-not $aciAssignment) {
        Write-Host "Granting Container Instance access..." -ForegroundColor Yellow
        az role assignment create `
            --role "Azure Container Instances Contributor Role" `
            --assignee-object-id $principalId `
            --assignee-principal-type ServicePrincipal `
            --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" `
            --output none 2>&1 | Out-Null
    }
    
    # Storage Account access
    $saAssignment = az role assignment list --assignee $principalId --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName" --query "[?roleDefinitionId=='/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab']" -o tsv 2>$null
    if (-not $saAssignment) {
        Write-Host "Granting Storage Account access..." -ForegroundColor Yellow
        az role assignment create `
            --role "Storage Account Contributor" `
            --assignee-object-id $principalId `
            --assignee-principal-type ServicePrincipal `
            --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName" `
            --output none 2>&1 | Out-Null
    }
    
    # Storage File access
    $fileAssignment = az role assignment list --assignee $principalId --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName" --query "[?roleDefinitionId=='/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/a7264617-510b-434b-a828-9731dc254ea7']" -o tsv 2>$null
    if (-not $fileAssignment) {
        Write-Host "Granting Storage File access..." -ForegroundColor Yellow
        az role assignment create `
            --role "Storage File Data SMB Share Elevated Contributor" `
            --assignee-object-id $principalId `
            --assignee-principal-type ServicePrincipal `
            --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName" `
            --output none 2>&1 | Out-Null
    }
    
    # Function Storage Account access
    $funcStorageAssignment = az role assignment list --assignee $principalId --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$functionStorageAccountName" --query "[?roleDefinitionId=='/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe']" -o tsv 2>$null
    if (-not $funcStorageAssignment) {
        Write-Host "Granting Function Storage Account access..." -ForegroundColor Yellow
        az role assignment create `
            --role "Storage Blob Data Contributor" `
            --assignee-object-id $principalId `
            --assignee-principal-type ServicePrincipal `
            --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$functionStorageAccountName" `
            --output none 2>&1 | Out-Null
    }
    
    Write-Host "Role assignments verified" -ForegroundColor Green
} else {
    Write-Host "Warning: Could not retrieve managed identity principal ID" -ForegroundColor Yellow
}

Write-Host "`nUsing Function App: $functionAppName" -ForegroundColor Cyan

$functionAppUrl = "https://$functionAppName.azurewebsites.net"

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
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to restore NuGet packages"
    }
    
    Write-Host "Building project..." -ForegroundColor Yellow
    dotnet build --configuration Release
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build project"
    }
    
    # Publish project (required to generate functions.metadata)
    Write-Host "Publishing project..." -ForegroundColor Yellow
    dotnet publish --configuration Release --no-build --output "bin\Release\net8.0\publish" --self-contained false
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to publish project"
    }
    
    # Verify critical files exist
    Write-Host "Verifying published files..." -ForegroundColor Yellow
    $publishDir = "bin\Release\net8.0\publish"
    $requiredFiles = @("host.json", "ValheimServerFunctions.dll", "functions.metadata", "extensions.json")
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $publishDir $file
        if (-not (Test-Path $filePath)) {
            Write-Host "❌ Required file missing: $file" -ForegroundColor Red
            throw "Required file missing from publish output: $file"
        }
    }
    Write-Host "✅ All required files present" -ForegroundColor Green
    
    # Deploy Function App code using Azure CLI (no func tools needed)
    Write-Host "Creating deployment package..." -ForegroundColor Yellow
    
    # Create a zip file with the published output
    $zipFile = "..\function-app-deploy.zip"
    
    # Remove old zip if exists
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force
    }
    
    # Create zip file with Linux-compatible paths (forward slashes)
    # Windows Compress-Archive uses backslashes which Linux can't read properly
    Write-Host "Creating deployment ZIP with Linux-compatible paths..." -ForegroundColor Yellow
    Write-Host "  Source: $publishDir" -ForegroundColor Gray
    
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    $publishDirResolved = Resolve-Path $publishDir
    $zipPath = (Resolve-Path "..").Path + "\function-app-deploy.zip"
    $zipStream = [System.IO.File]::Create($zipPath)
    $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    
    $files = Get-ChildItem $publishDirResolved -Recurse -File
    foreach ($file in $files) {
        # Use forward slashes for Linux compatibility
        $relativePath = $file.FullName.Substring($publishDirResolved.Path.Length + 1).Replace("\", "/")
        $entry = $archive.CreateEntry($relativePath)
        $entryStream = $entry.Open()
        $fileStream = [System.IO.File]::OpenRead($file.FullName)
        $fileStream.CopyTo($entryStream)
        $fileStream.Close()
        $entryStream.Close()
    }
    
    $archive.Dispose()
    $zipStream.Close()
    
    if (-not (Test-Path $zipFile)) {
        throw "Failed to create deployment package"
    }
    
    $zipSize = (Get-Item $zipFile).Length / 1MB
    Write-Host "  ZIP created: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Green
    
    Write-Host "Deploying Function App code via Azure CLI..." -ForegroundColor Yellow
    Write-Host "  Note: Deployment may appear to hang due to Azure CLI status polling issues with Flex Consumption" -ForegroundColor Gray
    Write-Host "  The deployment is actually proceeding in the background. We'll verify completion separately." -ForegroundColor Gray
    Write-Host ""
    
    # Start deployment in background job to prevent hanging
    $deploymentJob = Start-Job -ScriptBlock {
        param($rg, $name, $zip)
        $output = az functionapp deployment source config-zip `
            --resource-group $rg `
            --name $name `
            --src $zip `
            --timeout 300 2>&1
        return $output
    } -ArgumentList $ResourceGroupName, $functionAppName, $zipFile
    
    Write-Host "  Deployment started (running in background)..." -ForegroundColor Gray
    Write-Host "  Waiting for deployment to complete (max 5 minutes)..." -ForegroundColor Gray
    
    # Wait for deployment with timeout, checking periodically
    $timeout = 300 # 5 minutes
    $elapsed = 0
    $checkInterval = 15 # Check every 15 seconds
    
    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds $checkInterval
        $elapsed += $checkInterval
        
        # Check if job completed
        if ($deploymentJob.State -eq "Completed") {
            $deployOutput = Receive-Job -Job $deploymentJob
            Remove-Job -Job $deploymentJob
            Write-Host "  Deployment command completed" -ForegroundColor Green
            break
        }
        
        # Check if deployment actually succeeded by verifying functions
        Write-Host "  Checking deployment status... ($elapsed seconds)" -ForegroundColor Gray
        $functions = az functionapp function list --name $functionAppName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        
        if ($functions -and $functions.Count -gt 0) {
            Write-Host "  ✅ Functions detected! Deployment succeeded." -ForegroundColor Green
            Stop-Job -Job $deploymentJob -ErrorAction SilentlyContinue
            Remove-Job -Job $deploymentJob -ErrorAction SilentlyContinue
            break
        }
    }
    
    # If job is still running after timeout, stop it and verify manually
    if ($deploymentJob.State -eq "Running") {
        Write-Host "  ⚠️  Deployment command timed out, but checking if deployment actually succeeded..." -ForegroundColor Yellow
        Stop-Job -Job $deploymentJob -ErrorAction SilentlyContinue
        Remove-Job -Job $deploymentJob -ErrorAction SilentlyContinue
    }
    
    # Final verification
    Write-Host "`nVerifying deployment..." -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    $functions = az functionapp function list --name $functionAppName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    
    if ($functions -and $functions.Count -gt 0) {
        Write-Host "✅ Function App code deployed successfully! Found $($functions.Count) function(s):" -ForegroundColor Green
        foreach ($func in $functions) {
            Write-Host "  ✅ $($func.name)" -ForegroundColor Green
        }
    } else {
        Write-Host "⚠️  Functions not yet visible. They may appear in 30-60 seconds." -ForegroundColor Yellow
        Write-Host "   Check Azure Portal or run: az functionapp function list --name $functionAppName --resource-group $ResourceGroupName" -ForegroundColor Gray
        Write-Host "   Deployment may still be in progress - check the Azure Portal for status." -ForegroundColor Gray
    }
    
    # Clean up zip file
    # Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    
    Pop-Location
} catch {
    Write-Host "Error deploying Function App: $_" -ForegroundColor Red
    Pop-Location
    Write-Host "`nNote: Infrastructure is deployed. You can deploy Function App code manually later." -ForegroundColor Yellow
    # Don't exit - let the script continue to show next steps
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
