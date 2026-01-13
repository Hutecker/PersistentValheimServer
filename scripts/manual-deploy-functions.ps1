# Manual Function App Deployment Script
# Use this to test deploying functions step by step

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$FunctionAppName
)

Write-Host "Manual Function App Deployment Test" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

Push-Location functions

try {
    # Step 1: Clean previous builds
    Write-Host "[Step 1/6] Cleaning previous builds..." -ForegroundColor Yellow
    if (Test-Path "bin") {
        Remove-Item "bin" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "obj") {
        Remove-Item "obj" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "✅ Cleaned" -ForegroundColor Green
    Write-Host ""
    
    # Step 2: Restore packages
    Write-Host "[Step 2/6] Restoring NuGet packages..." -ForegroundColor Yellow
    dotnet restore
    if ($LASTEXITCODE -ne 0) {
        throw "Restore failed"
    }
    Write-Host "✅ Packages restored" -ForegroundColor Green
    Write-Host ""
    
    # Step 3: Build
    Write-Host "[Step 3/6] Building project..." -ForegroundColor Yellow
    dotnet build --configuration Release
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed"
    }
    Write-Host "✅ Build successful" -ForegroundColor Green
    Write-Host ""
    
    # Step 4: Publish (this is critical - creates functions.metadata)
    Write-Host "[Step 4/6] Publishing project..." -ForegroundColor Yellow
    Write-Host "  This creates the publish directory with all required files" -ForegroundColor Gray
    dotnet publish --configuration Release --no-build --output "bin\Release\net8.0\publish" --self-contained false
    if ($LASTEXITCODE -ne 0) {
        throw "Publish failed"
    }
    Write-Host "✅ Publish successful" -ForegroundColor Green
    Write-Host ""
    
    # Step 5: Verify files
    Write-Host "[Step 5/6] Verifying published files..." -ForegroundColor Yellow
    $publishDir = "bin\Release\net8.0\publish"
    $requiredFiles = @(
        @{Name="host.json"; Critical=$true},
        @{Name="functions.metadata"; Critical=$true},
        @{Name="extensions.json"; Critical=$true},
        @{Name="ValheimServerFunctions.dll"; Critical=$true}
    )
    
    $allPresent = $true
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $publishDir $file.Name
        if (Test-Path $filePath) {
            $size = (Get-Item $filePath).Length
            Write-Host "  ✅ $($file.Name) ($size bytes)" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $($file.Name) MISSING!" -ForegroundColor Red
            if ($file.Critical) {
                $allPresent = $false
            }
        }
    }
    
    if (-not $allPresent) {
        throw "Critical files missing from publish output"
    }
    
    # Check functions.metadata content
    Write-Host "`n  Checking functions.metadata content..." -ForegroundColor Gray
    $metadataPath = Join-Path $publishDir "functions.metadata"
    $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
    Write-Host "  Found $($metadata.value.Count) function(s):" -ForegroundColor Gray
    foreach ($func in $metadata.value) {
        Write-Host "    - $($func.name) ($($func.language))" -ForegroundColor White
    }
    Write-Host ""
    
    # Step 6: Create zip and deploy
    Write-Host "[Step 6/6] Creating deployment package..." -ForegroundColor Yellow
    $zipFile = "..\function-app-deploy.zip"
    
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force
        Write-Host "  Removed old zip file" -ForegroundColor Gray
    }
    
    Write-Host "  Zipping from: $publishDir" -ForegroundColor Gray
    Compress-Archive -Path "$publishDir\*" -DestinationPath $zipFile -Force
    
    if (-not (Test-Path $zipFile)) {
        throw "Failed to create zip file"
    }
    
    $zipSize = (Get-Item $zipFile).Length / 1MB
    Write-Host "  ✅ Zip created: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Green
    Write-Host ""
    
    # Deploy
    Write-Host "Deploying to Azure..." -ForegroundColor Yellow
    Write-Host "  Function App: $FunctionAppName" -ForegroundColor Gray
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
    Write-Host "  This may take 2-5 minutes..." -ForegroundColor Gray
    Write-Host ""
    
    az functionapp deployment source config-zip `
        --resource-group $ResourceGroupName `
        --name $FunctionAppName `
        --src $zipFile `
        --timeout 600
    
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed"
    }
    
    Write-Host ""
    Write-Host "✅ Deployment successful!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Wait 30-60 seconds for the host to restart" -ForegroundColor White
    Write-Host "  2. Check Azure Portal - functions should appear" -ForegroundColor White
    Write-Host "  3. Check logs for 'functions found' message" -ForegroundColor White
    Write-Host ""
    
    # Clean up
    Write-Host "Cleaning up..." -ForegroundColor Gray
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    
} catch {
    Write-Host ""
    Write-Host "❌ Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Debug info:" -ForegroundColor Yellow
    Write-Host "  Current directory: $(Get-Location)" -ForegroundColor Gray
    Write-Host "  Publish dir exists: $(Test-Path 'bin\Release\net8.0\publish')" -ForegroundColor Gray
    Write-Host "  Zip file exists: $(Test-Path '..\function-app-deploy.zip')" -ForegroundColor Gray
    exit 1
} finally {
    Pop-Location
}
