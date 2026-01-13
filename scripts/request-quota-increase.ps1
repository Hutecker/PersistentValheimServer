# Script to help request quota increase for Function Apps
# This opens the Azure Portal to request quota increase

param(
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = ""
)

if ([string]::IsNullOrEmpty($SubscriptionId)) {
    $account = az account show --output json | ConvertFrom-Json
    $SubscriptionId = $account.id
}

Write-Host "Opening Azure Portal to request quota increase..." -ForegroundColor Yellow
Write-Host "Subscription: $SubscriptionId" -ForegroundColor Cyan
Write-Host "Location: $Location" -ForegroundColor Cyan
Write-Host ""

$portalUrl = "https://portal.azure.com/#@/resource/subscriptions/$SubscriptionId/providers/Microsoft.Compute/locations/$Location/usages"

Write-Host "Portal URL: $portalUrl" -ForegroundColor Green
Write-Host ""
Write-Host "Steps to request quota:" -ForegroundColor Yellow
Write-Host "1. Portal will open (or copy the URL above)" -ForegroundColor White
Write-Host "2. Find the quota request form" -ForegroundColor White
Write-Host "3. When prompted for 'Compute Tier', select: Y" -ForegroundColor Cyan
Write-Host "   (Y tier = Consumption plan = Dynamic - this is what you need!)" -ForegroundColor Green
Write-Host "4. Set the new limit to at least 10" -ForegroundColor White
Write-Host "5. Region: $Location" -ForegroundColor White
Write-Host "6. Reason: 'Function Apps for Valheim server Discord bot'" -ForegroundColor White
Write-Host "7. Submit the request (usually approved in 24-48 hours)" -ForegroundColor White
Write-Host ""
Write-Host "NOTE: Y tier = Consumption plan (Y1) = Dynamic VMs" -ForegroundColor Yellow
Write-Host "      This is the cost-effective pay-per-execution plan" -ForegroundColor Yellow
Write-Host ""

Start-Process $portalUrl
