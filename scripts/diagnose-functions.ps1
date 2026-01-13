# Script to diagnose why functions aren't showing in Azure Portal

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$FunctionAppName
)

Write-Host "Function App Diagnostics" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor Cyan
Write-Host ""

# Check Function App status
Write-Host "1. Checking Function App status..." -ForegroundColor Yellow
$functionApp = az functionapp show `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --output json 2>$null | ConvertFrom-Json

if (-not $functionApp) {
    Write-Host "❌ Function App not found!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Function App exists: $($functionApp.name)" -ForegroundColor Green
Write-Host "   State: $($functionApp.state)" -ForegroundColor Gray
Write-Host "   Kind: $($functionApp.kind)" -ForegroundColor Gray
Write-Host ""

# Check runtime settings
Write-Host "2. Checking runtime settings..." -ForegroundColor Yellow
$settings = az functionapp config appsettings list `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --output json | ConvertFrom-Json

$workerRuntime = ($settings | Where-Object { $_.name -eq "FUNCTIONS_WORKER_RUNTIME" }).value
$dotnetVersion = ($settings | Where-Object { $_.name -eq "DOTNET_ISOLATED_WORKER_RUNTIME_VERSION" }).value
$functionsVersion = ($settings | Where-Object { $_.name -eq "FUNCTIONS_EXTENSION_VERSION" }).value

Write-Host "   FUNCTIONS_WORKER_RUNTIME: $workerRuntime" -ForegroundColor $(if ($workerRuntime -eq "dotnet-isolated") { "Green" } else { "Red" })
Write-Host "   DOTNET_ISOLATED_WORKER_RUNTIME_VERSION: $dotnetVersion" -ForegroundColor $(if ($dotnetVersion -eq "8") { "Green" } else { "Red" })
Write-Host "   FUNCTIONS_EXTENSION_VERSION: $functionsVersion" -ForegroundColor $(if ($functionsVersion -eq "~4") { "Green" } else { "Red" })
Write-Host ""

# Check if functions are registered
Write-Host "3. Checking registered functions..." -ForegroundColor Yellow
$functions = az functionapp function list `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --output json 2>$null | ConvertFrom-Json

if ($functions -and $functions.Count -gt 0) {
    Write-Host "✅ Found $($functions.Count) function(s):" -ForegroundColor Green
    foreach ($func in $functions) {
        Write-Host "   - $($func.name)" -ForegroundColor White
    }
} else {
    Write-Host "⚠️  No functions found via API (but they might still be deployed)" -ForegroundColor Yellow
}
Write-Host ""

# Test function endpoint
Write-Host "4. Testing function endpoint..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://$($functionApp.defaultHostName)/api/DiscordBot" -Method GET -TimeoutSec 10 -ErrorAction Stop
    Write-Host "✅ Function is responding! Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode -eq 404) {
        Write-Host "❌ Function returned 404 - host might not be starting" -ForegroundColor Red
        Write-Host "   This suggests the .NET isolated worker host isn't running" -ForegroundColor Yellow
    } else {
        Write-Host "⚠️  Function error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
Write-Host ""

# Recommendations
Write-Host "Recommendations:" -ForegroundColor Cyan
Write-Host "1. Check Application Insights logs in Azure Portal for startup errors" -ForegroundColor White
Write-Host "2. Verify host.json and functions.metadata are in the deployment" -ForegroundColor White
Write-Host "3. Ensure Program.cs is being executed (check for 'Host started' logs)" -ForegroundColor White
Write-Host "4. Try redeploying with: .\scripts\deploy-functions.ps1" -ForegroundColor White
Write-Host "5. Check Kudu console: https://$($functionApp.defaultHostName).scm.azurewebsites.net" -ForegroundColor White
Write-Host ""
