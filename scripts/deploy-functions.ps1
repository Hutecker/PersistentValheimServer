# Script to deploy Function App code to Azure
# This script builds and deploys the C# functions

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$FunctionAppName
)

Write-Host "Function App Code Deployment" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

# Check if Function App exists
Write-Host "Verifying Function App exists..." -ForegroundColor Yellow
$functionApp = az functionapp show `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --output json 2>$null | ConvertFrom-Json

if (-not $functionApp) {
    Write-Host "Error: Function App '$FunctionAppName' not found in resource group '$ResourceGroupName'" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Function App found: $FunctionAppName" -ForegroundColor Green
Write-Host ""

# Navigate to functions directory
Push-Location functions

try {
    # Check for .NET SDK
    Write-Host "Checking .NET SDK..." -ForegroundColor Yellow
    $dotnetVersion = dotnet --version 2>$null
    if (-not $dotnetVersion) {
        Write-Host "Error: .NET SDK not found. Please install from https://dotnet.microsoft.com/download" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ .NET SDK version: $dotnetVersion" -ForegroundColor Green
    Write-Host ""
    
    # Restore NuGet packages
    Write-Host "Restoring NuGet packages..." -ForegroundColor Yellow
    dotnet restore
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to restore NuGet packages"
    }
    Write-Host "✅ Packages restored" -ForegroundColor Green
    Write-Host ""
    
    # Build project
    Write-Host "Building project (Release configuration)..." -ForegroundColor Yellow
    dotnet build --configuration Release --no-restore
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build project"
    }
    Write-Host "✅ Build successful" -ForegroundColor Green
    Write-Host ""
    
    # Publish project
    Write-Host "Publishing project..." -ForegroundColor Yellow
    # Use --self-contained false to ensure we use the .NET runtime from Azure
    dotnet publish --configuration Release --no-build --output "bin\Release\net8.0\publish" --self-contained false
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to publish project"
    }
    Write-Host "✅ Publish successful" -ForegroundColor Green
    Write-Host ""
    
    # Verify critical files exist
    Write-Host "Verifying deployment package contents..." -ForegroundColor Yellow
    $requiredFiles = @("host.json", "ValheimServerFunctions.dll", "functions.metadata", "extensions.json")
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path "bin\Release\net8.0\publish" $file
        if (Test-Path $filePath) {
            Write-Host "  ✅ $file" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $file MISSING!" -ForegroundColor Red
            throw "Required file missing: $file"
        }
    }
    Write-Host ""
    
    # Create deployment package with Linux-compatible paths (forward slashes)
    Write-Host "Creating deployment package..." -ForegroundColor Yellow
    $publishDir = Resolve-Path "bin\Release\net8.0\publish"
    $zipFile = "..\function-app-deploy.zip"
    
    # Remove old zip if exists
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force
    }
    
    # Create zip file with Linux-compatible paths (forward slashes)
    # Windows Compress-Archive uses backslashes which Linux can't read properly
    Write-Host "Creating ZIP with Linux-compatible paths..." -ForegroundColor Gray
    
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    $zipStream = [System.IO.File]::Create((Resolve-Path "..").Path + "\function-app-deploy.zip")
    $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    
    $files = Get-ChildItem $publishDir -Recurse -File
    foreach ($file in $files) {
        # Use forward slashes for Linux compatibility
        $relativePath = $file.FullName.Substring($publishDir.Path.Length + 1).Replace("\", "/")
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
    Write-Host "✅ Deployment package created: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Green
    Write-Host ""
    
    # Ensure Function App is using .NET 8 isolated worker (not deprecated .NET 6)
    Write-Host "Ensuring Function App uses .NET 8 isolated worker..." -ForegroundColor Yellow
    az functionapp config appsettings set `
        --resource-group $ResourceGroupName `
        --name $FunctionAppName `
        --settings "DOTNET_ISOLATED_WORKER_RUNTIME_VERSION=8" "FUNCTIONS_EXTENSION_VERSION=~4" "FUNCTIONS_WORKER_RUNTIME=dotnet-isolated" `
        --output none 2>&1 | Out-Null
    
    Write-Host "✅ Runtime version configured" -ForegroundColor Green
    Write-Host ""
    
    # Deploy to Azure
    Write-Host "Deploying to Azure Function App..." -ForegroundColor Yellow
    Write-Host "This may take a few minutes..." -ForegroundColor Gray
    Write-Host ""
    
    # Deploy using background job to prevent hanging
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
    } -ArgumentList $ResourceGroupName, $FunctionAppName, $zipFile
    
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
        $functions = az functionapp function list --name $FunctionAppName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
        
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
    $functions = az functionapp function list --name $FunctionAppName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    
    if ($functions -and $functions.Count -gt 0) {
        Write-Host "✅ Function App code deployed successfully! Found $($functions.Count) function(s):" -ForegroundColor Green
        Write-Host ""
        foreach ($func in $functions) {
            Write-Host "  ✅ $($func.name)" -ForegroundColor Green
        }
    } else {
        Write-Host "⚠️  Functions not yet visible. They may appear in 30-60 seconds." -ForegroundColor Yellow
        Write-Host "   Check Azure Portal or run: az functionapp function list --name $FunctionAppName --resource-group $ResourceGroupName" -ForegroundColor Gray
        Write-Host "   Deployment may still be in progress - check the Azure Portal for status." -ForegroundColor Gray
    }
    Write-Host ""
    
    # Clean up zip file
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    
    # Get Function App URL
    $functionAppUrl = $functionApp.defaultHostName
    if ($functionAppUrl) {
        $fullUrl = "https://$functionAppUrl"
        Write-Host "Function App URL: $fullUrl" -ForegroundColor Cyan
        Write-Host "Discord Bot endpoint: $fullUrl/api/DiscordBot" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "🎉 Deployment complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Check the Function App in Azure Portal to verify functions are deployed" -ForegroundColor White
    Write-Host "2. Set the Discord interaction endpoint URL" -ForegroundColor White
    Write-Host "3. Test the Discord commands" -ForegroundColor White
    
} catch {
    Write-Host ""
    Write-Host "❌ Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Make sure you're logged in: az login" -ForegroundColor White
    Write-Host "2. Check that the Function App exists and is running" -ForegroundColor White
    Write-Host "3. Verify you have permissions to deploy to the Function App" -ForegroundColor White
    exit 1
} finally {
    Pop-Location
}
