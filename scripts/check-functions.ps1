# Quick script to check if functions are visible

param(
    [Parameter(Mandatory=$true)]
    [string]$FunctionAppName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName
)

Write-Host "Checking Function App: $FunctionAppName" -ForegroundColor Cyan
Write-Host ""

# Check Function App status
Write-Host "[1/3] Function App Status:" -ForegroundColor Yellow
$app = az functionapp show --resource-group $ResourceGroupName --name $FunctionAppName --output json | ConvertFrom-Json
Write-Host "  State: $($app.state)" -ForegroundColor $(if ($app.state -eq "Running") { "Green" } else { "Yellow" })
Write-Host "  Host: $($app.defaultHostName)" -ForegroundColor Gray
Write-Host ""

# List functions via API (requires function key)
Write-Host "[2/3] Checking registered functions..." -ForegroundColor Yellow
try {
    # Get function keys
    $keys = az functionapp keys list --resource-group $ResourceGroupName --name $FunctionAppName --output json | ConvertFrom-Json
    $masterKey = $keys.masterKey
    
    # Try to list functions via admin API
    $functionsUrl = "https://$($app.defaultHostName)/admin/functions?code=$masterKey"
    $response = Invoke-RestMethod -Uri $functionsUrl -Method Get -ErrorAction SilentlyContinue
    
    if ($response -and $response.Count -gt 0) {
        Write-Host "  ✅ Found $($response.Count) function(s):" -ForegroundColor Green
        foreach ($func in $response) {
            Write-Host "    - $($func.name)" -ForegroundColor White
        }
    } else {
        Write-Host "  ⚠️  Could not retrieve functions via API" -ForegroundColor Yellow
        Write-Host "     (This might be normal if host is still starting)" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ⚠️  Could not check functions via API: $_" -ForegroundColor Yellow
}
Write-Host ""

# Check Application Insights logs
Write-Host "[3/3] Checking Application Insights logs..." -ForegroundColor Yellow
Write-Host "  (Check Azure Portal > Function App > Log stream for real-time logs)" -ForegroundColor Gray
Write-Host "  Or use: az monitor app-insights query --app $($app.appInsightsId) --analytics-query 'traces | take 20'" -ForegroundColor Gray

Write-Host ""
Write-Host "If functions are still not visible:" -ForegroundColor Yellow
Write-Host "  1. Wait another 30-60 seconds for host restart" -ForegroundColor White
Write-Host "  2. Check Application Insights for detailed logs" -ForegroundColor White
Write-Host "  3. Try restarting the Function App manually" -ForegroundColor White
