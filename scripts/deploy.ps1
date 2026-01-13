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
    [string]$SubscriptionId = ""
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
    
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed with exit code $LASTEXITCODE"
    }
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
    
    Write-Host "Publishing project..." -ForegroundColor Yellow
    dotnet publish --configuration Release --no-build --output "bin\Release\net8.0\publish" --self-contained false
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to publish project"
    }
    
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
    
    Write-Host "Creating deployment package..." -ForegroundColor Yellow
    
    $zipFile = "..\function-app-deploy.zip"
    
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force
    }
    
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
    
    $timeout = 300
    $elapsed = 0
    $checkInterval = 15
    
    while ($elapsed -lt $timeout) {
        Start-Sleep -Seconds $checkInterval
        $elapsed += $checkInterval
        
        if ($deploymentJob.State -eq "Completed") {
            $deployOutput = Receive-Job -Job $deploymentJob
            Remove-Job -Job $deploymentJob
            Write-Host "  Deployment command completed" -ForegroundColor Green
            break
        }
        
        Write-Host "  Checking deployment status... ($elapsed seconds)" -ForegroundColor Gray
        $functions = az functionapp function list --name $functionAppName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        
        if ($functions -and $functions.Count -gt 0) {
            Write-Host "  ✅ Functions detected! Deployment succeeded." -ForegroundColor Green
            Stop-Job -Job $deploymentJob -ErrorAction SilentlyContinue
            Remove-Job -Job $deploymentJob -ErrorAction SilentlyContinue
            break
        }
    }
    
    if ($deploymentJob.State -eq "Running") {
        Write-Host "  ⚠️  Deployment command timed out, but checking if deployment actually succeeded..." -ForegroundColor Yellow
        Stop-Job -Job $deploymentJob -ErrorAction SilentlyContinue
        Remove-Job -Job $deploymentJob -ErrorAction SilentlyContinue
    }
    
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
    
    if (Test-Path $zipFile) {
        Write-Host "Cleaning up deployment ZIP file..." -ForegroundColor Gray
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
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
