# Check what files are actually deployed to Azure Function App

param(
    [string]$ResourceGroupName = "valheim-server-rg",
    [string]$FunctionAppName = "valheim-func-vmaygfpvthejm"
)

Write-Host ""
Write-Host "Checking files deployed to Azure Function App" -ForegroundColor Cyan
Write-Host ""
Write-Host "Function App: $FunctionAppName" -ForegroundColor Gray
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host ""

# Get publishing credentials
Write-Host "Getting publishing credentials..." -ForegroundColor Yellow
$creds = az functionapp deployment list-publishing-credentials `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --output json | ConvertFrom-Json

if (-not $creds) {
    Write-Host "Could not get publishing credentials" -ForegroundColor Red
    exit 1
}

$username = $creds.publishingUserName
$password = $creds.publishingPassword
$authString = "${username}:${password}"
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authString))

# Check files via Kudu API
Write-Host "Checking files in wwwroot via Kudu API..." -ForegroundColor Yellow
$kuduUrl = "https://$FunctionAppName.scm.azurewebsites.net/api/vfs/site/wwwroot/"

try {
    $response = Invoke-RestMethod -Uri $kuduUrl -Method GET -Headers @{Authorization = "Basic $base64Auth"}
    
    Write-Host ""
    Write-Host "Files in wwwroot:" -ForegroundColor Yellow
    $response | Select-Object name, @{Name="Size";Expression={if($_.size){$_.size}else{"dir"}}} | Format-Table -AutoSize
    
    Write-Host ""
    Write-Host "Checking for critical files:" -ForegroundColor Yellow
    $criticalFiles = @("host.json", "functions.metadata", "extensions.json", "ValheimServerFunctions.dll")
    $allPresent = $true
    
    foreach ($file in $criticalFiles) {
        $found = $response | Where-Object { $_.name -eq $file }
        if ($found) {
            Write-Host "  OK: $file (size: $($found.size) bytes)" -ForegroundColor Green
        } else {
            Write-Host "  MISSING: $file" -ForegroundColor Red
            $allPresent = $false
        }
    }
    
    if (-not $allPresent) {
        Write-Host ""
        Write-Host "Critical files are missing from deployment!" -ForegroundColor Red
        Write-Host "The deployment may not have completed correctly." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To fix, run the manual deployment script:" -ForegroundColor Cyan
        Write-Host "  .\scripts\manual-deploy-functions.ps1 -ResourceGroupName valheim-server-rg -FunctionAppName valheim-func-vmaygfpvthejm" -ForegroundColor White
    } else {
        Write-Host ""
        Write-Host "All critical files are present!" -ForegroundColor Green
        Write-Host "If functions still do not appear, check:" -ForegroundColor Yellow
        Write-Host "  1. Worker process logs in Application Insights" -ForegroundColor White
        Write-Host "  2. FUNCTIONS_WORKER_RUNTIME is set to dotnet-isolated" -ForegroundColor White
        Write-Host "  3. DOTNET_ISOLATED_WORKER_RUNTIME_VERSION is set to 8" -ForegroundColor White
    }
    
} catch {
    Write-Host "Could not access Kudu API: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternative: Check files manually:" -ForegroundColor Yellow
    Write-Host "  1. Go to Azure Portal - Function App - Advanced Tools (Kudu)" -ForegroundColor White
    Write-Host "  2. Click Debug console - CMD" -ForegroundColor White
    Write-Host "  3. Navigate to site/wwwroot" -ForegroundColor White
    Write-Host "  4. Verify these files exist: host.json, functions.metadata, ValheimServerFunctions.dll" -ForegroundColor White
}

# Check app settings
Write-Host ""
Write-Host "Checking app settings..." -ForegroundColor Yellow
$settings = az functionapp config appsettings list `
    --resource-group $ResourceGroupName `
    --name $FunctionAppName `
    --output json | ConvertFrom-Json

$requiredSettings = @(
    @{Name="FUNCTIONS_WORKER_RUNTIME"; Expected="dotnet-isolated"},
    @{Name="FUNCTIONS_EXTENSION_VERSION"; Expected="~4"},
    @{Name="DOTNET_ISOLATED_WORKER_RUNTIME_VERSION"; Expected="8"}
)

foreach ($setting in $requiredSettings) {
    $found = $settings | Where-Object { $_.name -eq $setting.Name }
    if ($found) {
        $match = $found.value -eq $setting.Expected
        $color = if ($match) { "Green" } else { "Yellow" }
        $status = if ($match) { "OK" } else { "WARN" }
        Write-Host "  ${status}: $($setting.Name) = $($found.value) (expected: $($setting.Expected))" -ForegroundColor $color
    } else {
        Write-Host "  MISSING: $($setting.Name)" -ForegroundColor Red
    }
}

Write-Host ""
