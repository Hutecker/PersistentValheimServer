# Deploy Function App to Flex Consumption
# This script creates a proper ZIP with Linux-compatible paths

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$FunctionAppName
)

Write-Host ""
Write-Host "Deploying to Flex Consumption Function App" -ForegroundColor Cyan
Write-Host "Function App: $FunctionAppName" -ForegroundColor Gray
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host ""

Push-Location functions

try {
    # Build and publish
    Write-Host "[1/4] Building and publishing..." -ForegroundColor Yellow
    dotnet publish --configuration Release --output "bin\Release\net8.0\publish" --self-contained false
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to publish project"
    }
    Write-Host "Done." -ForegroundColor Green
    
    # Verify critical files
    Write-Host "`n[2/4] Verifying published files..." -ForegroundColor Yellow
    $publishDir = Resolve-Path "bin\Release\net8.0\publish"
    $requiredFiles = @("host.json", "functions.metadata", "ValheimServerFunctions.dll", ".azurefunctions")
    foreach ($file in $requiredFiles) {
        $path = Join-Path $publishDir $file
        if (Test-Path $path) {
            Write-Host "  OK: $file" -ForegroundColor Green
        } else {
            Write-Host "  MISSING: $file" -ForegroundColor Red
            throw "Required file missing: $file"
        }
    }
    
    # Create ZIP with Linux-compatible paths (forward slashes)
    Write-Host "`n[3/4] Creating deployment ZIP..." -ForegroundColor Yellow
    $zipPath = "..\function-deploy.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    $zipStream = [System.IO.File]::Create((Join-Path (Resolve-Path "..").Path "function-deploy.zip"))
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
    
    $zipSize = (Get-Item "..\function-deploy.zip").Length / 1MB
    Write-Host "  ZIP created: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Green
    
    # Deploy to Azure
    Write-Host "`n[4/4] Deploying to Azure..." -ForegroundColor Yellow
    Write-Host "  This may take a few minutes..." -ForegroundColor Gray
    
    $result = az functionapp deployment source config-zip `
        --name $FunctionAppName `
        --resource-group $ResourceGroupName `
        --src "..\function-deploy.zip" 2>&1
    
    # Check for errors (ignore warnings)
    $errors = $result | Where-Object { $_ -match "ERROR:" -and $_ -notmatch "status code '400'" }
    if ($errors) {
        Write-Host "Deployment errors:" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    } else {
        Write-Host "  Deployment completed!" -ForegroundColor Green
    }
    
    # Clean up
    Remove-Item "..\function-deploy.zip" -Force -ErrorAction SilentlyContinue
    
    Write-Host ""
    Write-Host "Deployment complete!" -ForegroundColor Green
    Write-Host "  Endpoint: https://$FunctionAppName.azurewebsites.net/api/DiscordBot" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
